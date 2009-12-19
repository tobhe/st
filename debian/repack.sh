#!/bin/sh
#
#   Copyright
#
#       Copyright (C) 2008-2009 Jari Aalto <jari.aalto@cante.net>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.

set -e
set -u

Init ()
{
    # Check depends

    [ -x /bin/mktemp ] || Die "[ERROR]: mktemp (coreutils) not installed."
    [ -x /bin/bzip2  ] || Die "[ERROR]: bzip2 (bzip2) not installed."
    [ -x /bin/gzip   ] || Die "[ERROR]: gzip (gzip) not installed."
    [ -x /bin/tar    ] || Die "[ERROR]: tar (tar) not installed."
}

Help ()
{
    echo "
SYNOPSIS
  repack.sh --upstream-source <ver> <downloaded file> [package]

DESCRIPTION
    Repackage upstream source. The command line arguments are due
    to uscan(1) order. The PACKAGE argument is optional.

EXAMPLES
    Repack foo-1.1.tar.gz as bar-1.10.tar.gz

        repack.sh 1.10 foo-1.1.tar.gz bar

AUTHOR
    Jari Aalto <jari.aalto@cante.net>. Licenced under GPL v2 or,
    at your option, any later version.
"
    exit 0
}

Run ()
{
    if [ "${test+test_mode}" = "test_mode" ]; then
	echo "$@"
    else
	[ "${verbose+verbose_mode}" = "verbose_mode" ] && echo "$@" >&2
	"$@"
    fi
}

Warn ()
{
    echo "$*" >&2
}

Die ()
{
    Warn "$*"
    exit 1
}

AtExit ()
{
    if [ "$DIR" ]; then
	[ -d "$DIR" ] && Run rm -rf "$DIR"
    fi
}

DebianVersion ()
{
    # YYYYMMDD => YYYY.MMDD
    echo $1 | sed 's/^\([0-9][0-9][0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\)/\1.\2\3/'
}

DebianTar ()
{
    local ver=$1
    local dver=$2
    local file=$3
    local pkg=$4

    # If version is same, use original file

    if [ "$ver" = "$dver" ]; then
	if [ "$pkg" ]; then
	    echo $file | sed "s,.*$ver,$pkg-$ver,"
	else
            echo $file
	fi
	return 0
    fi

    if [ "$pkg" ]; then
	echo $file | sed -e "s,.*$ver,$pkg-$dver,"
    else
        # replace with new version
	echo $file | sed -e "s,$ver,$dver,"
    fi
}

Pkg ()
{
    local file=$1

    if [ -f debian/changelog ]; then
	dpkg-parsechangelog | awk '/^Source:/ {print $2}'
    else

	# package-1.1.tar.gz => package
	echo $file | sed "s,-[0-9].*,,"
    fi
}

Version ()
{
    local file=$1
    local pkg=$(Pkg $file)

    if [ ! "$pkg" ]; then
	Die "[ERROR] Internal error. 'pkg' variable not set. Run with debug (-x)"
    fi

    echo $file |
    sed -e "s,\.tar.*,," \
        -e "s,$pkg[-_],,"
}

Main ()
{
    Init

    DIR=

    #  Ignore uscan(1) argument --upstream-version in $1

    case "$1" in
	--help|-h)
		Help
		;;
	--*)	shift
		;;
    esac

    VER="$1"
    FILE="$2"

    if [ ! -f "$FILE" ]; then
	Die "[ERROR] Arg 2. File does not exist: $FILE"
    fi

    PKG=${3:-$(Pkg $FILE)}

    if [ ! "$PKG" ]; then
	Die "[ERROR] Internal error. PKG not set. Run with debug (-x)"
    fi

    CURVER=$(Version $FILE)

    if [ ! "$CURVER" ]; then
	Die "[ERROR] Internal error. CURVER not set. Run with debug (-x)"
    fi

    DVER=$(DebianVersion "$VER")
    DFILE=$(DebianTar "$CURVER" "$DVER" "$FILE" $PKG)

    #  Debian Developer's Reference 6.7.8.2 Repackaged upstream source

    REPACK_DIR="$PKG-$DVER.orig"

    DIR=$(Run mktemp -d ./tmp.repack.XXXXXX)

    echo "Repacking $FILE as $PKG-$DVER"

    #	Create an extra directory to cope with tarballs that
    #	do not have root/ directory

    UP_BASE="$DIR/unpack"
    Run mkdir "$UP_BASE"

    Run tar -C "$UP_BASE" -xf "$FILE"

    if [ $(ls -1 "$UP_BASE" | wc -l) -eq 1 ]; then
	# Tarball does contain a root directory
	UP_BASE="$UP_BASE/$(ls -1 "$UP_BASE")"
    fi

    #	Remove files if needed

    #	Repack

    Run mv "$UP_BASE" "$DIR/$REPACK_DIR"

    #	Don't use pipes. Errors are not handled correctly if pipes aree used.

    Run tar -C "$DIR" -cf "$DIR/repacked.tar" "$REPACK_DIR"

    #   The .orig file must uxe gzip compression

    tar="$DIR/repacked.tar"

    case "$DFILE" in
	*.bz2)
	    DFILE=$(echo $DFILE | sed "s/.bz2/.gz/")
	    ;;
	*.gz)
	    ;;
	 *)
	    Die "Unknown *.suffix in $DFILE"
	    ;;
    esac

    suffix=".gz"

    Run gzip --best "$tar"
    Run mv "$tar$suffix" "$DFILE"

    echo "Done $DFILE"
}

trap AtExit QUIT INT EXIT

if [ $# -eq 0 ]; then
    Help
else
    Main "$@"
fi

# End of file
