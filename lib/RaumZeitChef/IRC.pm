package RaumZeitChef::IRC;
use RaumZeitChef::Role;
use v5.14;
use utf8;

use AnyEvent::IRC::Client;
use Method::Signatures::Simple;

has irc => (is => 'ro', default => method {
    my $irc = AnyEvent::IRC::Client->new();
    my %events = $self->get_events;
    for my $e (keys %events) {
        for my $cb (@{ $events{$e} }) {
            $irc->reg_cb($e => $cb);
        }
    }
    return $irc;
});

method say ($msg) {
    my $encoding = utf8::is_utf8($msg) ? undef : 'utf8';
    $self->irc->send_long_message($encoding, 0, 'PRIVMSG', $self->channel, $msg);
}

event connect => method ($irc, $err) {
    return unless defined $err;

    syslog('info', "Connect error: $err");
    $self->cv->send;
};

event registered => method ($irc) {
    syslog('info', 'Connected, joining channel');
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
    my $text = $ircmsg->{params}->[1];

    my %commands = $self->get_commands;
    if (my ($cmd, $rest) = $text =~ /^!(\w+)\s*(.*)\s*$/) {
        if (my $cb = $commands{$cmd}) {
            $cb->($irc, $channel, $ircmsg, $cmd, $rest);
        }
    }

    # disabled
    #if ($text =~ /^!help/) {
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
    #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
    #}
};

1;
