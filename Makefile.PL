#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
use strict;
use warnings;
use inc::Module::Install;

name     'RaumZeitMPD';
all_from 'lib/RaumZeitLabor/IRC/MPD.pm';

requires 'AnyEvent';
requires 'AnyEvent::HTTP';
requires 'AnyEvent::IRC';
requires 'Audio::MPD';

install_script 'ircbot-mpd';

postamble <<'END_OF_MAKEFILE';
install:: extra_install
pure_install:: extra_install
install_vendor:: extra_install

extra_install:
	install -d $(DESTDIR)/etc/rsyslog.d/
	install -m 644 ircbot-mpd.rsyslog $(DESTDIR)/etc/rsyslog.d/ircbot-mpd.conf
END_OF_MAKEFILE

WriteAll;
