use v5.14;
package RaumZeitChef::IRC::Event;
use strict;
use warnings;

use Moose::Exporter;

my $event_trait;

package RaumZeitChef::Trait::IRC::Event {
    use Moose::Role;
    BEGIN { $event_trait = __PACKAGE__ }

    has event_name => (is => 'ro', isa => 'Str', required => 1);
    has code => (is => 'ro', isa => 'CodeRef', required => 1);

    no Moose::Role;
}

(my $import, *unimport) = Moose::Exporter->build_import_methods(
    with_meta => ['event'],
);

sub import {
    namespace::autoclean->import(
        -cleanee => scalar(caller),
    );
    goto $import;
}

sub event {
    my (undef, $name, $cb) = @_;

    my %param = (
        is => 'bare',
        event_name => $name,
        traits => [$event_trait],
        code => $cb,
    );

    RaumZeitChef::IRC->meta->add_attribute("event_$name" => %param);
    # say "added event $name";
}

1;
