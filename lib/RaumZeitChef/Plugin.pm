use v5.14;
package RaumZeitChef::Plugin;

use Moose::Role ();
use Moose::Exporter;

package RaumZeitChef::Trait::Command {
    use Moose::Role;

    has command_name => (is => 'ro', isa => 'Str', required => 1);
    has match_rx => (is => 'ro', isa => 'RegexpRef', required => 1);
    has code => (is => 'ro', isa => 'CodeRef', required => 1);

    no Moose::Role;
}

Moose::Exporter->setup_import_methods(
    with_meta => ['command'],
    also => ['Moose::Role'],
);

sub command {
    my $cb = pop;
    my ($meta, $name, %args) = @_;

    my %param = (
        is => 'bare',
        traits => ['RaumZeitChef::Trait::Command'],
        command_name => $name,
        match_rx => qr<^!(?<cmd>$name)\s*(?<rest>.*)\s*$>,
        code => $cb,
        %args
    );

    $meta->add_attribute("command/$name" => %param);
}

1;
