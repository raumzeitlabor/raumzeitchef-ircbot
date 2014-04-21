package RaumZeitChef::IRC;
use RaumZeitChef::Plugin;
use v5.14;
use utf8;

use RaumZeitChef::Log;

use Carp ();
use Encode 'decode_utf8';
use AnyEvent::IRC::Util 'prefix_nick';
use AnyEvent::IRC::Client;

requires qw( server port nick channel nickserv_pw cv );

has irc => (is => 'ro', default => method {
    my $irc = AnyEvent::IRC::Client->new;

    $irc->set_exception_cb(func ($e, $event) {
        Carp::cluck("caught exception in event '$event': $e");
    });

    for my $attr ($self->meta->get_all_attributes) {
        next unless $attr->does('RaumZeitChef::Trait::IrcEvent');
        my $name = $attr->event_name;
        my $cb = $attr->code;
        $irc->reg_cb($name => sub { $self->$cb(@_) });
    }

    return $irc;
});


event connect => sub {
    my ($self, $irc, $err) = @_;
    return unless defined $err;

    log_info("Connect error: $err");
    $self->cv->send;
};

event registered => sub {
    my ($self, $irc) = @_;
    log_info('Connected, joining channel');
    if (my $pw = $self->nickserv_pw) {
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
    state $commands ||= [ $self->get_all_commands ];

    for my $cmd (@$commands) {
        my ($name, $rx, $cb) = @$cmd;
        if ($text =~ $rx) {
            my $msg = { %+ };
            die "regex must not have 'text' capture group"
                if exists $msg->{text};

            $msg->{text} = $text;
            $msg->{from} = $from_nick;
            $self->$cb($ircmsg, $msg);
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
    $self->irc->send_long_message('utf8', 0, 'PRIVMSG', $self->channel, $msg);
}

sub get_all_commands {
    my ($self) = @_;
    return map {
        [ $_->command_name, $_->match_rx, $_->code ]
    } grep {
        $_->does('RaumZeitChef::Trait::Command')
    } $self->meta->get_all_attributes;
}


no Moose::Role;

1;
