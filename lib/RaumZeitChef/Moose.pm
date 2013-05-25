package RaumZeitChef::Moose;
use v5.12;
use Moose ();
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
    say "adding command: $name => $cb";
    $commands{$name} = $cb;
}
# wrap each command with $self
# XXX code smell, injects method
method RaumZeitChef::get_commands {
    return map {
        my $cb = $commands{$_};
        ($_ => sub { $self->$cb(@_) })
    } keys %commands;
}

Moose::Exporter->setup_import_methods(
    as_is => ['event', 'command'],
    also => 'Moose',
);

1;
