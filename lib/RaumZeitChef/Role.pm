package RaumZeitChef::Role;
use v5.12;
use Moose::Role ();
use Moose::Exporter;
use Method::Signatures::Simple;

my %events;
func event ($name, $cb) {
    say "adding event: $name => $cb";
    push @{$events{$name} ||= []}, $cb;
}
# XXX code smell, injects method
method RaumZeitChef::get_events { %events }

my %commands;
func command ($name, $cb) {
    my $rx = qr/^!(?<cmd>$name)\s*(?<rest>.*)\s*$/;
    if (@_ == 3) {
        $rx = $cb;
        $cb = pop @_;
    }
    say "adding command: $name => $cb";
    $commands{$name} = { rx => $rx, cb => $cb };
}
# XXX code smell, injects method
method RaumZeitChef::get_commands { %commands }

Moose::Exporter->setup_import_methods(
    as_is => ['event', 'command'],
    also => 'Moose::Role',
);

1;
