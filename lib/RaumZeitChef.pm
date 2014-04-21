# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)
use v5.14;
use utf8;

package RaumZeitChef 1.8;

# These modules are in core:
# All these modules are not in core:
use AnyEvent;
use Method::Signatures::Simple;

use Moose;

use RaumZeitChef::Log;

has [qw/server port nick channel nickserv_pw/] =>
    (is => 'ro', required => 1);

has cv => (is => 'rw', default => sub { AE::cv });

# load base roles
with("RaumZeitChef::$_") for qw/IRC HTTPD/;

# automatically consume all plugins
{
    my @class_prefix = (__PACKAGE__, 'Plugin');
    my $class_path = join '/', @class_prefix;

    # find files via shell globbing
    my @files = glob '{' . join(',', @INC) . "}/${class_path}/*.pm";
    #  transform filenames to RaumZeitChef::Plugin::*
    my @plugins = map {
        my ($stem) = m[/ ( [^/]+ ) \.pm $]x;
        join '::', @class_prefix, $stem;
    } @files;

    # don't uniq(@plugins); if we have multiple files, die instead
    with($_) for @plugins;
}

sub run {
    my ($self) = @_;
    my $nick = $self->nick;
    my $server = $self->server;
    my $port = $self->port;

    log_info('Starting up');

    while (1) {
        log_info("Connecting to $host as $nick...");

        $self->irc->connect($server, $port, { nick => $nick, user => $nick });
        $self->cv->recv;

        $self->cv(AE::cv);

        # Wait 5 seconds before reconnecting, else we might get banned
        log_info('Connection lost.');
        sleep 5;
    }
}

1;

__END__


=head1 NAME

RaumZeitMPD - RaumZeitMPD IRC bot

=head1 DESCRIPTION

This module is an IRC bot (nickname RaumZeitMPD) which displays the currently
playing song (querying the MPD) upon !stream and enables a light upon !ping.

=head1 VERSION

Version 1.6

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Michael Stapelberg.

This program is free software; you can redistribute it and/or modify it
under the terms of the BSD license.

=cut
