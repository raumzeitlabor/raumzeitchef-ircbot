package RaumZeitLabor::IRC::MPD;
# vim:ts=4:sw=4:expandtab
# © 2010-2011 Michael Stapelberg (see also: LICENSE)

use strict;
use warnings;
use v5.10;
# All these modules are not in core:
use AnyEvent;
use AnyEvent::IRC::Client;
use Audio::MPD;
use IO::All;

our $VERSION = '1.0';

sub mpd_play_existing_song {
    my ($mpd, $playlist, $url) = @_;
    # Search for the song
    my @items = $playlist->as_items;
    for my $item (@items) {
        next if $item->file ne $url;
        say "Found $url (file is " . $item->file . ", id is " . $item->id . "), playing";
        $mpd->playid($item->id);
        return 1;
    }
    return 0;
}

sub mpd_change_url {
    my $url = shift;
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    say "Connected to mpd.rzl.";

    my $playlist = $mpd->playlist;

    if (!mpd_play_existing_song($mpd, $playlist, $url)) {
        say "Adding $url to playlist";
        $playlist->add($url);
        $playlist = $mpd->playlist;
        if (!mpd_play_existing_song($mpd, $playlist, $url)) {
            say "err, what?";
        }
    }
}

sub mpd_current_song {
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    say "Connected to mpd.rzl.";

    my $song = $mpd->current;
    my $name;
    my $totsec = $mpd->status->time->seconds_total;
    my $cursec = $mpd->status->time->seconds_sofar;
    my $tottime = sprintf("%d:%02d",int($totsec / 60),$totsec - (60 * int($totsec / 60)));
    my $curtime = sprintf("%d:%02d",int($cursec / 60),$cursec - (60 * int($cursec / 60)));
    my $lefttime = $mpd->status->time->left;
    my $time = $curtime.'/'.$tottime;

    my $playlist = $mpd->playlist;
    if (defined($song->artist) && defined($song->album)) {
        $name = $song->artist . ": " . $song->album;
    } else {
        $name = $song->name;
    }
    return "Playing: $name (" . $song->file . " " . $time . ")";
}

sub run {
    my $server = "irc.hackint.net";
    my $port = 6667;
    my $nick = "RaumZeitMPD";
    my @channels = ('#raumzeitlabor');
    my $last_ping = 0;
    my $said_idiot = 0;
    my $disable_timer = undef;
    my $disable_bell = undef;

    while (1) {
        print "Connecting...\n";
        my $old_status = "";
        my $c = AnyEvent->condvar;
        my $conn = AnyEvent::IRC::Client->new;

        $conn->reg_cb(
            registered => sub {
                say "Connected, joining channels";
                $conn->send_srv(JOIN => $_) for @channels;

                # Send a PING every 30 seconds. If no PONG is received within
                # another 30 seconds, the connection will be closed and a reconnect
                # will be triggered.
                $conn->enable_ping(30);
            });

        $conn->reg_cb(disconnect => sub { $c->broadcast });

        $conn->reg_cb(
            publicmsg => sub {
                my ($conn, $channel, $ircmsg) = @_;
                my $text = $ircmsg->{params}->[1];

                if ($text =~ /^!stream/) {
                    my ($url) = ($text =~ /^!stream (.+)$/);
                    if (!defined($url) || length($url) == 0) {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, mpd_current_song()));
                    } else {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Playing $url"));
                        mpd_change_url($url);
                    }
                }
                if ($text =~ /^!help/) {
                    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
                    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
                }

                if ($text =~ /^!ping/) {
                    print "time = " . time() . ", last_ping = $last_ping, diff = " . (time() - $last_ping) . "\n";
                    if ((time() - $last_ping) < 180) {
                        if (!$said_idiot) {
                            $conn->send_chan($channel, 'PRIVMSG', ($channel, "Hey! Nur einmal alle 3 Minuten!"));
                            $said_idiot = 1;
                        }
                    } else {
                        $last_ping = time();
                        print "last_ping = $last_ping\n";
                        $said_idiot = 0;
                        '1' > io('http://172.22.36.1:5000/port/8');
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Die Rundumleuchte wurde für 5 Sekunden aktiviert"));
                        $disable_timer = AnyEvent->timer(after => 5, cb => sub {
                            '0' > io('http://172.22.36.1:5000/port/8');
                        });
                    }
                }
            });

        $conn->connect($server, $port, { nick => $nick, user => 'mpd' });
        $c->wait;

        # Wait 5 seconds before reconnecting, else we might get banned
        sleep 5;
    }
}

1

__END__


=head1 NAME

RaumZeitMPD - RaumZeitMPD IRC bot

=head1 DESCRIPTION

This module is an IRC bot (nickname RaumZeitMPD) which displays the currently
playing song (querying the MPD) upon !stream and enables a light upon !ping.

=head1 VERSION

Version 1.0

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2011 Michael Stapelberg.

This program is free software; you can redistribute it and/or modify it
under the terms of the BSD license.

=cut
