package RaumZeitChef::Plugin;
use v5.14;
use strict;
use warnings;

use Moose;
use Moose::Role ();
use Moose::Exporter;

use RaumZeitChef::Log;
use RaumZeitChef::IRC::Event ();
use RaumZeitChef::PluginSuperClass ();

no Moose;

package RaumZeitChef::Meta::Action {
    use Moose;
    extends 'Moose::Meta::Method';

    has plugin_name => (is => 'ro', isa => 'Str', required => 1);
    has match => (is => 'ro', isa => 'RegexpRef|CodeRef', required => 1);

    no Moose;
}

(my $import, *unimport) = Moose::Exporter->build_import_methods(
    with_meta => ['action', 'before_action'],
    also => ['Moose', 'RaumZeitChef::IRC::Event'],
    as_is => [ @RaumZeitChef::Log::EXPORT ],
);

sub import {
    my ($class) = @_;
    my $PLUGIN_SUPER = 'RaumZeitChef::PluginSuperClass';
    my $caller = caller;

    $class->$import({ into => $caller });
    $caller->meta->superclasses($PLUGIN_SUPER);
}

sub action {
    my $cb = pop;
    my ($meta, $name, %args) = @_;

    my %param = (
        name => $name,
        match => qr<^!(?<cmd>$name)\s*(?<rest>.*)\s*$>,
        package_name => $meta->name,
        plugin_name => $meta->name,
        %args,
    );

    my $action = RaumZeitChef::Meta::Action->wrap($cb, %param);
    RaumZeitChef::PluginFactory->add_action($name => $action);
}

sub before_action {
    my $cb = pop;
    my ($meta, $name, %args) = @_;

    my %param = (
        name => $name,
        match => qr<^!(?<cmd>$name)\s*(?<rest>.*)\s*$>,
        package_name => $meta->name,
        plugin_name => $meta->name,
        %args,
    );

    my $action = RaumZeitChef::Meta::Action->wrap($cb, %param);
    RaumZeitChef::PluginFactory->add_before_action($name => $action);
}


1;
