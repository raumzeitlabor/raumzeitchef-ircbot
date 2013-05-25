package RaumZeitChef::Commands::MPD;
use strict; use warnings;
use v5.10;
use utf8;

# core modules
use Sys::Syslog;

# not in core
use Audio::MPD;

RaumZeitChef::Commands->add_command(stream => sub {
    my ($conn, $channel, $ircmsg, $cmd, $rest) = @_;

    if ($rest) {
        $conn->say($channel, $channel, "Playing $rest");
        mpd_change_url($rest);
    } else {
        $conn->say($channel, mpd_current_song());
    }
});

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
    # silence uninitialized warnings, if song is eg. a http stream
    $name ||= '';
    return "Playing: $name (" . $song->file . " " . $time . ")";
}


# vim: set ts=4 sw=4 sts=4 expandtab: 
