package RaumZeitChef::IRC;
use v5.14;
use utf8;

use Moose::Role;
use RaumZeitChef::IRC::Event;

use RaumZeitChef::Log;

use Carp ();
use Encode 'decode_utf8';
use AnyEvent::IRC::Util 'prefix_nick';
use AnyEvent::IRC::Client;

has irc => (is => 'ro', default => sub { AnyEvent::IRC::Client->new });

before run => sub {
    my ($self) = @_;
    $self->irc->set_exception_cb(sub {
        my ($e, $event) = @_;
        Carp::cluck("caught exception in event '$event': $e");
    });

    for my $attr ($self->meta->get_all_attributes) {
        next unless $attr->does('RaumZeitChef::Trait::IRC::Event');
        my $name = $attr->event_name;
        my $cb = $attr->code;
        $self->irc->reg_cb($name => sub { $self->$cb(@_) });
        log_debug("registered event $name");
    }

};

event connect => sub {
    my ($self, $irc, $err) = @_;
    return unless defined $err;

    log_info("Connect error: $err");
    $self->cv->send;
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
        if ($irc->nick() ne $self->nick) {
            log_info('trying to get back my nick...');
            $irc->send_srv('NICK', $self->nick);
        } else {
            log_info('got my nick back.');
            $nc_timer = undef;
        }
    });
};

event disconnect => sub { shift->cv->send };

event publicmsg => sub {
    my ($self, $irc, $channel, $ircmsg) = @_;
    my $line = $ircmsg->{params}->[1];
    my $text = decode_utf8($line); # decode_n_filter($line);
    my $from_nick = decode_utf8(prefix_nick($ircmsg->{prefix}));

    # for now, commands cannot be added at runtime
    # so it is okay to cache them
    state $actions ||= $self->plugin_factory->build_all_actions;

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

sub say {
    my ($self, $msg) = @_;

    my $channel = $self->channel;
    $self->call_after_joined(send_long_message => 'utf8', 0, 'PRIVMSG', $channel, $msg);
}

# defers method calls on ->irc until we joined our ->channel
sub call_after_joined {
    my ($self, $method, @args) = @_;

    my $channel = $self->channel;

    return $self->irc->$method(@args)
        if $self->irc->channel_list($channel);

    # XXX unusable right now, need to walk the stackframes
    # XXX to filter out RaumZeitChef::IRC::say
    my (undef, $file, $line) = caller;
    log_debug("deferred $method, called from $file:$line");

    my $defer;
    $defer = sub {
        $self->irc->$method(@args);
        $self->irc->unreg_cb($defer);
        # get rid (hopefully) of the circular dependency
        undef $defer;
    };

    $self->irc->reg_cb(join => $defer);
}

# defers method calls on ->irc until we got +o in ->channel
sub call_after_oped {
    my ($self, $method, @args) = @_;

    my $channel = $self->channel;
    my $mode = $self->irc->nick_modes($channel, $self->irc->nick);
    # channel_nickmode_update
    return $self->irc->$method(@args)
        if $mode and $mode->{o};

    my (undef, $file, $line) = caller;
    my $method_called_from = "$method, called from $file:$line";
    log_debug("deferred $method_called_from");

    my $defer;
    $defer = sub {
        my (undef, $dest) = @_;

        if ($dest ne $self->irc->nick) {
            log_debug("waiting for op, got '$dest' [$method_called_from]");
            return;
        }

        my $mode = $self->irc->nick_modes($channel, $self->irc->nick);
        unless ($mode and $mode->{o}) {
            log_debug("still waiting for op [$method_called_from]");
            return;
        }

        log_debug("got op, calling $method_called_from");

        $self->irc->$method(@args);
        $self->irc->unreg_cb($defer);
        # get rid (hopefully) of the circular dependency
        undef $defer;
    };

    $self->irc->reg_cb(channel_nickmode_update => $defer);
}


no Moose::Role;

1;
