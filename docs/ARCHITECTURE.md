# Architecture and build decisions

Recorded before implementation and kept current. Design intent (patient, route, chapters, tools, guide) is in
[DESIGN.md](DESIGN.md); this file covers how the program is built.

## Constraints that drove the choices

The target is one machine class: Apple Silicon, macOS 14 or later, Metal. Game and runtime code is Zig
(0.17). The workspace had no engine to reuse, but `~/projects/glance` already drives AppKit and Metal from
Zig through `objc_msgSend`, and that pattern carried over.

## Rendering stack

AppKit and Metal are called directly through the Objective-C runtime (`src/objc.zig`), with no Objective-C
or Swift source and no third-party dependency. The alternatives were a C library (sokol, raylib, SDL) or a
Zig wrapper package. Both would add a dependency and a build step for a renderer that needs about a dozen
Metal calls, and the direct route keeps `zig build` as the only requirement.

Shaders are one MSL file compiled at launch with `newLibraryWithSource:`. Offline compilation needs the Metal
toolchain component of Xcode, which is not guaranteed to be installed; runtime compilation takes a few
milliseconds and lets the bundled shader be edited without rebuilding. The binary embeds the same source as
a fallback when it runs outside a bundle.

A frame is two passes. The scene renders to an RGBA16F target with 4x MSAA, is resolved, and gets a mip
chain; the post pass reads that chain for bloom, applies exposure, ACES tone mapping, vignette, transit warp
and damage flashes, and draws the HUD in the same pass. There are no vertex descriptors: vertex and instance
data are pulled from buffers by `vertex_id` and `instance_id`, which keeps pipeline setup to a few lines.
Materials are a small integer id per instance switched in one fragment function (vessel wall, cell membrane,
metal, fibrin, biofilm, leaflet, clot, calcified, mucosa, crypt floor, hologram, unlit). The first-person arms are drawn after
the world in the front slice of the depth range with their own projection, so they never clip into tissue.

Text is a CoreText glyph atlas (two faces, 96 px, mip-mapped). Audio is an AudioQueue fed by a procedural
synthesiser; there are no sample files. The game thread sends events through a single-producer ring and
continuous parameters (drill load per arm, flow, heart rate) through atomics, and each arm's sounds are
panned to its side.

## Simulation

One world unit is one micrometre. The anatomy of a chapter is a set of analytic functions in one module:
`src/vein.zig` (centreline, wall radius, valve cusp surfaces, pulsed parabolic flow) and `src/gut.zig`
(villus lattice, fold profile, canopy flow, the travelling contraction ring). The mesh, the collision, the
flow that advects the drone, and the ray casts for the reticle and the weapons are all derived from those
functions, so what the player sees, hits and is carried by cannot drift apart.

`src/game.zig` holds the rules shared by every chapter: the drone, the two arms and their tools, the entity
table, damage, the guide's triggers. It has no rendering or platform imports and runs headless. Chapter 1's
script lives there as well, since it was written first; from chapter 2 on a chapter is a module
(`src/ch2.zig`) that owns its state, stage script, organisms and upgrade, and `game.zig` dispatches to it at
a fixed set of points (stage entry, movement and collision, focus, each tool's hit, entity update, grading).
New chapters follow the chapter 2 shape.

The guide (`src/guide.zig`) is state-driven: an atlas of topics with a short and a deep entry each, a
priority queue for spoken lines, stage-entry lines, reactions to player actions, and three hint levels per
stage.

## Verification

The simulation being headless makes four layers possible.

- `zig build test` runs unit tests for the anatomy models, the rules, the guide and the audio panning, plus a
  scripted pilot (`src/bot.zig`) that plays each chapter and must finish it with the chapter's mechanics
  actually used (simultaneous dual-arm time, Sync Strikes, contractions survived, tether pulls) above a
  floor.
- `dentro --shots <dir>` renders the menus and every stage offscreen through the real GPU pipeline and
  writes one image per stage.
- `dentro --inputtest` opens the window and posts synthetic `NSEvent` key events to the app's own queue, so
  the real input path is exercised without touching other applications.
- `dentro --demo` has the scripted pilot fly a chapter in the window with audio and reports frame rate.

`--chapter N` selects the chapter for `--demo` and `--shots`, and opens it directly in normal play.

Scripted and bot-driven modes never read or write the save file.

## Build and packaging

`zig build` produces `zig-out/bin/dentro` and assembles `zig-out/Dentro del cuerpo.app` (binary, Info.plist,
icon, shader source), then seals the bundle with an ad-hoc signature. The icon is rendered by the game
itself (`dentro --icon`) and checked in as `res/AppIcon.icns`. The save file is
`~/Library/Application Support/Dentro del cuerpo/save.txt`.

Quitting needs one piece of care: AppKit's `terminate:` calls `exit()` from inside the event pump, so the
cleanup that must precede exit (stopping the audio thread, re-associating the mouse) runs from
`applicationShouldTerminate:` rather than after the main loop.

## Source layout

| | |
|---|---|
| `src/vein.zig`, `src/gut.zig` | anatomy of chapters 1 and 2 as analytic functions: shape, flow, collision, ray casts |
| `src/game.zig` | shared rules: drone, arms and tools, entities, guide triggers; chapter 1's script |
| `src/ch2.zig` | chapter 2: state, stage script, organisms, tether |
| `src/guide.zig`, `src/campaign.zig` | the atlas and comms queue; the chapter table |
| `src/bot.zig` | scripted pilot used by the tests and `--demo` |
| `src/draw.zig`, `src/render.zig`, `src/gpu.zig`, `src/shaders/` | scene, arms and HUD; batching; Metal |
| `src/platform.zig`, `src/audio.zig`, `src/font.zig`, `src/objc.zig` | window and input, synthesiser, glyph atlas, runtime bridge |
