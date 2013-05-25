package RaumZeitChef::Commands;
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

1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
