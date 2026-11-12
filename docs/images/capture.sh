#!/usr/bin/env bash
# Regenerate the README screenshots from the game's own offscreen renderer.
# Run from the repo root after `zig build`: docs/images/capture.sh
set -euo pipefail
out=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# One language at a time, and its frames deleted before the next: a run is over half a gigabyte of BMP.
# --shots exits non-zero if a frame could not be written or a chapter did not complete, which stops this.
shots() {
    rm -rf "$tmp/frames"
    zig-out/bin/dentro --lang "$1" --shots "$tmp/frames" >/dev/null 2>"$tmp/log" || { cat "$tmp/log" >&2; return 1; }
}

# A frame is picked by its name, not its number: the numbers shift whenever --shots gains a frame. Where
# a name repeats (the "-more" frames of a stage), the first one is taken.
pick() {
    local f
    for f in "$tmp/frames"/[0-9]*-"$1".bmp; do
        if [ -e "$f" ]; then printf '%s\n' "$f"; return; fi
    done
    echo "capture: --shots wrote no frame named $1" >&2
    return 1
}

# JPEG: rendered gradients band under PNG8 palette quantisation
jpg() {
    local src
    src=$(pick "$1")
    magick "$src" -resize "$2x>" -strip -quality 82 "$out/$3.jpg"
}

shots en
jpg treat 1440 vein-biofilm               # chapter 1: drilling a biofilm colony open while the other arm shoots
jpg g_factory-more 720 jejunum-viroplasm  # chapter 2: the viroplasm dome
jpg map 720 route-map                     # route map from the title screen
shots uk
jpg g_extrude-more 1440 jejunum-uk        # chapter 2 in Ukrainian: infected cells on a villus tip
