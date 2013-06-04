package RaumZeitChef::URITitle;
use RaumZeitChef::Role;
use v5.14;
use utf8;

# core modules
use Sys::Syslog;
use POSIX qw(strftime);
use Encode ();

# not in core
use AnyEvent::HTTP;
use HTTP::Request::Common ();
use Method::Signatures::Simple;
use Regexp::Common qw/URI/;
use HTTP::Status qw/status_message/;

command urititle => qr#^(?<url>$RE{URI}{HTTP})#, method ($irc, $channel, $ircmsg, $match, $rest) {
    my $data_read = 0;
    http_get $match,
        timeout => 3,
        on_header => sub { $_[0]{"content-type"} =~ /^text\/html\s*(?:;|$)/ },
        on_body => sub {
            my ($data, $headers) = @_;

            if ($headers->{Status} !~ m/^2/) {
                $self->say('[Link Info] error: '.status_message($headers->{Status}));
                return 0;
            }

            $data_read += length $data; 
            if ($data =~ m#<title>([^<]+)</title>#) {
                $self->say("[Link Info] $1");
                return 0;
            }
            # no title found, continue if < 8kb
            return 1 if ($data_read < 8192);
        }
    };
    syslog('info', 'fetching remote content '.$match);
};

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
