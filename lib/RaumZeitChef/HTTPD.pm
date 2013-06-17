package RaumZeitChef::HTTPD;
use RaumZeitChef::Plugin;
use v5.14;
use utf8;

use Method::Signatures::Simple;
use JSON::XS;
use AnyEvent::HTTPD;

my %response = map { $_->[0] => { content => $_->[1] } }
    [missing => ['text/plain', 'No content received. Please post JSON']],
    [sucesss => ['text/html', '{"success":true}']];

has httpd => (is => 'ro', default => method {
    my $httpd = AnyEvent::HTTPD->new(host => '127.0.0.1', port => 9091);
    $httpd->reg_cb('/to_irc' => sub {
        my ($httpd, $req) = @_;

        my $json;
        my $content = $req->{content};
        unless ($content and eval { $json = decode_json($content); 1 }) {
            $req->respond($response{missing});
            return;
        }

        $self->say($json->{message});

        $req->respond($response{success});
    });
    return $httpd;
});

1;
