#!/usr/bin/env bash
# Regenerate the README screenshots from the game's own offscreen renderer.
# Run from the repo root after `zig build`: docs/images/capture.sh
set -euo pipefail
out=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/en" "$tmp/uk"
zig-out/bin/dentro --lang en --shots "$tmp/en" >/dev/null 2>&1
zig-out/bin/dentro --lang uk --shots "$tmp/uk" >/dev/null 2>&1
# JPEG: rendered gradients band under PNG8 palette quantisation
jpg() { magick "$tmp/$1.bmp" -resize "$2x>" -strip -quality 82 "$out/$3.jpg"; }
jpg en/28-treat 1440 vein-biofilm               # chapter 1: drilling a biofilm colony open while the other arm shoots
jpg en/57-g_factory-more 720 jejunum-viroplasm  # chapter 2: the viroplasm dome
jpg en/02-map 720 route-map                     # route map from the title screen
jpg uk/50-g_extrude-more 1440 jejunum-uk        # chapter 2 in Ukrainian: infected cells on a villus tip
