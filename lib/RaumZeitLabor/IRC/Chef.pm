package RaumZeitLabor::IRC::Chef;
# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)

use strict;
use warnings;
use v5.10;
use utf8;

# These modules are in core:
use Sys::Syslog;
# All these modules are not in core:
use AnyEvent;
use AnyEvent::HTTPD;
use JSON::XS;

use parent 'AnyEvent::IRC::Client';
use RaumZeitLabor::IRC::Chef::Commands qw/MPD Ping Erinner/;

our $VERSION = '1.7';

sub run {
    my ($class) = @_;
    my $server = "irc.hackint.net";
    my $port = 6667;
    my $nick = "RaumZeitChef";
    my @channels = ('#raumzeitlabor');

    openlog('ircbot-chef', 'pid', 'daemon');
    syslog('info', 'Starting up');

    while (1) {
        syslog('info', "Connecting to $server as $nick...");
        my $old_status = "";
        my $c = AnyEvent->condvar;
        my $conn = $class->new;
        my $httpd = AnyEvent::HTTPD->new(host => '127.0.0.1', port => 9091);

        $httpd->reg_cb(
            '/to_irc' => sub {
                my ($httpd, $req) = @_;

                if (!defined($req->{'content'})) {
                    $req->respond({ content => [
                        'text/plain',
                        'No content received. Please post JSON'
                    ]});
                    return;
                }

                my $decoded = decode_json($req->{'content'});
                $conn->say($channels[0], $decoded->{message});

                $req->respond({ content => [
                    'text/html',
                    '{"success":true}'
                ]});
            }
        );

        $conn->reg_cb(
            connect => sub {
                my ($conn, $err) = @_;

                if (defined($err)) {
                    syslog('info', "Connect error: $err");
                    $c->send;
                    return;
                }
            });

        $conn->reg_cb(
            registered => sub {
                syslog('info', 'Connected, joining channels');
                $conn->send_srv(JOIN => $_) for @channels;

                # Send a PING every 30 seconds. If no PONG is received within
                # another 30 seconds, the connection will be closed and a reconnect
                # will be triggered.
                $conn->enable_ping(30);

                # if nick differs from one we set on connect (due to a
                # nick-collision), we try to rename every once in a while.
                my $nc_timer;
                $nc_timer = AnyEvent->timer(interval => 30, cb => sub {
                    if ($conn->nick() ne $nick) {
                        syslog('info', 'trying to get back my nick...');
                        $conn->send_srv('NICK', $nick);
                    } else {
                        syslog('info', 'got my nick back.');
                        $nc_timer = undef;
                    }
                });
            });

        $conn->reg_cb(disconnect => sub { $c->send });

        my %command_whitelist = RaumZeitLabor::IRC::Chef::Commands->commands;
        $conn->reg_cb(publicmsg => sub {
                my ($conn, $channel, $ircmsg) = @_;
                my $text = $ircmsg->{params}->[1];

                if (my ($cmd, $rest) = $text =~ /^!(\w+)\s*(.*)\s*$/) {
                    if (my $cb = $command_whitelist{$cmd}) {
                        $cb->($conn, $channel, $ircmsg, $cmd, $rest);
                    }
                }

                # disabled
                #if ($text =~ /^!help/) {
                #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
                #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
                #}
        });

        $conn->connect($server, $port, { nick => $nick, user => 'RaumZeitChef' });
        $c->recv;

        # Wait 5 seconds before reconnecting, else we might get banned
        syslog('info', 'Connection lost.');
        sleep 5;
    }
}

sub say {
    my ($self, $channel, $msg) = @_;
    $self->send_long_message('utf8', 0, 'PRIVMSG', $channel, $msg);
}

1

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
