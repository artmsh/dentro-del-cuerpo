# Architecture and build decisions

Recorded before implementation and kept current. Design intent (patient, route, chapters, tools, guide) is in
[DESIGN.md](DESIGN.md); this file covers how the program is built.

## Constraints that drove the choices

The target is one machine class: Apple Silicon, macOS 14 or later, Metal. Game and runtime code is Zig
(0.17). The workspace had no engine to reuse, but `~/projects/glance` already drives AppKit and Metal from
Zig through `objc_msgSend`, and that pattern carried over.

## Rendering stack

AppKit and Metal are called directly through the Objective-C runtime (`src/objc.zig`), with no Objective-C
or Swift source and no dependency to fetch. The alternatives were a C library (sokol, raylib, SDL) or a
Zig wrapper package. Both would add a dependency and a build step for a renderer that needs about a dozen
Metal calls, and the direct route keeps `zig build` as the only requirement. The one piece of third-party
code is `vendor/stb/stb_truetype.h`, checked in and compiled by the same `zig build` (see Text below).

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

Audio is an AudioQueue fed by a procedural synthesiser; there are no sample files. The game thread sends
events through a single-producer ring and continuous parameters (drill load per arm, flow, heart rate)
through atomics, and each arm's sounds are panned to its side.

## Text

Text is drawn from a glyph atlas that `src/font.zig` builds at startup: one 4096×2048 R8 texture,
mip-mapped, holding two faces at 96 px per em. The module has no platform imports. It rasterises fonts that
are compiled into the binary with `@embedFile`, using stb_truetype (one C translation unit,
`src/stb_truetype.c`, built by `zig build`), so the same code and the same glyphs serve any platform the
game is ported to. An earlier version asked CoreText for Avenir Next Condensed; that font has no Cyrillic
and exists only on Apple systems.

The text faces are Noto Sans ExtraCondensed Medium and SemiBold, chosen because their widths and cap height
are within about 2% of the Avenir faces the layout was drawn for, and because their Cyrillic is designed
alongside the Latin. Two alternatives were set aside for reasons that are easy to miss. Sofia Sans Condensed
maps Cyrillic code points to Bulgarian letterforms by default and reaches the forms Ukrainian readers
expect only through the OpenType `locl` feature, which stb_truetype does not apply. Roboto Condensed and
Oswald ship as variable fonts, from which stb_truetype can only read the default instance. Arrows and
geometric symbols that Noto Sans lacks (→ ↑ ● ▲ ◆ ✓ and the like) come from DejaVu Sans, also bundled; a
system font is never consulted. Licences are listed in the README.

The atlas holds a fixed character set declared in `font.zig`: ASCII, Latin-1, the Cyrillic block as far as
Ukrainian needs it, and the punctuation and symbols the HUD uses. Glyphs are found by binary search over
the sorted code points, and strings are decoded as UTF-8 (`src/utf8.zig`). A test walks every string the
game can show, in both languages, and fails if any code point is absent from either face, so a new string
cannot introduce a missing glyph unnoticed. The layout baseline is a constant one em below the top of the
line rather than the font's own ascent, which keeps every text position where it was under the old font.

## Localisation

The game has two languages, English and Ukrainian (`Lang` in `src/i18n.zig`), and English is the source
text. Every piece of text the player sees is a `Text` value, a pair of strings with one field per language
and no defaults, so leaving out a translation is a compile error. Short interface strings and Dr. Marín's
lines live in one catalogue, `src/strings.zig`; atlas entries and the chapter table are bilingual in
`src/guide.zig` and `src/campaign.zig`, next to the data they describe. The simulation passes `Text`
values around and never chooses a language: the guide queues a `Text`, and `src/draw.zig` picks the string
for the current language when it draws. This keeps `game.zig` free of rendering and platform imports, and
it means a language switch applies to the line already on screen. A line's display time is computed from
the longer of its two translations, so the simulation, and with it the scripted pilot's run, is identical
in both languages.

