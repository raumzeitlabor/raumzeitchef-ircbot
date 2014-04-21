package RaumZeitChef::Plugin::MPD;
use RaumZeitChef::Plugin;
use v5.10;
use utf8;

use RaumZeitChef::Log;

# not in core
use Audio::MPD;

command stream => sub {
    my ($self, $msg, $match) = @_;
    my $rest = $match->{rest};
    if ($rest) {
        $self->say("Playing $rest");
        _mpd_change_url($rest);
    } else {
        $self->say(_mpd_current_song());
    }
};

sub _mpd_play_existing_song {
    my ($mpd, $playlist, $url) = @_;
    # Search for the song
    my @items = $playlist->as_items;
    for my $item (@items) {
        next if $item->file ne $url;
        log_info("Found $url (file is " . $item->file . ", id is " . $item->id . "), playing");
        $mpd->playid($item->id);
        return 1;
    }
    return 0;
}

sub _mpd_change_url {
    my $url = shift;
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    log_info('Connected to mpd.rzl.');

    my $playlist = $mpd->playlist;

    if (!_mpd_play_existing_song($mpd, $playlist, $url)) {
        log_info("Adding $url to playlist");
        $playlist->add($url);
        $playlist = $mpd->playlist;
        if (!_mpd_play_existing_song($mpd, $playlist, $url)) {
            log_info("$url was not added?!");
        }
    }
}

sub _mpd_current_song {
    my $mpd = Audio::MPD->new({ host => 'mpd.rzl' });
    log_info('Connected to mpd.rzl.');

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
