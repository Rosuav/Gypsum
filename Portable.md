Portable Gypsum
===============

Download a portable, self-contained Gypsum from https://rosuav.com/portable-gypsum.zip
and extract it to any directory, even removable media.

This is an installation of Pike (currently v8.0.1956) with a copy of Gypsum,
ready to be run, without need of any installation.

Pike can be found at https://pike.lysator.liu.se/download/pub/pike/latest-stable/
and Gypsum comes from https://github.com/rosuav/Gypsum

Extract this onto a thumb drive and be able to connect to your favourite MUD
server(s) from anywhere!

To update Gypsum to the latest, use Plugins|Update; it should be able to download
and apply the latest updates. Updating Pike itself is more complicated but should
not normally be necessary.

Internal notes:
* To update Pike, do a regular installation, then locate the path references (eg
  all references to "G:/Pike") in Pike/lib/master.pike, and recode them to use
  relative paths.
* zip ../tmp/portable-gypsum.zip -r *
* Push that archive up somewhere

Launcher is quite simple:

    cd Gypsum
    ..\Pike\bin\pike gypsum threshold

Can be edited by the end user if preferred.
