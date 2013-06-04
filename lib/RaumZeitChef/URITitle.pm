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
use HTML::Entities qw/decode_entities/;
use Encode qw/decode_utf8/;

# derp.
(my $re = $RE{URI}{HTTP}) =~ s/http/https?/;
command urititle => qr#^(?<url>$re)#, method ($ircmsg, $match) {
    my $data_read = 0;
    my $partial_body;
    http_get $match->{url},
        timeout => 3,
        on_header => sub { $_[0]{"content-type"} =~ /^text\/html\s*(?:;|$)/ },
        on_body => sub {
            my ($data, $headers) = @_;

            if ($headers->{Status} !~ m/^2/ && $headers->{Status} !~ m/^59/) {
                $self->say('[Link Info] error: '.$headers->{Status}." ".status_message($headers->{Status}));
                return 0;
            }

            $data_read += length $data; 
            $partial_body .= $data;
            if ($partial_body =~ m#<title>([^<]+)</title>#) {
                my $title = decode_utf8(decode_entities($1));
                $self->say("[Link Info] $title");
                return 0;
            }

            # no title found, continue if < 8kb
            return 1 if ($data_read < 8192);
        };

    syslog('info', 'fetching remote content '.$match);
};

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
