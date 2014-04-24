package RaumZeitChef::Plugin::Github;
use RaumZeitChef::Plugin;

use v5.14;
use utf8;
use Time::Piece;
use Time::Seconds;

use AnyEvent::HTTP;
use JSON::XS;
use Data::Dump;
use URI;

my $event_uri = 'https://api.github.com/orgs/raumzeitlabor/events';

has timer => (is => 'rw');

sub init_plugin {
    my ($self) = @_;
    $self->_mk_timer(0);
}

# XXX I'm really unpleased with the shenanigans I have to do
# to setup a non blocking loop. There ought to be a better way.

sub _mk_timer {
    my ($self, $next_poll) = @_;
    log_debug("next poll in $next_poll seconds at " . localtime(time + $next_poll));
    my $t = AnyEvent->timer(after => $next_poll, cb => $self->poll_github_events);
    $self->timer($t);
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
        # only show the first line of the last commit
        my ($last_msg) = $commits[-1]{message} =~ /^([^\n]+)/;

        my $num_commits = @commits > 1 ? "(and $#commits more) " : '';

        # transform the API URI to the HTML one
        my $uri = URI->new($commits[-1]{url});
        $uri->host('github.com');
        my @segments = $uri->path_segments;
        # 0 is the empty string (because it's an absolute path),
        # 1 is 'repos', 2, 3 is login and pathname, 4 is 'commits', 5 is sha
        $uri->path_segments(@segments[0, 2, 3], 'commit', $segments[5]);

        return "±$repo: “$last_msg” " . $num_commits . "@ $uri (by $nick)";
    }
    elsif ($type eq 'ForkEvent') {
        return "±$repo: forked to $e->{payload}{forkee}{html_url} (by $nick)";
    }
    elsif ($type eq 'CreateEvent') {
        # XXX this is broken, see maikfs prrrrring event
        # $text = "±$repo: created "
    }
}

sub poll_github_events {
    my ($self) = @_;
    state ($etag, $poll_interval, $poll);

    return sub {
        use Data::Dump;
        $poll = AnyEvent->condvar(cb => sub { $self->_mk_timer(shift->recv) });
        http_get $event_uri, ($etag && (headers => { 'If-None-Match' => $etag })), sub {
            my ($data, $h) = @_;
            my $status = $h->{Status};

            # internal error
            if ($status =~ /^59/) {
                log_error("error: $status $h->{Reason}");
                return $poll->send(5 * ONE_MINUTE);
            }

            # X-Poll-Interval isn't always set, we have to save it
            if ($h->{'x-poll-interval'}) {
                $poll_interval = $h->{'x-poll-interval'};
                log_info("setting new interval: $poll_interval");
            }
            if ($h->{etag}) {
                $etag = $h->{etag};
            }

            # we exhausted our API limit, be a good citizen and wait
            if (exists $h->{'x-ratelimit-remaining'}
                and $h->{'x-ratelimit-remaining'} == 0)
            {
                log_error('ratelimit exceeded, we are banned from github');
                my $unbanned_after = $h->{'x-ratelimit-reset'} - time;
                return $poll->send($unbanned_after);
            }

            # nothing has changed
            if ($status == 304) {
                log_debug('nothing has changed');
            }
            elsif ($status == 200) {
                $self->parse_github_events($data);
            }
            else {
                log_error("got a status: $status");
                return $poll->send(5 * ONE_MINUTE);
            }
            return $poll->send($poll_interval);
        };

        return;
    }
}

1;
