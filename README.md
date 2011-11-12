RaumZeitMPD ircbot
==================

This git repository contains the source for the RaumZeitMPD IRC bot. It
consists of two files:

<dl>
  <dt>bin/ircbot-mpd</dt>
  <dd>A simple script to run the IRC bot, providing --version.</dd>

  <dt>lib/RaumZeitLabor/IRC/MPD.pm</dt>
  <dd>The bot source code.</dd>
</dl>

Creating a Debian package
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

Fortunately, creating a Debian package is easy. Make soure you have the
packages `dpkg-dev dh-make-perl`.

Then, run the following commands (you might need to install RaumZeitMPD’s build
dependencies, but you will be told so):
<pre>
perl Makefile.PL
make distdir
cd RaumZeitMPD-1.0
dh-make-perl -p raumzeitmpd-ircbot --source-format 1
dpkg-buildpackage
</pre>

Now you have a package called `raumzeitmpd-ircbot_1.0-1_all.deb` which you can
deploy on the Blackbox.
