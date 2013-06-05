package RaumZeitChef::AutoVoice;
use RaumZeitChef::Role;
use v5.14;
use utf8;
use Sys::Syslog;

use Method::Signatures::Simple;
use RaumZeitLabor::RaumStatus;
use List::MoreUtils qw/natatime/;
use List::Util qw/first/;

has raumstatus => (
    is => 'ro',
    default => method {
        my $status = RaumZeitLabor::RaumStatus->new;
        $status->register_join(sub { $self->_laborant_join($self->benutzerdb_to_channel(@_)) });
        $status->register_part(sub { $self->_laborant_part($self->benutzerdb_to_channel(@_)) });

        return $status;
    },
);

method _laborant_join (@members) {
    $self->set_voice(
        grep {
            $self->has_mode('-v', $_);
        } @members
    );
}

method _laborant_part (@members) {
    $self->remove_voice(
        grep {
            $self->has_mode('+v', $_);
        } @members
    );
}

event join => method ($irc, $nick, $channel, $is_myself) {
    if ($is_myself) {
        # enter the event loop one more time, since channel_list isn't up to date
        state $t = AnyEvent->timer(after => 0.5, cb => sub {
            my @members = $self->benutzerdb_to_channel($self->raumstatus->members);
            warn "members after join: @members\n";

            $self->set_voice(
                grep { $self->has_mode('-v', $_) } @members
            );

            # remove stale +v
            my @voiced = grep { $self->has_mode('+v', $_) } $self->list_channel_nicks;
            $self->remove_voice(grep { not $_ ~~ @members } @voiced);
        };
    } else {
        warn "join: $nick\n";
        return unless _normalize_channick($nick) ~~ $self->raumstatus->members;

        $self->set_voice($nick);
    }
};

func _normalize_channick($nick) {
    for (lc $nick) {
        s/[^a-z\d]//g;
        return $_
    }
}

method has_mode ($mode, $nick) {
    my $chan = $self->channel;
    my ($want, $mode_char) = $mode =~ /(.)(.)/;
    $want = $want eq '+' ? 1 : 0;

    my $m = $self->irc->nick_modes($chan, $_);

    return unless $m;
    return $m->{$mode_char} == $want
}

method list_channel_nicks {
    my %nicks = %{ $self->irc->channel_list($self->channel) || {} };
    return keys %nicks;
}

# given a benutzerdb-nick it tries to find a matching nick in our channel,
# returning the channel nick
method benutzerdb_to_channel (@members) {
    my @nicks = $self->list_channel_nicks;

    return map {
        my $member = $_;
        first { _normalize_channick($_) eq lc $member } keys %nicks
    } @members
}

method channel_to_benutzerdb ($member) {
}

method set_voice (@nicks) {
    return unless @nicks;
    say "give: @nicks";

    # voice at most 4 nickss
    my $iter = natatime 4, @nicks;
    while (my @part = $iter->()) {
        $self->irc->send_msg(join ' ', 'MODE', $self->channel, ('+' . ('v' x @part)), @part);
    }
}

method remove_voice (@nicks) {
    return unless @nicks;
    say "remove: @nicks";

    # devoice at most 4 nickss
    my $iter = natatime 4, @nicks;
    while (my @part = $iter->()) {
        $self->irc->send_msg(join ' ', 'MODE', $self->channel, ('-' . ('v' x @part)), @part);
    }
}

1;
