package RaumZeitLabor::IRC::Chef;
# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)

use strict;
use warnings;
use v5.10;
# These modules are in core:
use Sys::Syslog;
use POSIX qw(strftime);
# All these modules are not in core:
use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::HTTPD;
use AnyEvent::IRC::Client;
use Audio::MPD;
use JSON::XS;
use HTTP::Request::Common ();

our $VERSION = '1.6';

sub mpd_play_existing_song {
    my ($mpd, $playlist, $url) = @_;
    # Search for the song
    my @items = $playlist->as_items;
    for my $item (@items) {
        next if $item->file ne $url;
        syslog('info', "Found $url (file is " . $item->file . ", id is " . $item->id . "), playing");
        $mpd->playid($item->id);
        return 1;
    }
    return 0;
}

sub mpd_change_url {
    my $url = shift;
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    syslog('info', 'Connected to mpd.rzl.');

    my $playlist = $mpd->playlist;

    if (!mpd_play_existing_song($mpd, $playlist, $url)) {
        syslog('info', "Adding $url to playlist");
        $playlist->add($url);
        $playlist = $mpd->playlist;
        if (!mpd_play_existing_song($mpd, $playlist, $url)) {
            syslog('info', "$url was not added?!");
        }
    }
}

sub mpd_current_song {
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    syslog('info', 'Connected to mpd.rzl.');

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

sub http_post_formdata {
    my ($uri, $content, $cb) = @_;

    my $p = HTTP::Request::Common::POST(
        $uri,
        Content_Type => 'form-data',
        Content => $content
    );

    my %hdr = map { ($_, $p->header($_)) } $p->header_field_names;

    http_post $p->uri, $p->content, headers => \%hdr, $cb;
}

sub run {
    my $server = "irc.hackint.net";
    my $port = 6667;
    my $nick = "RaumZeitChef";
    my @channels = ('#raumzeitlabor');
    my $ping_freq = 180; # in seconds
    my $last_ping = 0;
    my $said_idiot = 0;
    my $disable_timer = undef;
    my $disable_bell = undef;

    # pizza timer
    my $pizza_timer_user;
    my $pizza_timer_subject;
    my $pizza_timer_minutes;
    my $pizza_timer = undef;
    my $pizza_disable_timer = undef; # timer used for disabling ping+

    openlog('ircbot-chef', 'pid', 'daemon');
    syslog('info', 'Starting up');

    while (1) {
        syslog('info', "Connecting to $server as $nick...");
        my $old_status = "";
        my $c = AnyEvent->condvar;
        my $conn = AnyEvent::IRC::Client->new;
        my $httpd = AnyEvent::HTTPD->new(host => '127.0.0.1', port => 9091);
        my @answers = ("Alles klar.", "Yup.", "Okidoki.", "Eyup.", "Roger.");

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
                $conn->send_chan($channels[0], 'PRIVMSG', ($channels[0], $decoded->{message}));

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

                # disabled
                #if ($text =~ /^!help/) {
                #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream <url> to set Stream."));
                #    $conn->send_chan($channel, 'PRIVMSG', ($channel, "Enter !stream to see what's playing."));
                #}

                if ($text =~ /^!ping/) {

                    if ((time() - $last_ping) < $ping_freq) {
                        syslog('info', '!ping ignored');
                        if (!$said_idiot) {
                            $conn->send_chan($channel, 'PRIVMSG', ($channel, "Hey! Nur einmal alle 3 Minuten!"));
                            $said_idiot = 1;
                        }
                    } else {
                        $last_ping = time();
                        # Remaining text will be sent to Ping+, see:
                        # https://raumzeitlabor.de/wiki/Ping+
                        my ($remaining) = ($text =~ /^!ping (.*)/);
                        if (defined($remaining)) {
                            my $user = $ircmsg->{prefix};
                            my $nick = AnyEvent::IRC::Util::prefix_nick($user);
                            my $msg = strftime("%H:%M", localtime(time()))
                                . " <$nick> $remaining";

                            http_post_formdata 'http://pingiepie.rzl/create/text', [ text => $msg ], sub {
                                my ($body, $hdr) = @_;
                                return unless $body;

                                http_post_formdata 'http://pingiepie.rzl/show/scroll', [ id => $body ], sub {};

                                return;
                            };
                        }


                        $said_idiot = 0;
                        my $post;
                        my $epost;
                        # Zuerst den Raum-Ping (Port 8 am NPM), dann den Ping
                        # in der E-Ecke aktivieren (Port 3 am NPM).
                        $post = http_post 'http://172.22.36.1:5000/port/8', '1', sub {
                            say "Port 8 am NPM aktiviert!";
                            undef $post;
                            $epost = http_post 'http://172.22.36.1:5000/port/3', '1', sub {
                                say "Port 3 am NPM aktiviert!";
                                undef $epost;
                            };
                        };
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Die Rundumleuchte wurde für 5 Sekunden aktiviert"));
                        $disable_timer = AnyEvent->timer(after => 5, cb => sub {
                            my $post;
                            my $epost;
                            $post = http_post 'http://172.22.36.1:5000/port/8', '0', sub {
                                say "Port 8 am NPM deaktiviert!";
                                undef $post;
                                $epost = http_post 'http://172.22.36.1:5000/port/3', '0', sub {
                                    say "Port 3 am NPM deaktiviert!";
                                    undef $epost;
                                };
                            };
                        });
                        syslog('info', '!ping executed');
                    }
                }

                # timer ohne ping+ (irc-only)
                if ($text =~ /^!erinner (.+) an (.+) in (\d{1,2}) ?(h|m|s)/) {
                    my $reminder_target = $1;
                    if ($reminder_target eq 'mich') {
                        $reminder_target = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});
                    }
                    my $reminder_subject = $2;
                    my $reminder_timeout = $3;
                    $reminder_timeout *= 60 if ($4 eq 'm');
                    $reminder_timeout *= 3600 if ($4 eq 'h');
                    my $time = strftime("%H:%M", localtime(time()));
                    my $reminder;
                    $reminder = AnyEvent->timer(after => $reminder_timeout, cb => sub {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Reminder für $reminder_target: $reminder_subject ($time Uhr)"));
                        undef $reminder;
                    });
                    $conn->send_chan($channel, 'PRIVMSG', ($channel, $answers[rand @answers]));
                }

                # timer mit ping+ (auf 1 user begrenzt)
                if ($text =~ /^!timer cancel/) {
                    if (!$pizza_timer) {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Es läuft momentan kein Timer."));
                        return;
                    }

                    my $msguser = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});
                    if ($pizza_timer_user eq $msguser) {
                        undef $pizza_timer;
                        $conn->send_chan($channel, 'PRIVMSG', ($channel,
                                "Dein Timer \"$pizza_timer_subject\", $pizza_timer_minutes Minuten "
                                ."wurde deaktiviert."));
                        return;
                    }

                    $conn->send_chan($channel, 'PRIVMSG', ($channel,
                            "Der Timer \"$pizza_timer_subject\", $pizza_timer_minutes Minuten "
                            ."kann nur von $pizza_timer_user deaktiviert werden."));
                    return;
                } elsif ($text =~ /^!timer (\d+) (.+)/ || $text =~ /^!pizza/) {
                    if ($pizza_timer) {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel,
                                "Es läuft bereits ein Timer von $pizza_timer_user "
                                ."(\"$pizza_timer_subject\", $pizza_timer_minutes Minuten)."));
                        return;
                    }

                    $pizza_timer_user = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});

                    if ($text =~ /^!pizza/) {
                        $pizza_timer_minutes = 15;
                        $pizza_timer_subject = 'Pizza';
                    } else {
                        $pizza_timer_minutes = $1;
                        $pizza_timer_subject = $2;
                    }

                    if ($pizza_timer_minutes * 60 < $ping_freq) {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Das Timeout ist zu klein."));
                        return;
                    }
                    if ($pizza_timer_minutes > 30) {
                        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Das Timeout ist zu groß."));
                        return;
                    }

                    $conn->send_chan($channel, 'PRIVMSG', ($channel, $answers[rand @answers]));

                    my ($post, $epost);
                    $pizza_timer = AnyEvent->timer(after => $pizza_timer_minutes * 60, cb => sub {
                        my $body = encode_json({
                            text => "Timer abgelaufen: \"$pizza_timer_subject\"",
                            from => $pizza_timer_user,
                            time => strftime("%H:%M", localtime(time())),
                        });

                        my $guard;
                        $guard = http_post 'http://blackbox.raumzeitlabor.de/pingplus/', $body, sub {
                            undef $guard;
                        };

                        $post = http_post 'http://172.22.36.1:5000/port/8', '1', sub {
                            say "Port 8 am NPM aktiviert!";
                            undef $post;
                            $epost = http_post 'http://172.22.36.1:5000/port/3', '1', sub {
                                say "Port 3 am NPM aktiviert!";
                                undef $epost;
                            };
                        };

                        $conn->send_chan($channel, 'PRIVMSG', ($channel,
                            "( ・∀・)っ♨ $pizza_timer_user, deine Pizza ist fertig."));

                        $pizza_disable_timer = AnyEvent->timer(after => 5, cb => sub {
                            my $post;
                            my $epost;
                            $post = http_post 'http://172.22.36.1:5000/port/8', '0', sub {
                                say "Port 8 am NPM deaktiviert!";
                                undef $post;
                                $epost = http_post 'http://172.22.36.1:5000/port/3', '0', sub {
                                    say "Port 3 am NPM deaktiviert!";
                                    undef $epost;
                                };
                            };
                        });

                        undef $pizza_timer;

                        syslog('info', '!timer executed');
                    });
                }
            });

        $conn->connect($server, $port, { nick => $nick, user => 'RaumZeitChef' });
        $c->recv;

        # Wait 5 seconds before reconnecting, else we might get banned
        syslog('info', 'Connection lost.');
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

Version 1.6

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Michael Stapelberg.

This program is free software; you can redistribute it and/or modify it
under the terms of the BSD license.

=cut
