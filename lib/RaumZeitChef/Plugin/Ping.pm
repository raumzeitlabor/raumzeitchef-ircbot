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

    $last_ping = time();

    if ($match->{rest} =~ s/^\s*-a\s*//) {
        $get = http_get 'http://infra.rzl:8083/fhem?cmd.PCA301_0FA6FF=set%20PCA301_0FA6FF%20on&room=Olymp', sub {
            log_info("FHEM: ALAAAAAAARM aktiviert");

            $get = http_get 'http://infra.rzl:8083/fhem?cmd.PCA301_0FA6FF=set%20PCA301_0FA6FF%20off&room=Olymp', sub {
                log_info("FHEM: ALAAAAAAARM deaktiviert");
                undef $get;
            };
        };
    }

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
    my $get;
    my $epost;
    # Zuerst den Raum-Ping (Port 8 am NPM), dann den Ping
    # in der E-Ecke aktivieren (Port 3 am NPM).
    $get = http_get 'http://infra.rzl:8083/fhem?cmd.PCA301_053FFA=set%20PCA301_053FFA%20on&room=Hauptraum', sub {
        log_info("FHEM: blinklampe aktiviert");
        undef $get;
        $epost = http_post 'http://172.22.36.1:5000/port/3', '1', sub {
            log_info("Port 3 am NPM aktiviert!");
            undef $epost;
        };
    };
    $self->say("Die Rundumleuchte wurde für 5 Sekunden aktiviert");
    $disable_timer = AnyEvent->timer(after => 5, cb => sub {
        my $get;
        my $epost;
        $get = http_get 'http://infra.rzl:8083/fhem?cmd.PCA301_053FFA=set%20PCA301_053FFA%20off&room=Hauptraum', sub {
            log_info("FHEM: blinklampe deaktiviert");
            undef $get;
            $epost = http_post 'http://172.22.36.1:5000/port/3', '0', sub {
                log_info("Port 3 am NPM deaktiviert!");
                undef $epost;
            };
        };
    });
    log_info('!ping executed');

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
