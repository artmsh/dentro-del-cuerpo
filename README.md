<h1 align="center">Dentro del cuerpo</h1>
<p align="center">A first-person macOS game: pilot a cell-sized drone through a patient's real anatomy, leg vein to brain.</p>
<p align="center">
  <b>Stage:</b> alpha · <b>Target:</b> personal project · <b>License:</b> Apache-2.0 (code), CC BY 4.0 (artwork)
  <br>
  <a href="#installation">Installation</a> · <a href="#controls">Controls</a> · <a href="docs/DESIGN.md">Design</a> · <a href="docs/ARCHITECTURE.md">Architecture</a>
</p>

<p align="center">
  <a href="https://github.com/artmsh/dentro-del-cuerpo/releases/latest"><img src="https://img.shields.io/github/v/release/artmsh/dentro-del-cuerpo?label=download" alt="Latest release"></a>
  <a href="https://github.com/artmsh/dentro-del-cuerpo/releases"><img src="https://img.shields.io/github/downloads/artmsh/dentro-del-cuerpo/total" alt="Total downloads"></a>
  <a href="https://github.com/artmsh/dentro-del-cuerpo/actions/workflows/ci.yml"><img src="https://github.com/artmsh/dentro-del-cuerpo/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
</p>

<p align="center"><img src="docs/images/vein-biofilm.jpg" width="720" alt="Screenshot of chapter 1: the right arm drills a yellow biofilm colony open inside a vein while the left arm is set to shoot."></p>
<p align="center"><sub>Chapter 1, treating a septic microthrombus: one arm drills the biofilm open, the other fires into it. Rendered offscreen by <code>dentro --shots</code> through the game's Metal pipeline (<a href="docs/images/capture.sh">capture.sh</a>).</sub></p>

> [!WARNING]
> **Alpha.** Chapters 1 and 2 of 11 are playable, about five minutes each; chapters 3 to 11 and the two
> hidden chapters exist only as design and as entries on the route map. A scripted pilot in
> `zig build test` finishes both playable chapters. The campaign is complete when all eleven chapters in
> [DESIGN.md](docs/DESIGN.md) are playable.

*Inside the Body.* A doctor pilots the drone in through a vein in the patient's right leg and organ by organ
to the brain, treating what it finds on the way. Written in Zig over AppKit and Metal, with no other
dependencies.

## Rationale

Each chapter is built around one real structure the player has to learn to read before the objective can be
solved: the sinus bulge and cusps of a venous valve, the villi and travelling contraction ring of the
jejunum, and in later chapters the hexagonal liver lobule or the cardiac cycle read from valve states. The
anatomy, pathogens and dimensions are real (one world unit is one micrometre); the drone, its tools and the
pace are fiction, and the in-game atlas labels which is which.

## Features

- Two independent arms, each with its own key, tool (Punch, Drill or Shoot), HUD panel, half of the reticle,
  colour and stereo side. A drill stays locked in its cut while its key is held, so the pilot can work the
  other arm on something else.
- Anatomy defined as analytic functions (`src/vein.zig`, `src/gut.zig`) from which the mesh, collision,
  the flow that carries the drone and the reticle ray casts are all derived.
- Dr. Marín on comms: `T` names what the reticle is on and files it in the atlas, `T` again gives the longer
  explanation, `H` gives three levels of hint per objective.
- Chapter 1, Vein: pulsed parabolic flow, two venous valves to time, a septic microthrombus to treat with
  both arms at once, emboli to dissolve before they reach the lungs, the Sync Servo upgrade and a debrief
  with a grade.
- Chapter 2, Intestines: a chyme stream fast above the villus tips and still between them, peristaltic
  contractions to wait out, a scan that separates rotavirus-infected cells from commensal bacteria, and the
  Mucus Tether upgrade.
- Audio synthesised at runtime, with no sample files; each arm's sounds are panned to its side.

<p align="center">
  <img src="docs/images/jejunum-viroplasm.jpg" width="360" alt="Screenshot of chapter 2: a pink viroplasm dome among villi in the jejunum, with yellow bacteria in the stream.">
  <img src="docs/images/route-map.jpg" width="360" alt="Screenshot of the route map: a body outline with eleven numbered stops and the chapter list.">
</p>
<p align="center"><sub>Left: chapter 2, the viroplasm dome that needs drill and shot together. Right: the route map with chapter 1's briefing.</sub></p>

## Comparison

