package RaumZeitChef::Plugin::Ping;
use RaumZeitChef::Plugin;
use v5.14;
use utf8;

# core modules
use POSIX qw(strftime);
use Encode ();

# not in core
use AnyEvent::HTTP;
use HTTP::Request::Common ();

my $ping_freq = 180; # in seconds
my $last_ping = 0;
my $said_idiot = 0;
my $disable_timer = undef;
my $disable_bell = undef;

sub pca301 {
    my ($endpoint, $state, $cb) = @_;
	my $url = 'http://infra.rzl:8080/rest/items/pca301_' . $endpoint;
    my $body = $state ? 'ON' : 'OFF';
	http_post($url, $body, 'Content-Type' => 'text/plain', sub {
        my ($data, $hdr) = @_;
        log_error(Dumper($hdr)) if $hdr->{Status} ne '201';
        $cb->($hdr);
    })
}

action ping => sub {
    my ($self, $msg, $match) = @_;
    my ($cmd, $rest) = ($match->{cmd}, $match->{rest});

    if ((time() - $last_ping) < $ping_freq) {
        log_info('!ping ignored');
        if (!$said_idiot) {
            $self->say("Hey! Nur einmal alle 3 Minuten!");
            $said_idiot = 1;
        }

        return;
    }

    if ($rest =~ s/^\s*-a\s*//) {
        # if there is no text after the arg, stop here.
        return unless $rest;

        my $timer;
        pca301('alarm', 1, sub {
            log_info("FHEM: ALAAAAAAARM aktiviert");

            $timer = AnyEvent->timer(after => 0.5, cb => sub {
                pca301('alarm', 0, sub {
                        log_info("FHEM: ALAAAAAAARM deaktiviert");
                        undef $timer;
                });
            });
        });
    }

    $last_ping = time();

    # Remaining text will be sent to Ping+, see:
    # https://raumzeitlabor.de/wiki/Ping+
    if ($rest) {
        my $user = $msg->{prefix};
        my $nick = AnyEvent::IRC::Util::prefix_nick($user);
        my $msg = strftime("%H:%M", localtime(time()))
            . " <$nick> $rest";

        http_post_formdata('http://pingiepie.rzl/create/text', [ text => $msg ], sub {
            my ($body, $hdr) = @_;
            return unless $body;

            http_post_formdata('http://pingiepie.rzl/show/scroll', [ id => $body ], sub {});

            return;
        });
    }

    $said_idiot = 0;
    my $disable_timer;
    pca301('rundumleuchte', 1, sub {
        log_info("FHEM: blinklampe aktiviert");
        $self->say('Die Rundumleuchte wurde für 5 Sekunden aktiviert');

        $disable_timer = AnyEvent->timer(after => 5, cb => sub {
            pca301('rundumleuchte', 0, sub {
                log_info("FHEM: blinklampe deaktiviert");
                undef $disable_timer;
            });
        });
        log_info('!ping executed');
    });

};

sub http_post_formdata {
    my ($uri, $content, $cb) = @_;

    for (@$content) {
        # transform into bytestring
        $_ = Encode::encode_utf8($_);
    }
    my $p = HTTP::Request::Common::POST(
        $uri,
        Content_Type => 'form-data',
        Content => $content,
    );

    my %hdr = map { ($_, $p->header($_)) } $p->header_field_names;

    http_post($p->uri, $p->content, headers => \%hdr, $cb);
}

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