Strings with values in them are templates: `{0}` inserts an argument and `{0|one|few|many}` selects a
plural form by the argument's value, with two forms in English and three in Ukrainian (1 скупчення,
2 скупчення, 5 скупчень). `i18n.format` checks at compile time that the template is well formed in both
languages, that both use the same arguments, and that the call supplies them. Numbers take the language's
decimal separator. `src/l10n.zig` holds the tests that walk the whole catalogue: every string has
Ukrainian text, no Ukrainian string is a copy of the English apart from a short list of names that are the
same everywhere, Ukrainian typography is respected (« », —, ’, no straight quotes, no Latin letters inside
Cyrillic words), and every character has a glyph.

The language is chosen in this order: `--lang en|uk` on the command line; the language the player picked
in the game, stored as an optional last field of the save file; the first supported language in the
system's preference list, which the platform layer reports through `platform.preferredLanguages`; English.
`Tab` on the title and pause screens moves to the next language and writes the save file. Scripted modes
have no save file to write and default to English, so their output is the same on every machine. Layout
that depends on text measures it: panels and plates take their width from the string, and single-line
slots with a fixed width shrink the type until the string fits. Paragraphs wrap on spaces but never
directly before a dash.

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

- `zig build test` runs unit tests for the anatomy models, the rules, the guide, the audio panning, the text
  formatter and the translations, plus a scripted pilot (`src/bot.zig`) that plays each chapter and must
  finish it with the chapter's mechanics actually used (simultaneous dual-arm time, Sync Strikes,
  contractions survived, tether pulls) above a floor.
- `dentro --shots <dir>` renders offscreen through the real GPU pipeline and writes one image per screen:
  the title, the route map with each chapter selected, the briefing pages, every stage of both chapters,
  the upgrade, failure and debrief cards, the pause screen, the language switch, and the longest line,
  hint and atlas entry in the subtitle box. With `--lang uk` it does so in Ukrainian, which is how text
  fit is checked.
- `dentro --inputtest` opens the window and posts synthetic `NSEvent` key events to the app's own queue, so
  the real input path is exercised without touching other applications. It includes the language key and
  reads the menu bar back to see that it followed.
- `dentro --demo` has the scripted pilot fly a chapter in the window with audio and reports frame rate.

`--chapter N` selects the chapter for `--demo` and `--shots`, and opens it directly in normal play.
`--lang` applies to every mode. Cocoa's own `-AppleLanguages "(uk)"` argument is passed through, which
makes the system-preference path testable without changing system settings.

Scripted and bot-driven modes never read or write the save file.

## Build and packaging

`zig build` produces `zig-out/bin/dentro` and assembles `zig-out/Dentro del cuerpo.app` (binary, Info.plist,
icon, shader source), then seals the bundle with an ad-hoc signature. The fonts are inside the binary, so
the bundle carries no font files, only their licence texts under `Resources/licenses/`. `Info.plist` declares both localisations (`CFBundleLocalizations`), the
key macOS reads to offer an application its own language setting. The icon is rendered by the game
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
| `src/guide.zig`, `src/campaign.zig` | the atlas and comms queue; the chapter table (both bilingual) |
| `src/i18n.zig`, `src/strings.zig`, `src/l10n.zig` | languages, templates and plurals; the string catalogue; the tests that walk all text |
| `src/bot.zig` | scripted pilot used by the tests and `--demo` |
| `src/draw.zig`, `src/render.zig`, `src/gpu.zig`, `src/shaders/` | scene, arms and HUD; batching; Metal |
| `src/platform.zig`, `src/audio.zig`, `src/objc.zig` | window, input and system language; synthesiser; runtime bridge |
| `src/font.zig`, `src/utf8.zig`, `src/stb_truetype.c`, `vendor/stb/`, `res/fonts/` | glyph atlas and UTF-8 decoding; the rasteriser and the fonts it reads |
