
# Appended by gamescope-session-forward.sh to the host copy of
# polaris-gamescope-runtime-lib.sh. Called when the nested session's readiness
# check times out, to show which ownership check failed.
polaris_host_ready_diag() {
  local m="$1" rt="$2" ino d p
  echo "ready-diag: marker: $(cat "$m" 2>&1)"
  polaris_validate_marker "$m" nested
  echo "ready-diag: validate_marker rc=$? pid=${POLARIS_MARKER_PID:-} exe=${POLARIS_MARKER_EXECUTABLE:-}"
  ino="$(polaris_socket_inode "$rt/gamescope-0")"
  echo "ready-diag: gamescope-0 inode=$ino rc=$?"
  polaris_marker_owns_socket "$m" "$rt/gamescope-0" nested
  echo "ready-diag: owns gamescope-0 rc=$?"
  d="$(polaris_discover_xwayland_display "$m" nested)"
  echo "ready-diag: xwayland display=$d rc=$?"
  polaris_validate_marker "$m" nested
  polaris_validate_process_generation "${POLARIS_MARKER_PID:-}" "${POLARIS_MARKER_START_TIME:-}" "${POLARIS_MARKER_EXECUTABLE:-}"
  echo "ready-diag: process generation rc=$?"
  grep -E ' (/tmp/\.X11-unix/X[0-9]+|.*/gamescope-0)$' /proc/net/unix | sed 's/^/ready-diag: unix: /'
  for p in $(pgrep -f '(^|/)Xwayland([[:space:]]|$)'); do
    echo "ready-diag: Xwayland pid=$p ppid=$(ps -o ppid= -p "$p" | tr -d ' ') exe=$(readlink "/proc/$p/exe" 2>&1) argv=$(tr '\0' ' ' <"/proc/$p/cmdline" | cut -c1-120)"
  done
}
