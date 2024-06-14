#!/bin/bash

# Automates the extraction, installation, and configuration of Cadence tools, tailored for working with Rocky Linux 8.

set -eo pipefail

[ "$EXTRACTROOT" ] || EXTRACTROOT="$(pwd)/extracted"
[ "$INSTALLROOT" ] || INSTALLROOT="/eda/cadence"
[ "$ISCAPE" ] || ISCAPE="iscape.sh"

errorout() {
	echo -e "error: ${@:2}" >&2
	exit "$1"
}

checkcmd() {
	firstarg() { echo "$1"; }
	cmdname=$(firstarg $2)
	command -v "$cmdname" >/dev/null 2>&1 || errorout "$1" "Command '$cmdname' not found. Make sure it is included in PATH, or set the variable ISCAPE to the appropriate path prior to running the script."
}

myecho() {
    echo -en '\033[1;93m'; echo "$@"; echo -en '\033[0m'
}

myhack() {
    echo -en '\033[5m\033[1;31m(HACK)\033[0m '
    myecho "$@"
}

mywarn() {
    echo -en '\033[1;31mwarning:\033[0m '
    myecho "$@"
}

is_tgz() {
	file "$1" | grep -q 'gzip compressed data'
}

is_tar() {
	file "$1" | grep -q 'POSIX tar archive'
}