Compared with [Cell Sword](https://classyk.itch.io/cell-sword) 1.2.2 (Classyk Games, June 2025), the closest
game found: a shooter flown inside the human body.

| | Dentro del cuerpo | [Cell Sword](https://classyk.itch.io/cell-sword) |
|---|---|---|
| Setting | real anatomy and pathogens (*S. aureus*, rotavirus) | fictional nanobot disease ("Rust") |
| Movement | first person, two independently aimed arms | 6DoF ship, cockpit or third-person view |
| Content | 2 chapters, about 5 minutes each | 12-mission campaign, 5 difficulty levels |
| Platforms | macOS 14+ on Apple Silicon, built from source | Windows, macOS, Linux; $7.99 |
| Input | keyboard and mouse | keyboard, mouse, gamepads; remappable |
| Engine | none: Zig on AppKit and Metal | Godot |

Cell Sword is the one to play for a finished campaign, a gamepad, or a Windows or Linux machine.

## Requirements

- An Apple Silicon Mac with macOS 14 or later.
- Zig 0.17 to build from source.

## Installation

Download `Dentro-del-cuerpo-macos-arm64.zip` from the
[latest release](https://github.com/artmsh/dentro-del-cuerpo/releases/latest) and unzip it. Every push to
`main` that passes the tests is published there by [CI](.github/workflows/ci.yml).

The app is signed ad hoc and not notarised by Apple, so macOS quarantines the download and refuses the first
launch. Clear the quarantine flag once, or approve the app under System Settings → Privacy & Security →
Open Anyway after the first refused launch:

```sh
xattr -dr com.apple.quarantine "Dentro del cuerpo.app"
open "Dentro del cuerpo.app"
```

To build from source instead:

```sh
zig build -Doptimize=ReleaseFast          # builds zig-out/Dentro del cuerpo.app (signed ad hoc)
open "zig-out/Dentro del cuerpo.app"      # or double-click it in Finder
```

`zig build run -- --fullscreen` runs the bare binary. Cmd+F toggles full screen, Cmd+Q quits. Chapter 2
unlocks on the route map when chapter 1 is finished; `--chapter 2` opens it directly. Progress is saved to
`~/Library/Application Support/Dentro del cuerpo/save.txt`.

## Controls

| | |
|---|---|
| Move | `W A S D`, `Space` up, `C` down, `Shift` boost |
| Look | mouse, or arrow keys |
| Left arm | hold `Q` or left mouse button |
| Right arm | hold `E` or right mouse button |
| Left arm tool | `Z` cycles; `1` Punch, `2` Drill, `3` Shoot |
| Right arm tool | `X` cycles; `8` Punch, `9` Drill, `0` Shoot |
| Identify what the reticle is on | `T` (or `F`); again for the longer explanation. In chapter 2 it is also the scan pulse |
| Mucus Tether (chapter 2 upgrade) | `G` on tissue within 0.4 mm attaches and reels in; `G` on nothing releases |
| Ask Dr. Marín for a hint | `H` (three levels per objective) |
| Skip the current comms line | `Tab` |
| Pause | `Esc`; then `R` relaunch from checkpoint, `N` restart chapter, `L` title |
| Route map (from the title) | `M` |

After the chapter 1 upgrade, triggering both arms within 0.12 s lands them as one Sync Strike.

## Scope

A personal project, built for the author and published as-is. Chapters 3 to 11 are designed in
[DESIGN.md](docs/DESIGN.md): the patient, the route between organs and, for each chapter, the feature to
read, the objective, the challenge and the upgrade. The first hidden chapter's trigger (three cells in the
vein that should not be in circulating blood) is already in chapter 1.

## Limitations

- Apple Silicon and Metal only: there is no Intel, Windows or Linux build.
- No gamepad support and no key remapping.

## Development

```sh
zig build test                 # unit tests and a scripted pilot that must finish both chapters
zig-out/bin/dentro --selftest  # the same playthroughs, with a printed summary
zig-out/bin/dentro --shots DIR # offscreen GPU render of the menus and every stage, one BMP each
zig-out/bin/dentro --inputtest # opens the window and drives it with synthetic key events
zig-out/bin/dentro --demo      # the scripted pilot flies chapter 1 in the window, with audio
zig-out/bin/dentro --chapter 2 --demo
```

```text
Build Summary: 3/3 steps succeeded; 31/31 tests passed
…
selftest ch2: completed=true stage=done sim_time=86.8s deaths=0 stability=100.0 grade=A atlas=3
…
selftest: completed=true stage=done sim_time=107.4s deaths=0
  stability=95.5 hull=100 grade=A atlas=3
```

Source layout and build decisions are in [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

Source code is licensed under [Apache-2.0](LICENSE). Artwork and writing (the icon in `res/`, the images in
`docs/images/`, the game's script and atlas text, and the design documents in `docs/`) are licensed under
[CC BY 4.0](LICENSE-ARTWORK.txt); attribute them to "Dentro del cuerpo" with a link to this repository.
