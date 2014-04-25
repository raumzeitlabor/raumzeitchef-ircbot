package RaumZeitChef::Plugin::Github;
use RaumZeitChef::Plugin;

use v5.14;
use utf8;
use Time::Piece;
use Time::Seconds;

use AnyEvent::HTTP;
use JSON::XS;
use URI;

my $event_uri = 'https://api.github.com/orgs/raumzeitlabor/events';

has etag => (is => 'rw');

sub init_plugin {
    my ($self) = @_;
    $self->interval(0);
}

sub interval {
    my ($self, $seconds) = @_;
    state $interval = 60;

    if ($seconds != 0) {
        return if $interval == $seconds;
        $interval = $seconds;
        log_info("setting new interval: $interval");
    }

    state $t;
    $t = AnyEvent->timer(
        after => $seconds,
        interval => $interval,
        cb => sub {
            $self->poll_github_events;
            log_debug("next poll in $interval seconds at " . localtime(time + $interval));
        }
    );
}

sub parse_github_events {
    my ($self, $data) = @_;

    my $events = decode_json($data);
    state $last_seen = '';
    my @print;

    # events are ordered in reverse order, we first parse them until $last_seen
    # or until we hit the first one that's too old.
    # Push the good ones into @print
    for my $e (@$events) {
        last if $e->{id} eq $last_seen;
        # strptime doesn't come with an ISO 8601 template,
        # even though ISO 8601 is mentioned all over the place.
        my $created_at = Time::Piece->strptime($e->{created_at}, "%Y-%m-%dT%TZ")->epoch;

        last if $created_at + 15 * ONE_MINUTE < time;

        if (my $txt = _parse_one_github_event($e)) {
            push @print, $txt;
        }
    }

    log_info('parsed ' . @print . ' new events');
    $last_seen = "$events->[0]{id}";
    $self->say($_) for reverse @print;
}

sub _parse_one_github_event {
    my ($e) = @_;
    my $nick = $e->{actor}{login};
    my $repo = $e->{repo}{name};
    $repo =~ s{^raumzeitlabor/}{};

    my $type = $e->{type};

    if ($type eq 'PushEvent') {
        my @commits = @{ $e->{payload}{commits} };
        my $last_commit = $commits[-1];
        # only show the first line of the last commit
        my ($last_msg) = $last_commit->{message} =~ /^([^\n]+)/;

        my $url = _api_to_html_url($last_commit->{url});
        my $num_commits = @commits > 1 ? "(and $#commits more) " : '';

        return "±$repo: “$last_msg” " . $num_commits . "@ $url (by $nick)";
    }
    elsif ($type eq 'ForkEvent') {
        my $url = $e->{payload}{forkee}{html_url};
        return "±$repo: forked to $url (by $nick)";
    }
    elsif ($type eq 'CreateEvent') {
        # XXX this is broken, see maikfs prrrrring event
        # $text = "±$repo: created "
    }
}

sub _api_to_html_url {
    my ($url) = @_;

    my $uri = URI->new($url);
    $uri->host('github.com');
    my @segments = $uri->path_segments;

    # 0 is the empty string (because it's an absolute path),
    # 1 is 'repos', 2, 3 is login and pathname, 4 is 'commits', 5 is sha
    $uri->path_segments(@segments[0, 2, 3], 'commit', $segments[5]);

    # return a string, not the object
    return "$uri";
}

sub poll_github_events {
    my ($self) = @_;
    my $etag = $self->etag;

    http_get(
        $event_uri, timeout => 10,
        ($etag && (headers => { 'If-None-Match' => $etag })),
        sub { $self->handle_response(@_) }
    );
    return;
}

sub handle_response {
    my ($self, $data, $h) = @_;
    my $status = $h->{Status};

    # internal error
    if ($status =~ /^59/) {
        log_error("error: $status $h->{Reason}");
        $self->interval(5 * ONE_MINUTE);
        return;
    }

    if ($h->{'x-poll-interval'}) {
        $self->interval($h->{'x-poll-interval'});
    }
    if ($h->{etag}) {
        $self->etag($h->{etag});
    }

    $self->_check_ratelimit($h);

    if ($status == 304) {
        log_debug('nothing has changed');
    }
    elsif ($status == 200) {
        $self->parse_github_events($data);
    }
    else {
        log_error("got a status: $status");
        $self->interval(5 * ONE_MINUTE);
        return;
    }
}

sub _check_ratelimit {
    my ($self, $h) = @_;
    state $polls_remaining;

    if (defined(my $rem = $h->{'x-ratelimit-remaining'})) {
        if (not defined $polls_remaining) {
            log_info("initial rate limit: $rem");
        }
        elsif ($rem != $polls_remaining) {
            log_error("changed rate limit to $rem");
        }
        $polls_remaining = $rem;
    }
    else {
        undef $polls_remaining;
    }

    if (defined $polls_remaining and $polls_remaining == 0) {
        undef $polls_remaining;
        log_error('ratelimit exceeded, we are banned from github');
        my $unbanned_after = $h->{'x-ratelimit-reset'} - time;
        $self->interval($unbanned_after);
        return;
    }
}

1;
