package RaumZeitChef::Plugin::AutoVoice;
use RaumZeitChef::Plugin;
use v5.14;
use utf8;

use RaumZeitLabor::RaumStatus;
use List::MoreUtils qw/natatime/;
use List::Util qw/first/;

no if $] >= 5.018, warnings => "experimental::smartmatch";

has raumstatus => (
    is => 'ro',
    default => sub {
        my ($self) = @_;
        my $status = RaumZeitLabor::RaumStatus->new;
        $status->register_join(sub { $self->_laborant_join($self->benutzerdb_to_channel(@_)) });
        $status->register_part(sub { $self->_laborant_part($self->benutzerdb_to_channel(@_)) });

        return $status;
    },
);

sub _laborant_join {
    my ($self, @members) = @_;
    $self->set_voice(
        grep {
            $self->has_mode('-v', $_);
        } @members
    );
}

sub _laborant_part {
    my ($self, @members) = @_;
    $self->remove_voice(
        grep {
            $self->has_mode('+v', $_);
        } @members
    );
}

event join => sub {
    my ($self, $irc, $nick, $channel, $is_myself) = @_;
    if ($is_myself) {
        # enter the event loop one more time, since channel_list isn't up to date
        state $t = AnyEvent->timer(after => 0.5, cb => sub {
            my @members = $self->benutzerdb_to_channel($self->raumstatus->members);
            log_debug("members after join: @members");

            $self->set_voice(
                grep { $self->has_mode('-v', $_) } @members
            );

            # remove stale +v
            my @voiced = grep { $self->has_mode('+v', $_) } $self->list_channel_nicks;
            $self->remove_voice(grep { not $_ ~~ \@members } @voiced);
        });
    } else {
        log_debug("join: $nick");
        return unless _normalize_channick($nick) ~~ [ $self->raumstatus->members ];

        $self->set_voice($nick);
    }
};

sub _normalize_channick {
    my ($nick) = @_;
    for (lc $nick) {
        s/[^a-z\d]//g;
        return $_
    }
}

sub has_mode {
    my ($self, $mode, $nick) = @_;
    my $chan = $self->channel;
    my ($want, $mode_char) = $mode =~ /(.)(.)/;
    $want = $want eq '+' ? 1 : 0;

    my $m = $self->irc->nick_modes($chan, $_);

    return unless $m;
    return ($m->{$mode_char} ? 1 : 0) == $want
}

sub list_channel_nicks {
    my ($self) = @_;
    my %nicks = %{ $self->irc->channel_list($self->channel) || {} };
    return keys %nicks;
}

# given a benutzerdb-nick it tries to find a matching nick in our channel,
# returning the channel nick
sub benutzerdb_to_channel {
    my ($self, @members) = @_;
    my @nicks = $self->list_channel_nicks;

    return map {
        my $member = $_;
        first { _normalize_channick($_) eq lc $member } @nicks
    } @members
}

sub channel_to_benutzerdb {
    my ($self, $member) = @_;
}

sub set_voice {
    my ($self, @nicks) = @_;
    return unless @nicks;
    log_debug("give: @nicks");

    # voice at most 4 nicks
    my $iter = natatime 4, @nicks;
    while (my @part = $iter->()) {
        my $voice = join ' ', 'MODE', $self->channel, ('+' . ('v' x @part)), @part;
        $self->call_after_oped(send_msg => $voice);
    }
}

sub remove_voice {
    my ($self, @nicks) = @_;
    return unless @nicks;
    log_debug("remove: @nicks");

    # devoice at most 4 nicks
    my $iter = natatime 4, @nicks;
    while (my @part = $iter->()) {
        my $devoice = join ' ', 'MODE', $self->channel, ('-' . ('v' x @part)), @part;
        $self->call_after_oped(send_msg => $devoice);
    }
}

1;
