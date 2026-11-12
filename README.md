# Dentro del cuerpo

*Inside the Body.* A first-person 3D game for macOS in which a doctor pilots a cell-sized drone through a
living patient: in through a vein in the right leg, organ by organ to the brain, treating what it finds on
the way. Written in Zig over AppKit and Metal, with no other dependencies.

**Stage:** alpha. Chapters 1 and 2 of 11 are playable (about five minutes each); the full campaign is
designed and mapped. **Target:** personal project.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Zig 0.17 to build

## Build and launch

```sh
zig build -Doptimize=ReleaseFast          # builds zig-out/Dentro del cuerpo.app (signed ad hoc)
open "zig-out/Dentro del cuerpo.app"      # or double-click it in Finder
```

`zig build run -- --fullscreen` runs the bare binary. Cmd+F toggles full screen, Cmd+Q quits. Chapter 2
unlocks on the route map when chapter 1 is finished; `--chapter 2` opens it directly.

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

The arms are independent: each has its own key, tool, HUD panel, half of the reticle, colour (left cyan,
right amber) and stereo side. A drill stays locked in its cut while its key is held, so the pilot can look
away and work the other arm on something else. After the chapter's upgrade, triggering both arms within
0.12 s lands them as one Sync Strike.

## What is playable

**Chapter 1, Vein** is complete: injection through the cannula, flight in pulsed parabolic flow, two venous
valves to read and time, the guide's identify and hint system, the treatment of a septic microthrombus
pinning a valve cusp (biofilm colonies that only die when one arm drills them open while the other fires
into the breach, fibrin cables to cut, emboli to dissolve before they escape to the lungs), the Sync Servo
upgrade, a calcified obstruction that needs it, a debrief with a grade, and retry from checkpoints after
losing the drone or the patient.

**Chapter 2, Intestines** is complete: arrival among the villi of the proximal jejunum, a chyme stream that
is fast above the villus tips and still between them, peristaltic contractions that close the lumen and have
to be waited out below the tips, a scan that tells rotavirus-infected cells and loose virus from the
commensal bacteria that must be spared, treatment by punching an infected cell out whole and lysing it with
the other arm before it bursts, a viroplasm dome that needs drill and shot together, the Mucus Tether
upgrade, a stretch of blunted villi that can only be crossed on the tether, and its own debrief.

Chapters 3 to 11 and the two hidden chapters are designed in [docs/DESIGN.md](docs/DESIGN.md): the patient,
the anatomical route with the compartment for every transition, and for each chapter the feature to read,
the objective, the challenge and the upgrade. They appear on the in-game route map and are not yet playable.
The first hidden chapter's trigger (three cells in the vein that should not be in circulating blood) is
already in chapter 1.

## Checks

```sh
zig build test                 # unit tests and a scripted pilot that must finish both chapters
zig-out/bin/dentro --selftest  # the same playthroughs, with a printed summary
zig-out/bin/dentro --shots DIR # offscreen GPU render of the menus and every stage, one BMP each
zig-out/bin/dentro --inputtest # opens the window and drives it with synthetic key events
zig-out/bin/dentro --demo      # the scripted pilot flies chapter 1 in the window, with audio
zig-out/bin/dentro --chapter 2 --demo
```

## Layout

| | |
|---|---|
| `src/vein.zig`, `src/gut.zig` | anatomy of chapters 1 and 2 as analytic functions: shape, flow, collision, ray casts |
| `src/game.zig` | shared rules: drone, arms and tools, entities, guide triggers; chapter 1's script |
| `src/ch2.zig` | chapter 2: state, stage script, organisms, tether |
| `src/guide.zig`, `src/campaign.zig` | the atlas and comms queue; the chapter table |
| `src/bot.zig` | scripted pilot used by the tests and `--demo` |
| `src/draw.zig`, `src/render.zig`, `src/gpu.zig`, `src/shaders/` | scene, arms and HUD; batching; Metal |
| `src/platform.zig`, `src/audio.zig`, `src/font.zig`, `src/objc.zig` | window and input, synthesiser, glyph atlas, runtime bridge |
| `docs/` | [design](docs/DESIGN.md) and [architecture](docs/ARCHITECTURE.md) |
