# vim:ts=4:sw=4:expandtab
# © 2010-2012 Michael Stapelberg (see also: LICENSE)
package RaumZeitChef 1.7;
use v5.14;
use utf8;

# These modules are in core:
use Sys::Syslog;
# All these modules are not in core:
use AnyEvent;
use AnyEvent::HTTPD;
use JSON::XS;
use Method::Signatures::Simple;

use Moose;

has server => (is => 'ro', default => 'irc.hackint.net');
has port => (is => 'ro', default => 6667);
has nick => (is => 'ro', default => 'RaumZeitChef');
has channel => (is => 'ro', default => '#raumzeitlabor');

my @plugins = qw/IRC Commands::MPD Commands::Ping Commands::Erinner/;
with(__PACKAGE__ . "::$_") for @plugins;

has cv => (is => 'rw', default => sub { AE::cv });

has httpd => (is => 'ro', default => method {
    my $httpd = AnyEvent::HTTPD->new(host => '127.0.0.1', port => 9091);
    $httpd->reg_cb( '/to_irc' => sub {
        my ($httpd, $req) = @_;

        my $no_content = ['text/plain', 'No content received. Please post JSON'];
        my $success = ['text/html', '{"success":true}'];

        if (not $req->{content}) {
            $req->respond({ content => $no_content });
            return;
        }

        my $decoded = decode_json($req->{content});
        $self->say($decoded->{message});

        $req->respond({ content => $success });
    });
    return $httpd;
});

sub run {
    my ($class) = @_;
    my $self = $class->new();
    my $nick = $self->nick;
    my $server = $self->server;

    openlog('ircbot-chef', 'pid', 'daemon');
    syslog('info', 'Starting up');

    while (1) {
        syslog('info', "Connecting to $server as $nick...");

        $self->irc->connect($self->server, $self->port, { nick => $self->nick, user => 'RaumZeitChef' });
        $self->cv->recv;

        $self->cv(AE::cv);

        # Wait 5 seconds before reconnecting, else we might get banned
        syslog('info', 'Connection lost.');
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
