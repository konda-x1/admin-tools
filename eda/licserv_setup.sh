#!/bin/bash

# Sets up a directory hierarchy for FlexLM license server. Also creates the appropriate
# user and group, sets the appropriate permissions in the directory hierarchy, and
# produces a systemd service file. Also installs the necessary packages and some optional
# ones. Essentially, does everything necessary for normal operation of the license server
# daemon, aside from actually installing a FlexLM license server or setting up a specific
# license file for use.
#
# Three symlinks are created that point to /dev/null:
# * LCU/current: Points to the current LCU installation directory hierarchy
# * LCU/licenses/current.lic: Points to the currently used license file
# * LCU/options/current.opt: Points to the currently used options file
# The administrator is to recreate these symlinks that point to actual data on disk.
# Ideally, the symlinks should point to items that are located in the same directory.

[ "$lcu_root" ] || lcu_root="/eda/cadence/LCU"
[ "$lcu_bin_dir" ] || lcu_bin_dir="$lcu_root/current/bin"
[ "$service_root" ] || service_root="/etc/systemd/system"

mynotify() {
	echo -n "$0: " >&2
	echo "$@" >&2
}

# Install packages you'll probably need for one reason or another
elmgr=
for i in dnf yum; do
	if command -v "$i" &>/dev/null; then
		elmgr="$i"
		break
	fi
done
if [ "$elmgr" ]; then
	mynotify "Using package manager '$elmgr' to install packages"
#    sed -i -e 's/^mirrorlist=/#mirrorlist=/' -e 's/^#baseurl=/baseurl=/' /etc/yum.repos.d/*.repo # For use in restricted networks
	"$elmgr" upgrade -y
#	"$elmgr" config-manager --set-enabled powertools
#	"$elmgr" install -y epel-release
	"$elmgr" install -y tmux nano tcsh ksh perl tar nc java redhat-lsb
else
	mynotify "No compatible package manager found. Skipping package installation"
fi

# Create flexlm user and group if doesn't exist
if ! getent group flexlm >/dev/null; then
	if ! getent passwd flexlm >/dev/null; then
		mynotify "Creating user and group 'flexlm'"
		useradd -MUr flexlm
	else
		mynotify "Detected user 'flexlm' but no group. Creating group 'flexlm' and adding user 'flexlm' to it"
		groupadd -r flexlm
		usermod -a -G flexlm flexlm
	fi
elif ! getent passwd flexlm >/dev/null; then
	mynotify "Detected group 'flexlm' but no user. Creating user 'flexlm' with default group 'flexlm'"
	useradd -Mr -g flexlm flexlm
fi

# Make directory hierarchy
mkdir -p "$lcu_root/"{licenses,logs,options}
chgrp -R flexlm "$lcu_root/"{licenses,logs,options}
chmod 4750 "$lcu_root"/{licenses,options}
chmod 4770 "$lcu_root/logs"
ln -s /dev/null "$lcu_root/current"
ln -s /dev/null "$lcu_root/licenses/current.lic"
ln -s /dev/null "$lcu_root/options/current.opt"

# Create service file
cat >"$service_root/flexlm.service" <<EOF
[Unit]
Description=FlexLM license server

[Service]
Type=simple
User=flexlm
SuccessExitStatus=15
ExecStart=/bin/sh -c '$lcu_bin_dir/lmgrd -z -c $lcu_root/licenses/current.lic -l +$lcu_root/logs/debug.log'
ExecStop=/bin/sh -c '$lcu_bin_dir/lmutil lmdown -c $lcu_root/licenses/current.lic -all -force || true'

[Install]
WantedBy=multi-user.target
EOF
