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
to the brain, treating what it finds on the way. It is playable in English and Ukrainian. Written in Zig over
AppKit and Metal; the only third-party code is the vendored `stb_truetype.h`, which rasterises the bundled
fonts.

## Rationale

Each chapter is built around one real structure the player has to learn to read before the objective can be
solved: the sinus bulge and cusps of a venous valve, the villi and travelling contraction ring of the
jejunum, and in later chapters the hexagonal liver lobule or the cardiac cycle read from valve states. The
anatomy, pathogens and dimensions are real (one world unit is one micrometre); the drone, its tools and the
pace are fiction, and the in-game atlas labels which is which.

## Features

- Two independent arms, each with its own key or trigger, tool (Punch, Drill or Shoot), HUD panel, half of
  the reticle, colour and stereo side. A drill stays locked in its cut while its key is held, so the pilot
  can work the other arm on something else.
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
- Keyboard and mouse, or an Xbox, DualShock 4 or DualSense controller, over USB or Bluetooth with no
  driver or setup. The whole game can be played on the controller alone, menus included, and the two can
  be mixed at any moment. Every prompt on screen names the control of the device used last, in that
  controller's own terms (`A`, `LT`, `Menu` or `✕`, `L2`, `Options`).
- Audio synthesised at runtime, with no sample files; each arm's sounds are panned to its side.
- English and Ukrainian throughout: HUD, menus, route map, briefing, debrief, Dr. Marín's lines, hints and
  the atlas. The language follows the system's preference list on first launch and can be switched with
  `Tab` (`View` on a controller) on the title and pause screens; the choice is saved. A string without a Ukrainian translation fails
  the build or the tests, so the game never falls back to English mid-screen.

<p align="center">
  <img src="docs/images/jejunum-viroplasm.jpg" width="360" alt="Screenshot of chapter 2: a pink viroplasm dome among villi in the jejunum, with yellow bacteria in the stream.">
  <img src="docs/images/route-map.jpg" width="360" alt="Screenshot of the route map: a body outline with eleven numbered stops and the chapter list.">
</p>
<p align="center"><sub>Left: chapter 2, the viroplasm dome that needs drill and shot together. Right: the route map with chapter 1's briefing.</sub></p>

<p align="center"><img src="docs/images/jejunum-uk.jpg" width="720" alt="Screenshot of chapter 2 in Ukrainian: the HUD, the objective and Dr. Marín's subtitle are in Ukrainian while the drone hovers over villi in a stream of bacteria."></p>
<p align="center"><sub>Chapter 2 in Ukrainian (<code>dentro --lang uk</code>, or <code>Tab</code> on the title screen).</sub></p>

## Comparison

