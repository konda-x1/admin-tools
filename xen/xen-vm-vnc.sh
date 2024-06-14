#!/bin/bash

# Provides a VNC connection to a Xen VM without the need to configure networking or install
# a VNC server on the target VM, as long as there is a connection to the Xen server itself.
#
# Connects to a Xen server via ssh, lists available VMs and lets you choose which VM you
# want to connect to via VNC. Locally you must have vncviewer installed, and the remote
# needs to have 'xe' available. If Xen doesn't expose local VNC ports, the remote also needs
# to have 'socat' available. The VNC connection works by first creating an ssh tunnel and
# then connecting to 127.0.0.1 with the appropriate port on the remote host --vncviewer
# takes care of this. And the script ensures the appropriate local port on the remote
# host is forwarded to point to a corresponding VNC socket file located in
# /var/run/xen if the host doesn't already expose that port locally.

set -e

if ! command -v vncviewer &>/dev/null; then
	echo "error: Command 'vncviewer' not found" >&2
	exit 1
fi

if [ ! "$1" ]; then
	>&2 echo "usage: $0 [user@]hostname [vncviewer-options]"
	exit 2
fi

host="$1"
sock="/tmp/.ssh-%C%i"
sshmux() { ssh -o ControlMaster=auto -o ControlPath="$sock" -o ControlPersist=1m "$@"; }

remote_script=$(cat <<'SSHEOF'
sh -c 'sleeptime=5; if [ $(basename "$SHELL") != "bash" ]; then echo "Warning: remote shell ($SHELL) is not 'bash'. This script might not work properly. Sleeping for $sleeptime seconds" >&2; sleep "$sleeptime"; fi'
set -e

uuids=$(xe vm-list power-state=running params=uuid | awk -F'[[:space:]]*:[[:space:]]*' 'NF==2{print $2}')
while IFS= read -u 3 -r i; do
	gp() { xe vm-param-get uuid="$i" param-name="$1"; }
	printf "%s\n%s\n%s\x00" "$(gp dom-id)" "$i" "$(gp name-label)"
done 3<<<"$uuids" | sort -nz | tr '\0' '\n'
SSHEOF
)

doms=$(sshmux "$host" "$remote_script")
options=()
while IFS= read -u 3 -r domid; do
	IFS= read -u 3 -r uuid
	IFS= read -u 3 -r name_label
	options+=("dom${domid}: $name_label (uuid: $uuid)")
done 3<<<"$doms"

echo "Select a VM/domain to make a VNC connection to:" >&2
PS3="Enter your choice: "
COLUMNS=0
select opt in "${options[@]}"; do
	[ -n "$opt" ] && break || echo "Invalid option" >&2
done
domid=$(sed -n $((REPLY * 3 - 2))p <<<"$doms")

sed -n 1q <(2>&1 sshmux -n "$host" "</dev/null socat -d -d -d -d\
            TCP-LISTEN:$((5900 + domid)),fork,bind=127.0.0.1\
            UNIX-CONNECT:/var/run/xen/vnc-$domid & sleep 20")
# Passing the "%" symbols through a variable so vncviewer
# doesn't do something with them before they reach ssh
S=$sock VNC_VIA_CMD='ssh -f -S "$S" -L "$L":"$H":"$R" "$G" :'\
    vncviewer -via "$host" "127.0.0.1:$domid" "${@:2}"