[ $# -gt 0 ] || errorout 1 """No arguments specified
usage: ./cds_install_from_archives.sh FILENAME|DIRECTORY...
       NOCONFIGURE=1 ./cds_install_from_archives.sh FILENAME|DIRECTORY...
       NOINSTALL=1 ./cds_install_from_archives.sh INSTALL_DIRECTORY...
The second form will only install from archive without configuring the product.
The third form will only configure an already existing installation.

examples: ./cds_install_from_archives.sh tool1_version_lnx86.tgz tool2_version_lnx86.tgz extracted/tool3/tool3_version/
          NOCONFIGURE=1 ./cds_install_from_archives.sh tool1_version_lnx86.tgz tool2_version_lnx86.tgz extracted/tool3/tool3_version/
	  NOINSTALL=1 ./cds_install_from_archives.sh installed/tool1/tool1_version installed/tool2/tool2_version\
"""
checkcmd 7 "$ISCAPE"

if [ "$NOINSTALL" = "1" ]; then
	for DIRNAME in "$@"; do
		[ -d "$DIRNAME" ] || errorout 5 "Directory '$DIRNAME' doesn't exist"
		[ $(find "$DIRNAME" -maxdepth 1 -name 'bin' 2>/dev/null | head -n 1) ] ||\
			errorout 6 "Directory '$DIRNAME' is not a valid Cadence installation directory since it doesn't contain a 'bin' directory"
		[ "$INSTALLDIRS" ] && INSTALLDIRS=$(echo -e "$INSTALLDIRS\n$DIRNAME") || INSTALLDIRS="$DIRNAME"
	done
else
	for FILENAME in "$@"; do [ -f "$FILENAME" ] || [ -d "$FILENAME" ] || errorout 2 "File or directory '$FILENAME' does not exist"; done
	for FILENAME in "$@"; do
		is_tgz "$FILENAME" || is_tar "$FILENAME" || [ -d "$FILENAME" ] || errorout 3 "File '$FILENAME' is neither a gzip compressed archive nor a tar archive, nor a directory"
	done
	for FILENAME in "$@"; do
		[ -d "$FILENAME" ] && { [ $(find "$FILENAME" -maxdepth 1 -iname '*.sdp' 2>/dev/null | head -n 1) ] ||\
                	errorout 4 "Directory '$FILENAME' is not a valid Cadence archive directory since it doesn't contain a .sdp file"; }
	done
fi

if [ "$NOINSTALL" = "1" ]; then
myecho "--- Skipping install stage (NOINSTALL=1) ---"
else
myecho "--- Entering install stage ---"
for FILENAME in "$@"; do
	if [ -d "$FILENAME" ]; then
		SDPFILE=$(find "$FILENAME" -maxdepth 1 -iname '*.sdp' 2>/dev/null | head -n 1)
		[ "$SDPFILE" ] || errorout 4 "Directory '$FILENAME' is not a valid Cadence archive directory since it doesn't contain a .sdp file"
	else
		if is_tgz "$FILENAME"; then
	                TAR_XOPTS="-zxvf"
        	elif is_tar "$FILENAME"; then
                	TAR_XOPTS="-xvf"
	        else
			errorout 200 "Unknown error"
		fi
		mkdir -p "$EXTRACTROOT"
		myecho "Extracting '$FILENAME' to '$EXTRACTROOT'..."
		TAROUT=$(tar "$TAR_XOPTS" "$FILENAME" -C "$EXTRACTROOT")
		SDPFILE=$(sed -n '/.[sS][dD][pP]$/{p;q}' <<<"$TAROUT")
	fi
	SDPBASE=$(basename "$SDPFILE")
	RELARCHIVEDIR=$(dirname "$SDPFILE")
	if [ -d "$FILENAME" ]; then
		ARCHIVEDIR=$(realpath -e "$RELARCHIVEDIR")
	else
		ARCHIVEDIR=$(realpath -e "$EXTRACTROOT/$RELARCHIVEDIR")
	fi
	myecho "ARCHIVEDIR=$ARCHIVEDIR"
	PRODUCTNAME=$(grep -Po '[^_[:digit:]]*(?=[[:digit:]])' <<<"$SDPBASE" | head -n 1 | sed 's/[mM][aA][iI][nN]$//')
	myecho "PRODUCTNAME=$PRODUCTNAME"
	PRODUCTVERSION=$(grep -o '[[:digit:]][^_]*' <<<"$SDPBASE" | head -n 1)
	myecho "PRODUCTVERSION=$PRODUCTVERSION"
	INSTALLDIR="$INSTALLROOT/$PRODUCTNAME/$PRODUCTNAME$PRODUCTVERSION"
	myecho "INSTALLDIR=$INSTALLDIR"

	mkdir -p "$INSTALLROOT/$PRODUCTNAME"
	myecho "Install command: $ISCAPE -batch majorAction=InstallFromArchive archiveDirectory=\"$ARCHIVEDIR\" installDirectory=\"$INSTALLDIR\""
	myecho "Installing..."
	$ISCAPE -batch majorAction=InstallFromArchive archiveDirectory="$ARCHIVEDIR" installDirectory="$INSTALLDIR"
	[ "$INSTALLDIRS" ] && INSTALLDIRS=$(echo -e "$INSTALLDIRS\n$INSTALLDIR") || INSTALLDIRS="$INSTALLDIR"

	if [ ! -e "$INSTALLDIR/tools" ]; then
		myecho "Creating symbolic link: ln -s \"tools.lnx86\" \"$INSTALLDIR/tools\""
		ln -s "tools.lnx86" "$INSTALLDIR/tools"
	fi

	CHECKSYSCONF_PATH="$INSTALLDIR/tools.lnx86/bin/checkSysConf"
	myecho "Backing up checkSysConf to checkSysConf~ before applying patches..."
	cp -f "$CHECKSYSCONF_PATH" "$CHECKSYSCONF_PATH~"
	if grep -q "If not CentOS or Red Hat, it's unsupported" "$CHECKSYSCONF_PATH"; then
		myhack "Patching checkSysConf to work on Rocky"
		sed -i 's/set centos[[:space:]]*=.*/set centos = `grep '\''CentOS\\|Rocky'\'' "\/etc\/redhat-release"`/' "$CHECKSYSCONF_PATH"
	fi
	myhack "Patching checkSysConf to not merge separate fields while printing tables..."
	sed -i -e '/fmt[A-Za-z0-9_]* *=/ s/\([a-mo-zA-Z]\)%/\1 %/g' -e 's/\(printf *\)\($fmt[a-zA-Z0-9_]*\)/\1"\2"/g' "$CHECKSYSCONF_PATH"
	if [ ! -e "$INSTALLDIR/share/patchData/Linux/x86_64/redhat/8.0WS" ]; then
		myhack "Creating symbolic link: ln -s 7.0WS \"$INSTALLDIR/share/patchData/Linux/x86_64/redhat/8.0WS\""
                ln -s 7.0WS "$INSTALLDIR/share/patchData/Linux/x86_64/redhat/8.0WS"
	fi

	myecho "Setting mode 'g-w,o=' to '$INSTALLDIR' (non-recursive)..."
	chmod g-w,o= "$INSTALLDIR"
	echo
done
fi
myecho "INSTALLDIRS=${INSTALLDIRS//$'\n'/ }"
echo

myecho "--- Entering checkSysConf stage ---"
while IFS= read -u 3 -r INSTALLDIR; do
	CHECKSYSCONF_PATH="$INSTALLDIR/tools.lnx86/bin/checkSysConf"
	myecho -n "Running checkSysConf for $(basename "$INSTALLDIR")... "
        RELEASES=$("$CHECKSYSCONF_PATH" -r | awk 'BEGIN{extract=0}; extract==1&&NF==1&&$1!="8.0WS"{print $1}; extract==1&&NF!=1{quit}; /Valid release names are/{extract=1};') || true
        myecho "valid release names are: ${RELEASES//$'\n'/, }"
        for RELEASE in $RELEASES; do
                MISSING_PKGS=$("$CHECKSYSCONF_PATH" "$RELEASE" | awk '/Package not installed/{if($6=="FAIL"){sub(/[0-9.]*$/,"", $2); print $2 "." $5}else{print $2 "." $6}}') || true
                [ "$MISSING_PKGS" ] && mywarn "Release '$RELEASE' has the following missing packages: ${MISSING_PKGS//$'\n'/ }"
        done
	[ "$CONCAT_MISSING_PKGS" ] || CONCAT_MISSING_PKGS="$MISSING_PKGS" && CONCAT_MISSING_PKGS=$(echo -e "$CONCAT_MISSING_PKGS\n$MISSING_PKGS")
	echo
done 3<<<"$INSTALLDIRS"

TOTAL_MISSING_PKGS=$(sort -u <<<"$CONCAT_MISSING_PKGS")
if [ "$TOTAL_MISSING_PKGS" ]; then
	mywarn "There are missing packages in your system. It is highly advisable to install them before proceeding with the configuration of the tools."
	myecho "All missing packages: ${TOTAL_MISSING_PKGS//$'\n'/ }"
	[ "$NOCONFIGURE" = "1" ] || while read -r -p $'\033[1;93mInput y to continue:\033[0m '; do case "$REPLY" in y) break;; esac; done
	echo
fi

if [ "$NOCONFIGURE" = "1" ]; then
myecho "--- Skipping configure stage (NOCONFIGURE=1) ---"
else
myecho "--- Entering configure stage ---"
while IFS= read -u 3 -r INSTALLDIR; do
	myecho "Configuring $(basename "$INSTALLDIR")..."
	myecho "Configure command (part 1): $ISCAPE -batch majorAction=Configure installDirectory=\"$INSTALLDIR\""
	CONFIGUREOUT=$($ISCAPE -batch majorAction=Configure installDirectory="$INSTALLDIR" | tee /dev/tty)
	CONFIGURECMDLINE=$(awk '/To configure products run the script/{getline; print}' <<<"$CONFIGUREOUT")
	if [ "$CONFIGURECMDLINE" ]; then
		myecho "Configure command (part 2): $CONFIGURECMDLINE"
		eval "$CONFIGURECMDLINE"
	else
		mywarn "Could not detect valid configure command from iscape configure output"
	fi
	echo
done 3<<<"$INSTALLDIRS"
fi

myecho "--- Done ---"
