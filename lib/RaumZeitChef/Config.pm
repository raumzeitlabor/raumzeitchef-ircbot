package RaumZeitChef::Config;

use JSON::XS;
use Moose;

has 'config_filename' => (
    is => 'ro',
    default => "$ENV{HOME}/.raumzeitchef.json",
);

has [qw/server port nick channel/] =>
    (is => 'ro', required => 1);

has 'nickserv_password' => (is => 'ro');

no Moose;

sub BUILD {
    my ($self) = @_;

    return unless open my $fh, '<', $self->config_filename;
    my $config = decode_json(do { local $/; <$fh> });

    for my $key (keys %$config) {
        my $attr = $self->meta->get_attribute($key)
            or Carp::carp("'$key' is not a valid RaumZeitChef::Config attribute.");

        $attr->set_value($self, $config->{$key});
    }
}

1;
