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
command urititle => qr#(?<url>$re)#, method ($ircmsg, $match) {
    my $data_read = 0;
    my $partial_body = '';
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
            if (state $found_title ||= $partial_body =~ m#<title>#igsc) {
                state $off_start ||= pos $partial_body;
                if ($partial_body =~ m#</title>#igsc) {
                    my $len = pos($partial_body) - length('</title>') - $off_start;
                    say "$off_start $len";
                    my $too_long = $len > 72;
                    $len = 72 if $too_long;
                    my $title = substr $partial_body, $off_start, $len;
                    for ($title) {
                        # XXX decode correct encoding
                        $_ = decode_utf8($_);
                        $_ = decode_entities($_);
                        s/\s+/ /sg;
                    }
                    $title .= '…' if $too_long;
                    $self->say("[Link Info] $title");
                    return 0;
                }
            }

            # no title found, continue if < 8kb
            return 1 if ($data_read < 8192);
        };

    syslog('info', 'fetching remote content '.$match);
};

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
