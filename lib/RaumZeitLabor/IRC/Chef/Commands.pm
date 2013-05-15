package RaumZeitLabor::IRC::Chef::Commands;
use strict; use warnings;
use v5.10;

# core modules:
use Module::Load;

sub import {
    my ($class, @plugins) = @_;
    for my $module (map "$class\::$_", @plugins) {
        load($module);
    }
}

my %whitelist;
sub add_command {
    my ($class, $cmd, $cb) = @_;
    $whitelist{$cmd} = $cb;
}

sub commands {
    return %whitelist;
}

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
