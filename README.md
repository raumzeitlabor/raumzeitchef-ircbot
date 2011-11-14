RaumZeitMPD ircbot
==================

This git repository contains the source for the RaumZeitMPD IRC bot. It
consists of two files:

<dl>
  <dt>script/ircbot-mpd</dt>
  <dd>A simple script to run the IRC bot, providing --version.</dd>

  <dt>lib/RaumZeitLabor/IRC/MPD.pm</dt>
  <dd>The bot source code.</dd>
</dl>

Development
-----------
To run the bot on your local machine, use `./script/ircbot-mpd`. Note
that you need to edit **lib/RaumZeitLabor/IRC/MPD.pm** as it is hard-coded for
the RaumZeitLabor environment.

Building a Debian package
-------------------------
The preferred way to deploy code on the Blackbox (where this bot traditionally
runs on) is by installing a Debian package. This has many advantages:

1. When we need to re-install for some reason, the package has the correct
   dependencies, so installation is easy.

2. If Debian ships a new version of perl, the script will survive that easily.

3. A simple `dpkg -l | grep -i raumzeit` is enough to find all
   RaumZeitLabor-related packages **and their version**. The precise location
   of initscripts, configuration and source code can be displayed by `dpkg -L
   raumzeitmpd-ircbot`.

To create a Debian package, ensure you have `dpkg-dev` installed, then run:
<pre>
dpkg-buildpackage
</pre>

Now you have a package called `raumzeitmpd-ircbot_1.0-1_all.deb` which you can
deploy on the Blackbox.

Updating the Debian packaging
-----------------------------

If you introduce new dependencies, bump the version or change the description,
you have to update the Debian packaging. First, install the packaging tools we
are going to use:
<pre>
apt-get install dh-make-perl
</pre>

Then, run the following commands:
<pre>
perl Makefile.PL
mv debian/raumzeitmpd-ircbot.{init,postinst} .
rm -rf debian
dh-make-perl -p raumzeitmpd-ircbot --source-format 1
mv raumzeitmpd-ircbot.{init,postinst} debian/
</pre>

By the way, the originals for raumzeitmpd-ircbot.{init,postinst} are
`/usr/share/debhelper/dh_make/debian/init.d.ex` and
`/usr/share/debhelper/dh_make/debian/postinst.ex`.

See also
--------

For more information about Debian packaging, see:

* http://wiki.ubuntu.com/PackagingGuide/Complete

For online documentation about the Perl modules which are used:

* http://search.cpan.org/perldoc?AnyEvent::IRC::Client
* http://search.cpan.org/perldoc?Audio::MPD
* http://search.cpan.org/perldoc?IO::All
