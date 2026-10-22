#!/bin/sh
# Installed as the container's /usr/bin/polaris-gamescope-session. Runs the
# session script this Polaris build ships, unchanged, on the host as a transient
# user unit (via the mounted user bus), so its gamescope, Xwayland and Steam are
# host processes.
#
# It cannot run in here: rootless podman puts the container in its own user
# namespace, which cannot read /proc/<pid>/exe or environ of any host process.
# The script's ownership checks then fail closed on Plasma's Xwayland and on the
# host Steam, and it wedges in a "retaining recovery claim" state.
rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
src=/usr/share/polaris/gamescope
dst="$rt/polaris-host-gamescope"

# Republish the scripts each run so they always match this Polaris build.
mkdir -p "$dst"
cp -f "$src/polaris-gamescope-session.sh" "$src/polaris-gamescope-runtime-lib.sh" "$dst/"

# Debug aid: on a readiness timeout, log which ownership check failed.
cat /usr/share/polaris-host/gamescope-ready-diag.sh >>"$dst/polaris-gamescope-runtime-lib.sh"
sed -i 's|^\( *\)\(echo "polaris-gamescope-session: owned nested gamescope-0/Xwayland not ready.*\)$|\1\2\n\1polaris_host_ready_diag "$marker" "$rt" >\&2 \|\| true|' \
  "$dst/polaris-gamescope-session.sh"

# systemd-run drops the caller's env: forward the session credential, geometry,
# HDR and audio hints Polaris hands the script.
fwd=$(env | sed -n 's/^\(POLARIS_[A-Za-z0-9_]*\|PULSE_SINK\|PIPEWIRE_NODE\|SDL_[A-Za-z0-9_]*\)=.*/-E \1/p')

# The host's gamescope (SteamOS 3.16.30) lacks --pipewire-composite-cursor.
# Readiness can take 30-45s while Steam starts; the script's default is 30s
# (Polaris itself waits 120s).
# KillMode=process: `start` returns once gamescope is up and leaves it running;
# `stop` tears it down.
exec systemd-run --user --quiet --collect --wait --pipe \
  -p KillMode=process \
  $fwd \
  -E POLARIS_GAMESCOPE_COMPOSITE_CURSOR=0 \
  -E POLARIS_GAMESCOPE_READY_TIMEOUT_SECONDS=90 \
  -E POLARIS_GAMESCOPE_RUNTIME_LIB="$dst/polaris-gamescope-runtime-lib.sh" \
  -E POLARIS_SESSION_PATH=/usr/bin:/bin \
  -- /usr/bin/bash "$dst/polaris-gamescope-session.sh" "$@"
