package RaumZeitChef::IRC;
use RaumZeitChef::Role;
use v5.14;
use utf8;
use Sys::Syslog;
use Carp ();
use Encode qw/decode_utf8/;

use AnyEvent::IRC::Client;
use Method::Signatures::Simple;

requires qw(
    server port
    nick channel
    nickserv_pw
    cv
);

has irc => (is => 'ro', default => method {
    my $irc = AnyEvent::IRC::Client->new();
    $irc->set_exception_cb(func ($e, $event) {
        Carp::cluck("caught exception in event '$event': $e");
    });
    my %events = $self->get_events;
    for my $name (keys %events) {
        for my $cb (@{ $events{$name} }) {
            $irc->reg_cb($e => sub { $self->$cb(@_) });
        }
    }
    return $irc;
});

method say ($msg) {
    $self->irc->send_long_message('utf8', 0, 'PRIVMSG', $self->channel, $msg);
}

event connect => method ($irc, $err) {
    return unless defined $err;

    syslog('info', "Connect error: $err");
    $self->cv->send;
};

event registered => method ($irc) {
    syslog('info', 'Connected, joining channel');
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
            syslog('info', 'trying to get back my nick...');
            $irc->send_srv('NICK', $self->nick);
        } else {
            syslog('info', 'got my nick back.');
            $nc_timer = undef;
        }
    });
};

event disconnect => method { $self->cv->send };

event publicmsg => method ($irc, $channel, $ircmsg) {
    # transform raw byte string into an utf8 string
    my $text = decode_utf8($ircmsg->{params}->[1]);

    # for now, commands cannot be added at runtime
    # so it is okay to cache them
    state %commands ||= $self->get_commands;

    for my $cmd_name (keys %commands) {
        if ($text =~ $commands{$cmd_name}{rx}) {
            my $cb = $commands{$cmd_name}{cb};
            my $match = { %+ };
            $self->$cb($ircmsg, $match);
        }
    }

    # disabled
    #if ($text =~ /^!help/) {
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
    #}
};

1;
