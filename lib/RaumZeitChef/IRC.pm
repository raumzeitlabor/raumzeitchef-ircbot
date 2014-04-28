package RaumZeitChef::IRC;
use v5.14;
use utf8;

use Moose;
use RaumZeitChef::IRC::Event;

use RaumZeitChef::Log;

use Carp ();
use Encode 'decode_utf8';
use AnyEvent::IRC::Util 'prefix_nick';
use AnyEvent::IRC::Client;

has '_client' => (is => 'ro', default => sub { AnyEvent::IRC::Client->new });
has 'disconnect_cv' => (is => 'rw', default => sub { AE::cv });

has config => (
    is => 'ro',
    isa => 'RaumZeitChef::Config',
    required => 1,
    handles => [qw/server port nick channel nickserv_password/],
);

has chef => (is => 'ro');

no Moose;

sub BUILD {
    my ($self) = @_;
    $self->_client->set_exception_cb(sub {
        my ($e, $event) = @_;
        Carp::cluck("caught exception in event '$event': $e");
    });

    for my $attr ($self->meta->get_all_attributes) {
        next unless $attr->does('RaumZeitChef::Trait::IRC::Event');
        my $name = $attr->event_name;
        my $cb = $attr->code;
        my $obj;
        my $event_pkg = $attr->event_package;
        if ($event_pkg eq $self->meta->name) {
            $obj = $self;
        }
        elsif (my $plugin_obj = $self->chef->plugin_factory->get_plugin_instance($event_pkg)) {
            $obj = $plugin_obj;
        }
        else {
            Carp::carp("error while making RaumZeitChef::IRC::Event: unrecognized $event_pkg");
        }

        $self->_client->reg_cb($name => sub { $obj->$cb(@_) });
        log_debug("registered event $name");
    }

}

event connect => sub {
    my ($self, $irc, $err) = @_;
    return unless defined $err;

    log_info("Connect error: $err");
    $self->disconnect_cv->send;
};

event registered => sub {
    my ($self, $irc) = @_;
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
};

event disconnect => sub {
    my ($self, $irc, $reason) = @_;
    log_critical("disconnected from server: '$reason'");
    $self->disconnect_cv->send;
};

event error => sub {
    my ($self, $irc, $code, $msg) = @_;
    if ($code ne 'ERROR') {
        $code = AnyEvent::IRC::Util::rfc_code_to_name($code);
    }
    log_error("got error message from server: $code '$msg'");
};

event publicmsg => sub {
    my ($self, $irc, $channel, $ircmsg) = @_;
    my $line = $ircmsg->{params}->[1];
    my $text = decode_utf8($line); # decode_n_filter($line);
    my $from_nick = decode_utf8(prefix_nick($ircmsg->{prefix}));

    # for now, commands cannot be added at runtime
    # so it is okay to cache them
    state $actions = $self->chef->plugin_factory->build_all_actions;

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
};

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
