#!/usr/bin/env bash
# Regenerate the README screenshots from the game's own offscreen renderer.
# Run from the repo root after `zig build`: docs/images/capture.sh
set -euo pipefail
out=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
zig-out/bin/dentro --shots "$tmp" >/dev/null 2>&1
# JPEG: rendered gradients band under PNG8 palette quantisation
jpg() { magick "$tmp/$1.bmp" -resize "$2x>" -strip -quality 82 "$out/$3.jpg"; }
jpg 13-treat 1440 vein-biofilm               # chapter 1: drilling a biofilm colony open while the other arm shoots
jpg 42-g_factory-more 720 jejunum-viroplasm  # chapter 2: the viroplasm dome
jpg 01-map 720 route-map                     # route map from the title screen
