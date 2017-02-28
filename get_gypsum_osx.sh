#!/bin/bash

get_brew() {
	echo "not found, downloading."
	/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
}
echo -n "Detecting homebrew... "; which brew || get_brew

get_xquartz() {
	# URL detection derived from https://github.com/tjluoma/di/blob/master/di-xquartz.sh
	echo "XQuartz not found, downloading."
	XML_FEED="https://www.xquartz.org/releases/sparkle/release.xml"
	URL=`curl -sfL "$XML_FEED" | tr -s ' ' '\012' | sed -n -e '/url=/{s/^url="\(.*\)"$/\1/p;q}'`
	FILENAME=/tmp/XQuartz.dmg
	curl -L#o $FILENAME $URL
	# Mount point detection taken from the above script also. Couldn't this be done more simply
	# using the non-plist output of hdid?
	MNTPNT=$(echo -n "Y" | hdid -plist "$FILENAME" 2>/dev/null | fgrep -A 1 '<key>mount-point</key>' | tail -1 | sed 's#</string>.*##g ; s#.*<string>##g')
	PKG=`find "$MNTPNT" -maxdepth 1 -iname \*.pkg`
	sudo installer -verbose -pkg "$PKG" -target / -lang en
	diskutil eject "$MNTPNT" || echo Unmounting failed
}
defaults read "/Applications/Utilities/XQuartz.app/Contents/Info.plist" "CFBundleVersion" 2>/dev/null || get_xquartz

get_pike() {
	echo "not found, downloading."
	brew install pike
}
echo -n "Detecting Pike... "; which pike || get_pike

mkdir -p ~/Gypsum/plugins
cd ~/Gypsum
curl -O plugins/update.pike http://rosuav.github.io/Gypsum/plugins/update.pike
pike plugins/update.pike
echo "Gypsum should now be installed."
echo "No desktop icon as yet, sorry; to invoke:"
echo "cd ~/Gypsum; pike gypsum"