Compared with [Cell Sword](https://classyk.itch.io/cell-sword) 1.2.2 (Classyk Games, June 2025), the closest
game found: a shooter flown inside the human body.

| | Dentro del cuerpo | [Cell Sword](https://classyk.itch.io/cell-sword) |
|---|---|---|
| Setting | real anatomy and pathogens (*S. aureus*, rotavirus) | fictional nanobot disease ("Rust") |
| Movement | first person, two independently aimed arms | 6DoF ship, cockpit or third-person view |
| Content | 2 chapters, about 5 minutes each | 12-mission campaign, 5 difficulty levels |
| Platforms | macOS 14+ on Apple Silicon, built from source | Windows, macOS, Linux; $7.99 |
| Input | keyboard and mouse; Xbox and PlayStation controllers; fixed layout | keyboard, mouse, gamepads; remappable |
| Engine | none: Zig on AppKit and Metal | Godot |

Cell Sword is the one to play for a finished campaign, remappable controls, or a Windows or Linux machine.

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

`zig build run -- --fullscreen` runs the bare binary, and `zig build --prefix DIR` assembles and signs the
bundle under `DIR` instead of `zig-out`. Cmd+F toggles full screen; Cmd+Q quits, as does the `Quit game`
entry of the title and pause menus. Chapter 2 unlocks on the route map when chapter 1 is finished;
`--chapter 2` opens it directly. Progress is saved to
`~/Library/Application Support/Dentro del cuerpo/save.txt`, which keeps for each chapter the best grade
flown and, among runs of equal grade, the latest. The file is replaced whole on every save, so an
interrupted write leaves the previous one, and a save that cannot be written is reported once on stderr
while play goes on.

The game starts in Ukrainian if Ukrainian comes before English in the system's list of preferred languages,
and in English otherwise. `Tab` on the title or pause screen switches the language at once and the choice is
kept in the save file; `--lang en` or `--lang uk` sets it for one run without changing what is saved.

## Controls

| | Keyboard and mouse | Controller |
|---|---|---|
| Move | `W A S D`, `Space` up, `C` down | left stick, `A` up, `B` down |
| Boost | hold `Shift` | click `LS`; it lasts while the stick stays pushed |
| Look | mouse, or arrow keys | right stick |
| Left arm | hold `Q` or left mouse button | hold `LT` |
| Right arm | hold `E` or right mouse button | hold `RT` |
| Left arm tool | `Z` next; `1` Punch, `2` Drill, `3` Shoot | `LB` next, d-pad `←` previous |
| Right arm tool | `X` next; `8` Punch, `9` Drill, `0` Shoot | `RB` next, d-pad `→` previous |
| Identify what the reticle is on; again for the longer explanation. In chapter 2 it is also the scan pulse | `T` (or `F`) | `X` |
| Mucus Tether (chapter 2 upgrade): on tissue within 0.4 mm it attaches and reels in, on nothing it releases | `G` | click `RS`, or d-pad `↑` |
| Ask Dr. Marín for a hint (three levels per objective) | `H` | `Y` |
| Skip the current comms line | `Tab` | `View` |
| Pause, and resume | `Esc` | `Menu` |
| On the title screen: begin, route map, language, quit game | `↑ ↓` and `Enter`, or `M`, `Tab`, `Cmd+Q` | d-pad or left stick and `A`, or `Y`, `View` |
| In the pause menu: resume, relaunch from checkpoint, restart chapter, leave to title, quit game | `↑ ↓` and `Enter`, or `Esc`, `R`, `N`, `L`, `Cmd+Q` | d-pad or left stick and `A`; `B` resumes |
| Menus and cards: confirm, back | `Enter`, `Esc` | `A`, `B` |
| Switch language (English, Ukrainian) on the title screen or the pause screen | `Tab` | `View`, or d-pad `←` `→` |

The controller column uses Xbox names. On a DualShock 4 or DualSense the same positions are `✕ ○ □ △` for
`A B X Y`, `L1 R1 L2 R2` for `LB RB LT RT`, `L3 R3` for the stick clicks, `Create` (Share on a DualShock 4)
for `View` and `Options` for `Menu`, and the game's prompts use those names when such a controller is the
one in use. The triggers act as buttons, pressed at 40% of their travel and released at 25%. Keyboard, mouse
and controller are read together and their input is added, so the stick can fly while the mouse aims.
Mouse movement alone never changes which device the prompts are written for, since on a handheld the
gyroscope and trackpads arrive as mouse movement. `Cmd+F` has no controller equivalent; a controller quits
through the `Quit game` entry of the title and pause menus. The game pauses itself when its window loses
focus and when the controller in use disconnects during a chapter. Back on a briefing returns to the screen
it was opened from, the title or the route map.

After the chapter 1 upgrade, triggering both arms within 0.12 s lands them as one Sync Strike.

## Scope

A personal project, built for the author and published as-is. Chapters 3 to 11 are designed in
[DESIGN.md](docs/DESIGN.md): the patient, the route between organs and, for each chapter, the feature to
read, the objective, the challenge and the upgrade. The first hidden chapter's trigger (three cells in the
vein that should not be in circulating blood) is already in chapter 1.

## Limitations

- Apple Silicon and Metal only: there is no Intel, Windows or Linux build.
- The control layout is fixed: there is no remapping of keys or controller buttons, no sensitivity or
  invert-Y setting for the right stick, and no rumble.
- Controller hardware coverage is one device: an Xbox Wireless Controller over Bluetooth, on which
  discovery, family detection, every button, both sticks and both triggers were read through the game's own
  reader. No PlayStation controller has been attached, so its family detection and the hand-over of the
  Create and Share button are covered only by the automated tests, which drive a controller object that the
  GameController framework itself provides (see [ARCHITECTURE.md](docs/ARCHITECTURE.md)).
- The mouse-capture warp for a window on a second display follows Apple's documented coordinate spaces and
  is unit-tested as arithmetic, but has not been run on a machine with two displays.

## Development

```sh
zig build test                 # unit tests, translation checks, a scripted pilot that must finish both chapters, and the binary's exit codes
zig-out/bin/dentro --help      # the modes and options
zig-out/bin/dentro --selftest  # the same playthroughs, with a printed summary
zig-out/bin/dentro --shots DIR # offscreen GPU render of every screen and stage, one BMP each
zig-out/bin/dentro --lang uk --shots DIR   # the same in Ukrainian
zig-out/bin/dentro --prompts ps --lang uk --shots DIR   # with the prompts written for kbm, xbox or ps
zig-out/bin/dentro --inputtest # opens the window and drives it with synthetic key events
zig-out/bin/dentro --padtest   # opens the window and plays from the title screen with a synthetic controller
zig-out/bin/dentro --demo      # the scripted pilot flies chapter 1 in the window, with audio
zig-out/bin/dentro --chapter 2 --demo
zig-out/bin/dentro --demo --pad   # the same pilot, holding a controller instead of handing over its controls
```

The scripted modes run in English unless `--lang` says otherwise, so their output does not depend on the
machine; `--demo` follows the system like normal play. The tests fail on a string with no Ukrainian text, on
placeholders that differ between the two languages, on any character that has no glyph in the font
atlas, on an action with no controller binding, and on text shown to a controller player that names a key.
`--prompts kbm|xbox|ps` fixes the device the prompts are written for in normal play, `--demo`,
`--inputtest` and `--shots`; without it they follow the device last used.

The command line is checked before anything opens. An option that needs a value and has none, two
different modes, or an option given with a mode in which it would do nothing (`--pad` without `--demo`,
`--chapter` with `--selftest`) prints the reason and the usage and exits with status 2; `--help` and `-h`
print the usage and exit with 0. `--shots` creates its directory if needed and exits with 1 when the
directory cannot be made, a frame cannot be written or a chapter is not flown to its end, so a script can
rely on its status.

```text
Build Summary: 12/12 steps succeeded; 101/101 tests passed
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

Third-party files are distributed under their own licences. The fonts are compiled into the binary, and
their licence texts are copied into the app bundle under `Contents/Resources/licenses/`:

| | | |
|---|---|---|
| `res/fonts/NotoSans-ExtraCondensedMedium.ttf`, `NotoSans-ExtraCondensedSemiBold.ttf` | Noto Sans 2.015, [notofonts/latin-greek-cyrillic](https://github.com/notofonts/latin-greek-cyrillic) | [SIL Open Font License 1.1](res/fonts/OFL-NotoSans.txt) |
| `res/fonts/DejaVuSans.ttf` (arrows and symbols the text face lacks) | DejaVu Sans 2.37, [dejavu-fonts](https://github.com/dejavu-fonts/dejavu-fonts) | [Bitstream Vera and Arev licences, public-domain changes](res/fonts/LICENSE-DejaVu.txt) |
| `vendor/stb/stb_truetype.h` | stb_truetype 1.27, [nothings/stb](https://github.com/nothings/stb) | [MIT or public domain](vendor/stb/LICENSE) |
