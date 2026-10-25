#!/bin/sh
# Install the fake display helper for the user Polaris runs as (default: the
# user running sudo). Everything goes under /etc; SteamOS's read-only root is
# left alone. Run as root: sudo ./install.sh [user]
set -eu
user="${1:-${SUDO_USER:?pass the user Polaris runs as}}"
here="$(dirname "$0")"
install -D -m 0755 "$here/polaris-fake-display" /etc/polaris-fake-display/polaris-fake-display
install -m 0644 "$here/polaris-fake-display@.service" "$here/polaris-fake-display-unplug.service" /etc/systemd/system/
install -m 0644 "$here/70-polaris-fake-display.rules" /etc/udev/rules.d/
sed "s/@USER@/$user/g" "$here/50-polaris-fake-display.rules" > /etc/polkit-1/rules.d/50-polaris-fake-display.rules
systemctl daemon-reload
udevadm control --reload
echo "installed for $user"
