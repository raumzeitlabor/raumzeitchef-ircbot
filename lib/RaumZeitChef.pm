# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)
use v5.14;
use utf8;

package RaumZeitChef 1.9;

# These modules are in core:
use File::Basename ();

# All these modules are not in core:
use AnyEvent;
use Moose;

use RaumZeitChef::Log;

has [qw/server port nick channel nickserv_pw/] =>
    (is => 'ro', required => 1);

has cv => (is => 'rw', default => sub { AE::cv });

has plugin_factory => (
    is => 'ro',
    default => sub { RaumZeitChef::PluginFactory->new },
);


# load base roles
# with("RaumZeitChef::$_") for qw/IRC HTTPD/;
with 'RaumZeitChef::IRC';

use RaumZeitChef::PluginFactory;
sub run {
    my ($self) = @_;
    my $nick = $self->nick;
    my $server = $self->server;
    my $port = $self->port;

    RaumZeitChef::PluginSuperClass->meta->set_class_attribute_value($_, $self->$_)
        for qw/nick channel irc/;

    log_info('Starting up');

    while (1) {
        # resolve hosts manually.
        # For whatever reason, tcp_connect doesn't try to connect to all available hosts.
        # since we wait for 5 seconds after a disconnection,
        # connecting to a available host would take unnecessarily long.
        my @hosts = _resolve_host($server, $port);
        for my $host (@hosts) {
            log_info("Connecting to $host as $nick...");

            $self->irc->connect($host, $port, { nick => $nick, user => $nick });
            $self->cv->recv;

            $self->cv(AE::cv);

        }
        # Wait 5 seconds before reconnecting, else we might get banned
        log_info('Connection lost.');
        sleep 5;
    }
}

sub _resolve_host {
    my ($host, $port) = @_;
    my $resolve = AnyEvent->condvar;
    my @hosts;
    AnyEvent::Socket::resolve_sockaddr(
        $host, $port, 'tcp', undef, undef, sub {
            for (@_) {
                my $sa = $_->[3];
                my (undef, $ipn) = AnyEvent::Socket::unpack_sockaddr($sa);
                push @hosts, AnyEvent::Socket::format_address($ipn);
            }
            $resolve->send;
        }
    );
    $resolve->recv;

    return @hosts;
}


1;
__END__


=head1 NAME

RaumZeitChef - RaumZeitChef IRC bot

=head1 DESCRIPTION

This module is an IRC bot (nickname RaumZeitChef)

=head1 VERSION

Version 1.9

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Michael Stapelberg.
Copyright 201x Simon Elsbrock
Copyright 201x Maik Fischer

This program is free software; you can redistribute it and/or modify it
under the terms of the BSD license.

=cut
