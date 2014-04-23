#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
use strict;
use warnings;
use inc::Module::Install;

name     'RaumZeitChef';
all_from 'lib/RaumZeitChef.pm';

requires 'AnyEvent';
requires 'AnyEvent::HTTP';
requires 'AnyEvent::HTTPD';
requires 'AnyEvent::IRC';
requires 'Audio::MPD';
requires 'JSON::XS';
requires 'List::MoreUtils';
requires 'HTML::Parser';
requires 'HTTP::Message';
requires 'Moose';
requires 'MooseX::ClassAttribute';

install_script 'ircbot-chef';

postamble <<'END_OF_MAKEFILE';
install:: extra_install
pure_install:: extra_install
install_vendor:: extra_install

extra_install:
	install -d $(DESTDIR)/etc/rsyslog.d/
	install -m 644 ircbot-chef.rsyslog $(DESTDIR)/etc/rsyslog.d/ircbot-chef.conf
END_OF_MAKEFILE

WriteAll;
