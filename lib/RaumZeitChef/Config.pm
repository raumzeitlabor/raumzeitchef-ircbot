package RaumZeitChef::Config;

use JSON::XS;
use Moose;

has 'config_filename' => (
    is => 'ro',
    default => "$ENV{HOME}/.raumzeitchef.json",
);

my %defaults = (
    server => 'irc.hackint.net',
    port => 9999,
    nick => 'RaumZeitChef',
    channel => '#raumzeitlabor',
    tls => 1,
);

for my $name (keys %defaults) {
    has($name, is => 'ro', default => $defaults{$name});
}

has 'nickserv_password' => (is => 'ro');

no Moose;

sub BUILD {
    my ($self) = @_;

    return unless open my $fh, '<', $self->config_filename;
    my $data = do { local $/; <$fh> };
    close $fh;

    # allow comments and trailing commata in lists
    my $json = JSON::XS->new->relaxed(1);

    my $config = $json->decode($data);

    for my $key (keys %$config) {
        my $attr = $self->meta->get_attribute($key)
            or Carp::carp("'$key' is not a valid RaumZeitChef::Config attribute.");

        # don't overwrite options supplied by the commandline
        if ($self->$key eq $defaults{$key}) {
            $attr->set_value($self, $config->{$key})
        }
    }

}

1;
