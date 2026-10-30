#!/bin/sh
#
# Step the focused monitor to the next or previous numbered workspace, wrapping
# within 1-10 so Super+Left/Right (and Super+scroll) stay on the same ten
# desktops Super+1..0 reach. Hyprland's relative `r+1` would keep creating
# workspace 11, 12, ... past the end.
#
#   workspace-step.sh next | prev

max=10

cur=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1')
# A special workspace (negative id) or a named one steps from 1.
case "$cur" in
'' | *[!0-9]*) cur=1 ;;
esac
[ "$cur" -ge 1 ] && [ "$cur" -le "$max" ] || cur=1

case "$1" in
next) target=$((cur % max + 1)) ;;
prev) target=$(((cur + max - 2) % max + 1)) ;;
*) exit 1 ;;
esac

hyprctl dispatch "hl.dsp.focus({ workspace = $target })" >/dev/null
