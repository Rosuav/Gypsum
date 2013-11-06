#!/bin/sh
ver=$1
nextver=$2
[ "$nextver" = '' ] && { echo "Usage: $0 ver-to-release next-ver"; echo "eg $0 1.1.0 1.1.1-git"; exit 1; }
echo $ver >VERSION
git commit VERSION -m"Bump version number to $ver for release"
git tag v$ver
echo $nextver >VERSION
git commit VERSION -m"Update version number after release"
echo Updated. To push this change:
echo git push origin master v$ver
