package RaumZeitChef::Plugin::LinkInfo;
use RaumZeitChef::Plugin;
use v5.14;
use utf8;

# core modules
use POSIX qw(strftime);
use Encode ();

# not in core
use AnyEvent::HTTP;
use HTTP::Request::Common ();
use Regexp::Common qw/URI/;
use HTTP::Status qw/status_message/;
use HTML::Entities qw/decode_entities/;
use Encode qw/decode_utf8/;


# derp.
(my $re = $RE{URI}{HTTP}) =~ s/http/https?/;

action 'linkinfo', match => qr#(?<url>$re)#, sub {
    my ($self, $ircmsg, $match) = @_;
    my $data_read = 0;
    my $partial_body = '';

    my $is_html;

    http_get($match->{url},
        timeout => 3,
        on_header => sub {
            my ($hdr) = @_;

            # close connection if it isn't HTML
            my $type = $hdr->{'content-type'};
            $is_html = $type =~ /^text\/x?html \s* (?: ; | $ )/xi;
            return $is_html;
        },
        on_body => sub {
            my ($data, $headers) = @_;

            # silently do nothing
            return unless $is_html;

            my $status = $headers->{Status};

            if (not $status =~ /^2/) {
                my $internal_err = $status =~ /^59/;

                my $err_msg = 'LinkInfo: ' .
                              ($internal_err && 'Internal ') .
                              "Error $status";

                my $reason = $headers->{Reason} // status_message($status);

                $self->say("$err_msg $reason");
                return;
            }

            $data_read += length $data; 
            $partial_body .= $data;
            if (state $found_title ||= $partial_body =~ m#<title>#igsc) {
                state $off_start ||= pos $partial_body;
                if ($partial_body =~ m#</title>#igsc) {
                    my $len = pos($partial_body) - length('</title>') - $off_start;
                    my $too_long = $len > 320;
                    $len = 320 if $too_long;
                    my $title = substr $partial_body, $off_start, $len;
                    for ($title) {
                        # XXX decode correct encoding
                        $_ = decode_utf8($_);
                        $_ = decode_entities($_);
                        s/\s+/ /sg;
                    }
                    $title .= '…' if $too_long;
                    $self->say("LinkInfo: $title");
                    return 0;
                }
            }

            # no title found, continue if < 8kb
            return 1 if ($data_read < 8192);
        }
    );

    log_info('fetching remote content ' . $match->{url});
};

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
