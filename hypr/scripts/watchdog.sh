#!/bin/sh

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lumen-watchdog.lock"
flock -n 9 || exit 0

launch() {
  # Wait for the Hyprland XDG desktop portal backend.
  # This prevents Quickshell from racing portal startup.
  i=0
  while [ "$i" -lt 30 ]; do
    systemctl --user is-active --quiet xdg-desktop-portal-hyprland.service && break
    sleep 1
    i=$((i + 1))
  done

  # Start the default Quickshell configuration.
  qs -d 9>&- 2>/dev/null

  # Wait until Quickshell IPC is available.
  i=0
  while [ "$i" -lt 30 ]; do
    qs ipc show >/dev/null 2>&1 && return
    sleep 1
    i=$((i + 1))
  done
}

while true; do
  qs ipc show >/dev/null 2>&1 || launch
  sleep 5
done
