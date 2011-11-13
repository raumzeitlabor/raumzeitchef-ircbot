#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
use strict;
use warnings;
use ExtUtils::MakeMaker; # in core

WriteMakefile(
    NAME => 'RaumZeitMPD',
    MIN_PERL_VERSION => '5.010000', # 5.10.0
    PREREQ_PM => {
        'AnyEvent'      => 0,
        'AnyEvent::IRC' => 0,
        'Audio::MPD'    => 0,
        'IO::All'       => 0,
        'IO::All::LWP'  => 0,
    },
    ABSTRACT_FROM => 'lib/RaumZeitLabor/IRC/MPD.pm',
    VERSION_FROM => 'lib/RaumZeitLabor/IRC/MPD.pm',
    LICENSE => 'bsd',
    AUTHOR => 'Michael Stapelberg',
    EXE_FILES => [ 'bin/ircbot-mpd' ],
);

# Install the initscript
sub MY::postamble {
    return q{
install:: extra_install
pure_install:: extra_install
install_vendor:: extra_install

extra_install:
	install -d $(DESTDIR)/etc/init.d $(DESTDIR)/etc/rsyslog.d/
	install -m 755 ircbot-mpd.init $(DESTDIR)/etc/init.d/ircbot-mpd
	install -m 755 ircbot-mpd.rsyslog $(DESTDIR)/etc/rsyslog.d/ircbot-mpd.conf
    }
}
