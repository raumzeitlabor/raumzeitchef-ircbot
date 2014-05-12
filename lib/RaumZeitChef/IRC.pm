package RaumZeitChef::IRC;
use v5.14;
use utf8;

use Moose;

use RaumZeitChef::Log;

use Carp ();
use Encode 'decode_utf8';
use AnyEvent::IRC::Util 'prefix_nick';
use AnyEvent::IRC::Client;

has '_client' => (
    is => 'ro',
    lazy => 1,
    builder => '_irc_client_builder',
);

has 'disconnect_cv' => (is => 'rw', default => sub { AE::cv });

has config => (
    is => 'ro',
    isa => 'RaumZeitChef::Config',
    required => 1,
    handles => [qw/server port nick channel nickserv_password/],
);

has actions => (
    is => 'ro',
    required => 1,
    traits => ['Array'],
    default => sub { [] },
    handles => {
        add_action => 'push',
    },
);

no Moose;

sub _irc_client_builder {
    my ($self) = @_;

    my $irc = AnyEvent::IRC::Client->new(send_initial_whois => 1);

    $irc->enable_ssl if $self->config->tls;

    $irc->set_exception_cb(sub {
        my ($e, $event) = @_;
        Carp::cluck("caught exception in event '$event': $e");
    });

    my @callbacks = qw/connect registered disconnect error publicmsg/;

    for my $name (@callbacks) {
        $irc->reg_cb($name => $self->_generate_cb("${name}_cb"));
    }

    return $irc;
}

sub _generate_cb {
    my ($self, $name) = @_;

    # XXX Currently we resolve the method at runtime,
    # XXX ideally it the closure should be generated
    # XXX at BUILD time
    return sub {
        shift; # don't leak AnyEvent::IRC::Client object
        if (my $sub = $self->can($name)) {
            $self->$sub(@_);
        }
    };
}

sub add_event {
    my ($self, $event) = @_;

    $self->_client->reg_cb(@$event);
}

sub connect_cb {
    my ($self, $err) = @_;
    return unless defined $err;

    log_info("Connect error: $err");
    $self->disconnect_cv->send;
}

sub registered_cb {
    my ($self) = @_;
    my $irc = $self->_client;
    log_info('Connected, joining channel');
    if (my $pw = $self->nickserv_password) {
        $irc->send_srv(PRIVMSG => 'NickServ', (join ' ', 'identify', $self->nick, $pw));
    }
    $irc->send_srv(JOIN => $self->channel);

    # Send a PING every 30 seconds. If no PONG is received within
    # another 30 seconds, the connection will be closed and a reconnect
    # will be triggered.
    $irc->enable_ping(30);

    # if nick differs from one we set on connect (due to a
    # nick-collision), we try to rename every once in a while.
    my $nc_timer;
    $nc_timer = AnyEvent->timer(interval => 30, cb => sub {
        if ($irc->nick ne $self->config->nick) {
            log_info('trying to get back my nick...');
            $irc->send_srv('NICK', $self->config->nick);
        } else {
            log_info('got my nick back.');
            $nc_timer = undef;
        }
    });
}

sub disconnect_cb {
    my ($self, $reason) = @_;
    log_critical("disconnected from server: '$reason'");
    $self->disconnect_cv->send;
}

sub error_cb {
    my ($self, $code, $msg) = @_;
    if ($code ne 'ERROR') {
        $code = AnyEvent::IRC::Util::rfc_code_to_name($code);
    }
    log_error("got error message from server: $code '$msg'");

    # TODO: read RFC 1459 and confirm we want to disconnect here
}

sub publicmsg_cb {
    my ($self, $channel, $ircmsg) = @_;
    my $line = $ircmsg->{params}->[1];
    my $text = decode_utf8($line); # decode_n_filter($line);
    my $from_nick = decode_utf8(prefix_nick($ircmsg->{prefix}));

    my $actions = $self->actions;

    for my $act (@$actions) {
        my ($rx, $cb) = @$act;
        if ($text =~ /$rx/) {
            my $msg = { %+ };
            die "regex must not have 'text' capture group"
                if exists $msg->{text};

            $msg->{text} = $text;
            $msg->{from} = $from_nick;
            $cb->($ircmsg, $msg);
            # TODO should we return here? don't return based on $cb return value…
            # also: don't return after the first found command, this might kill smth. like:
            # !erinner mich an http://example.com in 1s
        }
    }

    # disabled
    #if ($text =~ /^!help/) {
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
    #}
}

sub wait_for_disconnect {
    my ($self) = @_;

    # XXX $err not used yet
    my $err = $self->disconnect_cv->recv;
    $self->disconnect_cv(AE::cv);
    return $err;
}

sub say {
    my ($self, $msg) = @_;

    my $channel = $self->channel;
    $self->call_after_joined(send_long_message => 'utf8', 0, 'PRIVMSG', $channel, $msg);
}

# defers method calls on ->irc until we joined our ->channel
sub call_after_joined {
    my ($self, $method, @args) = @_;

    my $channel = $self->channel;

    return $self->_client->$method(@args)
        if $self->_client->channel_list($channel);

    # XXX unusable right now, need to walk the stackframes
    # XXX to filter out RaumZeitChef::IRC::say
    my (undef, $file, $line) = caller;
    log_debug("deferred $method, called from $file:$line");

    my $defer;
    $defer = sub {
        $self->_client->$method(@args);
        $self->_client->unreg_cb($defer);
        # get rid (hopefully) of the circular dependency
        undef $defer;
    };

    $self->_client->reg_cb(join => $defer);
}

# defers method calls on ->irc until we got +o in ->channel
sub call_after_oped {
    my ($self, $method, @args) = @_;

    my $channel = $self->channel;
    my $mode = $self->_client->nick_modes($channel, $self->_client->nick);
    # channel_nickmode_update
    return $self->_client->$method(@args)
        if $mode and $mode->{o};

    my (undef, $file, $line) = caller;
    my $method_called_from = "$method, called from $file:$line";
    log_debug("deferred $method_called_from");

    my $defer;
    $defer = sub {
        my ($irc, $channel, $dest) = @_;

        if ($dest ne $self->_client->nick) {
            log_debug("waiting for op, got '$dest' [$method_called_from]");
            return;
        }

        my $mode = $self->_client->nick_modes($channel, $self->_client->nick);
        unless ($mode and $mode->{o}) {
            log_debug("still waiting for op [$method_called_from]");
            return;
        }

        log_debug("got op, calling $method_called_from");

        $self->_client->$method(@args);
        $self->_client->unreg_cb($defer);
        # get rid (hopefully) of the circular dependency
        undef $defer;
    };

    $self->_client->reg_cb(channel_nickmode_update => $defer);
}

1;
