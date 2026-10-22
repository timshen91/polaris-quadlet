#!/bin/sh
# Installed as the container's /usr/bin/steam. Polaris launches Steam titles by
# running `steam ...`; forward that to the host's /usr/bin/steam as a transient
# host user unit (via the mounted user bus), which hands steam:// URLs and
# -applaunch to the already-running Steam client, or starts one.
#
# systemd-run drops the caller's env, so forward the display Polaris picked
# (its labwc or headless gamescope), the gamescope/Steam integration vars, the
# stream audio sink, and the POLARIS_* tags it uses to find its own Steam.
fwd=$(env | sed -n 's/^\(WAYLAND_DISPLAY\|DISPLAY\|XDG_CURRENT_DESKTOP\|POLARIS_[A-Za-z0-9_]*\|SDL_[A-Za-z0-9_]*\|GAMESCOPE_[A-Za-z0-9_]*\|STEAM_[A-Za-z0-9_]*\|ENABLE_GAMESCOPE_WSI\|DISABLE_HDR_WSI\|DXVK_HDR\|PULSE_SINK\|PIPEWIRE_NODE\|QT_QPA_PLATFORM\)=.*/-E \1/p')

# The user manager carries Plasma's WAYLAND_DISPLAY/DISPLAY. Under headless
# gamescope the caller has no WAYLAND_DISPLAY (games must use XWayland plus
# GAMESCOPE_WAYLAND_DISPLAY), so drop whichever of the two the caller lacks.
unset_args=
for v in WAYLAND_DISPLAY DISPLAY; do
  eval "[ -n \"\${$v+x}\" ]" || unset_args="$unset_args -u $v"
done

# In /usr/bin, not /usr/local/bin: Private Stream runs its command with PATH=/usr/bin:/bin.
exec systemd-run --user --quiet --collect $fwd -- /usr/bin/env $unset_args /usr/bin/steam "$@"
