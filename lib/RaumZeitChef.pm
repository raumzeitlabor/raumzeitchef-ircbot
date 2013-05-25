# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)
package RaumZeitChef 1.7;
use v5.14;
use utf8;

use RaumZeitChef::Moose;

# These modules are in core:
use Sys::Syslog;
# All these modules are not in core:
use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::HTTPD;
use JSON::XS;
use Method::Signatures::Simple;

has server => (is => 'ro', default => 'irc.hackint.net');
has port => (is => 'ro', default => 6667);
has nick => (is => 'ro', default => 'RaumZeitChef');
has channel => (is => 'ro', default => '#raumzeitlabor');


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

has cv => (is => 'rw', default => sub { AE::cv });

has httpd => (is => 'ro', default => method {
    my $httpd = AnyEvent::HTTPD->new(host => '127.0.0.1', port => 9091);
    $httpd->reg_cb( '/to_irc' => sub {
        my ($httpd, $req) = @_;

        my $no_content = ['text/plain', 'No content received. Please post JSON'];
        my $success = ['text/html', '{"success":true}'];

        if (not $req->{content}) {
            $req->respond({ content => $no_content });
            return;
        }

        my $decoded = decode_json($req->{content});
        $self->say($decoded->{message});

        $req->respond({ content => $success });
    });
    return $httpd;
});

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

use RaumZeitChef::Commands qw/MPD Ping Erinner/;

sub run {
    my ($class) = @_;
    my $self = $class->new();
    my $nick = $self->nick;
    my $server = $self->server;

    openlog('ircbot-chef', 'pid', 'daemon');
    syslog('info', 'Starting up');

    while (1) {
        syslog('info', "Connecting to $server as $nick...");

        $self->irc->connect($self->server, $self->port, { nick => $self->nick, user => 'RaumZeitChef' });
        $self->cv->recv;

        $self->cv(AE::cv);

        # Wait 5 seconds before reconnecting, else we might get banned
        syslog('info', 'Connection lost.');
        sleep 5;
    }
}

method say ($msg) {
    $self->irc->send_long_message('utf8', 0, 'PRIVMSG', $self->channel, $msg);
}

1;

__END__


=head1 NAME

RaumZeitMPD - RaumZeitMPD IRC bot

=head1 DESCRIPTION

This module is an IRC bot (nickname RaumZeitMPD) which displays the currently
playing song (querying the MPD) upon !stream and enables a light upon !ping.

=head1 VERSION

Version 1.6

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Michael Stapelberg.

This program is free software; you can redistribute it and/or modify it
under the terms of the BSD license.

=cut
