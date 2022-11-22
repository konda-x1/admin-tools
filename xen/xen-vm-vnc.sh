#!/bin/bash

# Description:
# Provides a VNC connection to a Xen VM without the need to configure networking or install
# a VNC server on the target VM, as long as there is a connection to the Xen server itself.
#
# Connects to a Xen server via ssh, lists available VMs and lets you choose which VM you
# want to connect to via VNC. Locally you must have vncviewer installed, and the remote
# needs to have ss and xe available. If Xen doesn't expose local VNC ports, the remote
# also needs to have socat available. The VNC connection works by first creating an ssh
# tunnel and then connecting to 127.0.0.1 with the appropriate port on the remote host --
# vncviewer takes care of this. And the script ensures the appropriate local port on the
# remote host is forwarded to point to a corresponding VNC socket file located in
# /var/run/xen if the host doesn't already expose that port locally.

set -e

if ! command -v vncviewer &>/dev/null; then
	echo "error: Command 'vncviewer' not found" >&2
	exit 1
fi

if [ ! "$1" ]; then
	>&2 echo "\
usage: $0 [user@]hostname [vncviewer-options]"
	exit 2
fi

sshhost="$1"

remotescript=$(cat <<'SSHEOF'
sh -c 'sleeptime=5; if [ $(basename "$SHELL") != "bash" ]; then echo "Warning: remote shell ($SHELL) is not 'bash'. This script might not work properly. Sleeping for $sleeptime seconds" >&2; sleep "$sleeptime"; fi'
set -e
require_cmd() {
	for cmd in "$@"; do if ! command -v "$cmd" &>/dev/null; then
		echo "remote: Command '$cmd' not found" >&2
		exit 3
	fi; done
}
require_cmd xe ss

uuids=$(xe vm-list power-state=running params=uuid | awk -F'[[:space:]]*:[[:space:]]*' 'NF==2{print $2}')
doms=$(while IFS= read -u 3 -r i; do
	gp() { xe vm-param-get uuid="$i" param-name="$1"; }
	printf "%s\n%s\n%s\x00" "$(gp dom-id)" "$i" "$(gp name-label)"
done 3<<<"$uuids" | sort -nz | tr '\0' '\n')
options=()
while IFS= read -u 3 -r domid; do
	IFS= read -u 3 -r uuid
	IFS= read -u 3 -r namelabel
	options+=("dom${domid}: $namelabel (uuid: $uuid)")
done 3<<<"$doms"

echo "Select a VM/domain to make a VNC connection for:" >&2
PS3="Enter your choice: "
COLUMNS=0
select opt in "${options[@]}"
do
	[ -n "$opt" ] && break || echo "Invalid option" >&2
done

item="$REPLY"
if ((item > 1)); then
	domid=$(head -n 1 < <(sed "1,$(( (item-1) * 3))d" <<<"$doms"))
else
	domid=$(head -n 1 <<<"$doms")
fi

remoteport=$((5900+domid))
if ! ss -4tan |  awk 'NR>1{print $4}' | awk -F':' '{print $NF}' | grep -q "^$remoteport$"; then
	require_cmd socat
	(socat TCP-LISTEN:"$remoteport",fork,bind=127.0.0.1 UNIX-CONNECT:/var/run/xen/vnc-"$domid" &>/dev/null &) || true
fi

echo "$domid"
SSHEOF
)

vncport=$(ssh "$sshhost" "$remotescript")
vncviewer -via "$sshhost" "127.0.0.1:$vncport" "${@:2}"
