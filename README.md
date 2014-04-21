RaumZeitChef ircbot
==================

This git repository contains the source for the RaumZeitChef IRC bot.

<dl>
  <dt>script/ircbot-chef</dt>
  <dd>A simple script to run the IRC bot, providing --version.</dd>

  <dt>lib/RaumZeitLabor/IRC/Chef.pm</dt>
  <dd>The bot source code.</dd>
</dl>

Development
-----------
To run the bot on your local machine, use `./script/ircbot-chef` and
set `--channel` and `--nick` to something appropiate.


Building a Debian package
-------------------------
The preferred way to deploy code on infra.rzl (where this bot traditionally
runs on) is by installing a Debian package. This has many advantages:

1. When we need to re-install for some reason, the package has the correct
   dependencies, so installation is easy.

2. If Debian ships a new version of perl, the script will survive that easily.

3. A simple `dpkg -l | grep -i raumzeit` is enough to find all
   RaumZeitLabor-related packages **and their version**. The precise location
   of initscripts, configuration and source code can be displayed by `dpkg -L
   raumzeitchef-ircbot`.

To create a Debian package, ensure you have `dpkg-dev` installed, then run:
<pre>
dpkg-buildpackage
</pre>

Now you have a package called `raumzeitchef-ircbot_$VERSION_all.deb` which you can
deploy on infra.rzl.

Updating the Debian packaging
-----------------------------

**XXX Don't do this, it will overwrite your `.git` directory**

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
