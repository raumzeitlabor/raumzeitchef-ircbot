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
# wrap each event with $self
# XXX code smell, injects method
method RaumZeitChef::get_events {
    return map {
        $_ => [ map {
                    my $cb = $_;
                    sub { $self->$cb(@_) }
                } @{ $events{$_} } ]
    } keys %events
}

my %commands;
func command ($name, $cb) {
    my $rx = qr/^!(?<cmd>\w+)\s*(?<rest>.*)\s*$/;
    if (ref $cb eq 'Regexp') {
        $rx = $cb;
        $cb = pop;
    }
    say "adding command: $name => $cb";
    $commands{$name} = { rx => $rx, cb => $cb };
}
# wrap each command with $self
# XXX code smell, injects method
method RaumZeitChef::get_commands {
    return map {
        my $cb = $commands{$_}{cb};
        ($_ => sub { $self->$cb(@_) })
    } keys %commands;
}

Moose::Exporter->setup_import_methods(
    as_is => ['event', 'command'],
    also => 'Moose::Role',
);

1;
