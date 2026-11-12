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
the longest form of it any player can be shown, across both languages and all three prompt devices (see
Input), so the simulation, and with it the scripted pilot's run, is identical whichever is in use.

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
`Tab` on the title and pause screens (`View` or the d-pad on a controller) moves to the next language and
writes the save file. Scripted modes
have no save file to write and default to English, so their output is the same on every machine. Layout
that depends on text measures it: panels and plates take their width from the string, and single-line
slots with a fixed width shrink the type until the string fits. Paragraphs wrap on spaces but never
directly before a dash. Text that types itself out (subtitles, the briefing) is laid out once at its full
length and revealed within that layout (`Renderer.paragraphRevealed`), so a word appears on the line it
will end on instead of starting on one line and jumping to the next when it outgrows it.

## Input

Keyboard and mouse events arrive through the AppKit event pump in `src/platform.zig` and are turned into
the game's actions by `gather` in `src/main.zig`. The pump records key events itself and never forwards
them to AppKit, which would beep at keys no view handles. A key-up is always recorded, whatever modifiers
are held, because a key that was recorded going down must be seen coming up: releasing an arrow key
between pressing Cmd+F and letting go of Cmd would otherwise leave the view turning until the key was
tapped again. A key-down under Cmd is first offered to the menu bar (`performKeyEquivalent:`), which is
what keeps Cmd+F and Cmd+Q working; if the menu takes it the game does not see the key, and its repeats
are dropped until the key comes up, and if the menu has no use for it the key is recorded like any other.
When the mouse is captured the cursor is warped to the centre of the window, and the warp is the one place
where two coordinate spaces meet: AppKit's window frame has its origin at the bottom left of the primary
display with y up, `CGWarpMouseCursorPosition` takes a point from the top left of the primary display with
y down, and both span all displays. The flip is therefore about the height of `NSScreen.screens[0]`, not of
`mainScreen`, which is the display of the key window and gives a wrong point as soon as the window is on a
second display of a different height (`platform.warpTarget`, unit-tested; not run on two displays).

A game controller takes a different route, laid out so that a second platform has one small thing to
supply. `src/pad.zig` defines `pad.State`: whether a
controller is attached, its family (Xbox, PlayStation or generic), two sticks, two analog triggers and a
set of sixteen buttons, all as the device reports them. The module imports nothing but the standard
library. A platform backend fills that struct once a frame into `Platform.pad` and does nothing else; the
dead zones, response curves, trigger thresholds, press edges and menu auto-repeat are all applied on the
neutral side, so they behave identically on every platform and are unit-tested without a device.

The macOS backend is the `Gamepad` struct in `src/platform.zig`, which reads the GameController framework
through the Objective-C runtime like the rest of the platform code. The framework supports Xbox,
DualShock 4 and DualSense controllers over USB and Bluetooth with no driver and presents each as an
extended gamepad. Nothing is registered with it. Each frame the backend asks for `GCController.current`,
falling back to the first entry of `controllers` that has an extended-gamepad profile, and reads every
element's value. Polling covers a controller that was on before launch, one switched on later and one
that goes away, without a notification that could be missed, and the framework's own bookkeeping runs on
the main run loop that the event pump already turns. The family comes from the class of the profile
(`GCXboxGamepad`, `GCDualShockGamepad`, `GCDualSenseGamepad`). Input counts only while the game's window
is key: `shouldMonitorBackgroundEvents` is switched off explicitly, and independently of that the backend
reports an attached but idle controller whenever the window is not key. On a PlayStation controller
macOS reserves the Create button for its screenshot gestures and delays the press until it has ruled a
gesture out, so when a controller is adopted the backend sets that button's preferred system-gesture
state to disabled. Rumble is not implemented.

`src/input.zig` turns `pad.State` into actions. `pad.Filter` first reduces the raw state to a sample:
sticks pass through a radial dead zone and a response curve (linear for thrust, squared for look, so
small deflections aim finely), triggers become buttons with hysteresis (pressed at 0.40, released at
0.25), and each button gets a pressed edge. A controller that is absent or whose window lost focus
yields an empty sample, and a button already held when it comes back is down but not pressed, which is
what prevents both stuck inputs and phantom presses. `input.Mapper` then applies the layout in one of two
contexts. While the drone is being flown the sticks thrust and look, the triggers work the arms and the
face buttons climb, descend, identify and ask for a hint; on every menu and card the same buttons
confirm, go back and move a selection. Three details follow from that sharing. A button that went down
in a menu does nothing in flight until it has been released, so the press that launched a chapter does
not also climb. The confirm button is ignored for half a second after flight stops, so a card that
appears while the player is tapping the climb button is not dismissed unread. And the keyboard's Esc is
split in two for a controller, a cancel that only backs out of menus and a pause that only pauses and
resumes, because the cancel button is also the one that descends. Stick look is a rate (3.2 rad/s yaw,
2.3 rad/s pitch at full deflection) multiplied by the frame time, so a turn takes the same time at any
frame rate. Both triggers reach the simulation in the frame they are pulled, so a Sync Strike has no
added latency. Boost is a click of the left stick that lasts while the stick stays pushed, since
holding a stick down while steering with it for several seconds is uncomfortable.

The keyboard's and the controller's output are merged every frame by `Out.merge`: held controls and look
deltas are added, one-shot actions are taken from either, so the devices can be mixed freely. Which
device the on-screen prompts are written for is decided by `input.Tracker`: a press on a device moves
the prompts to it at once, and a held control (a key kept down, a stick past its dead zone) does so only
while the other device is idle, so steering with a stick and tapping a key does not make the prompts
flicker. Mouse movement is deliberately not an input to that decision, because a handheld delivers its
gyroscope and trackpads as mouse movement while the player's hands are on the controller. Unplugging the
controller returns the prompts to the keyboard; losing focus does not. The tracker also reports, for one
frame, that the controller the prompts were following has gone, and the main loop pauses the game on that
report as it does when the window loses focus. Both go through `App.autoPause`, which applies the rule of
the pause key (`App.canPause`: a chapter is on screen and is not on its debrief), so an automatic pause
cannot open the pause menu anywhere the player could not have opened it. That matters on the debrief,
where the chapter is already recorded and the menu's relaunch entry would restart a finished run.

The layout itself is one table in `src/bindings.zig`: each `Action` has a keyboard label and a controller
control. Strings do not spell out controls. They refer to actions (`{@examine}`, `{@arm_left}`), and
`bindings.resolve` substitutes the label for the device in use, with Xbox names (`A`, `LT`, `View`,
`Menu`), PlayStation names (`✕`, `L2`, `Create`, `Options`) or key names. A controller of unknown family
gets Xbox names, since that is the layout such controllers copy. Where a sentence cannot be the same for
both kinds of device ("hold the key" against "hold the trigger"), the `Text` carries a second wording
for controllers. Tests in `src/l10n.zig` check that every reference names an action a controller has a
button for, that no text shown to a controller player names a key, and that every label has its glyphs
in the atlas.

A Windows backend has to produce the same `pad.State` from XInput and report whether the window has
focus; everything above the seam is shared. `gather` and `platform.Key` remain specific to macOS and are
the keyboard half of the same port.

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

The simulation being headless makes five layers possible.

- `zig build test` runs unit tests for the anatomy models, the rules, the guide, the audio panning, the text
  formatter, the translations and the controller layer, plus a scripted pilot (`src/bot.zig`) that plays
  each chapter and must finish it with the chapter's mechanics actually used (simultaneous dual-arm time,
  Sync Strikes, contractions survived, tether pulls) above a floor. The pilot plays each chapter twice:
  once handing its controls to the simulation, and once through `input.Puppet`, which holds a controller
  the way those controls require, and `input.Mapper`, which reads it back. The second run shows that a
  chapter can be finished with only what a controller can express: a turn rate with a ceiling, climb and
  descent as buttons, tools reached by stepping.
- `dentro --shots <dir>` renders offscreen through the real GPU pipeline and writes one image per screen:
  the title and its menu, the route map with each chapter selected, the briefing pages, every stage of
  both chapters, the upgrade, failure and debrief cards, the pause screen with and without the tether row,
  the language switch, and the longest line, hint and atlas entry in the subtitle box. The stages are
  photographed on a timer while the scripted pilot flies, and the pilot passes through some of them in less
  than the interval, so the run also keeps a copy of the application as it stood when each stage began.
  When a stage ends without a frame, the run goes back to that copy with the pilot held off, steps it
  until Dr. Marín's line for the stage is on screen, writes the frame and resumes from where it was; `App` being a plain value
  makes that a pair of struct copies, and coverage does not depend on a list of stages kept by hand. With
  `--lang uk` it does so in Ukrainian, and with `--prompts kbm|xbox|ps` with the prompts written for that
  device, which is how text fit is checked for each of the six combinations. The run creates its directory
  and exits with a non-zero status if the directory cannot be made, a frame cannot be written or a chapter
  is not completed.
- `dentro --inputtest` opens the window and posts synthetic `NSEvent` key events to the app's own queue, so
  the real input path is exercised without touching other applications. It includes the language key and
  reads the menu bar back to see that it followed, and it covers the keys under Cmd: an arrow key released
  while Cmd is held stops the turn, a key the menu bar has no shortcut for reaches the game with Cmd down,
  and Cmd+F reaches the Full Screen menu item exactly once without also being read as `F`. For that last
  check the item is pointed at a counter for a few frames, so the window does not change mode.
- `dentro --padtest` opens the window and plays from the title screen with a controller alone: the title
  menu, the route map, the briefing, flight in chapter 1 (both sticks, both triggers and a Sync Strike,
  tool stepping, climb, descent, boost, identify, hint, skip), the pause menu with its language and quit
  entries, a disconnection with a trigger held, after which the game must have paused itself and the arm
  must be at rest on reconnection, and the tether in chapter 2. It also checks which device the prompts follow, including
  that posted mouse-moved events do not take them from the controller. The controller is synthetic but
  not a stub. The GameController framework can create a controller object that belongs to no device and
  whose elements a program may set; the test writes its script onto such an object and `Platform.pump`
  reads it with the same code that reads a real device, so everything from the element values upward is
  the shipping path. What this cannot cover is the part below the element values: discovery through
  `GCController.current`, the profile class a real controller reports, and the system-gesture override
  on Create. Those have been run only with no controller attached.
- `dentro --demo` has the scripted pilot fly a chapter in the window with audio and reports frame rate.
  With `--pad` the pilot holds the same framework-made controller instead of handing its controls to the
  game.

The command line is parsed by `src/cli.zig`, apart from acting on it, so that the rules are unit-tested:
an option that needs a value is refused without one (a following argument that begins with a dash is not a
value), two different modes are refused, and so is an option combined with a mode in which it would be
ignored, since silence there reads as success. `--chapter N` selects the chapter for `--demo` and `--shots`
and opens it directly in normal play; `--lang` applies to every mode that shows text, which excludes
`--selftest` and `--icon`; `--prompts` applies wherever prompts are drawn except `--padtest`, which checks
the device they follow; `--pad` belongs to `--demo`. A refusal prints its reason and the usage and exits
with 2, and `--help` exits with 0. `zig build test` runs the binary with a handful of such lines and
checks the exit status and the message, because the status is decided in `main`, outside what a unit test
of the parser reaches. Cocoa's own `-AppleLanguages "(uk)"` argument is passed through, which makes the
system-preference path testable without changing system settings.

Scripted and bot-driven modes never read or write the save file.

## Build and packaging

`zig build` produces `zig-out/bin/dentro` and assembles `zig-out/Dentro del cuerpo.app` (binary, Info.plist,
icon, shader source), then seals the bundle with an ad-hoc signature. The bundle is signed where it is
installed: the path given to `codesign` is resolved against the install prefix when the step runs, so
`zig build --prefix DIR` seals `DIR/Dentro del cuerpo.app`, and a `codesign --verify --strict` step after
it fails the build if the seal does not match the bundle's contents. The fonts are inside the binary, so
the bundle carries no font files, only their licence texts under `Resources/licenses/`. `Info.plist` declares both localisations (`CFBundleLocalizations`), the
key macOS reads to offer an application its own language setting, and that it supports extended gamepads
(`GCSupportedGameControllers`, `GCSupportsControllerUserInteraction`), which is how macOS knows the game
can be driven from a controller. The icon is rendered by the game
itself (`dentro --icon`) and checked in as `res/AppIcon.icns`.

The save file is `~/Library/Application Support/Dentro del cuerpo/save.txt`, one line of space-separated
fields. Reading it is total: `Save.parse` accepts any bytes, clamps each number to the range its field can
hold and reads a field it cannot make sense of as zero or as no grade, so a damaged or hand-edited file
yields a valid save, or the default one, and never a trap (a float outside the integer range used to be converted unchecked, which panics in a safe
build and is undefined in a fast one). A fuzz-style test feeds it random bytes, mutated real saves and
extreme numerals. Writing creates the directory and any missing parents, writes the bytes to a temporary
file beside the save, flushes it to disk and renames it over the save, so a crash leaves the old file or
the new one. A failed save is reported on stderr once per run of failures instead of once per attempt, and
play continues. For each chapter the file keeps the best grade flown and, among runs of equal grade, the
latest (`Save.supersedes`); the two chapters used to differ on equal grades.

Quitting needs one piece of care: AppKit's `terminate:` calls `exit()` from inside the event pump, so the
cleanup that must precede exit (stopping the audio thread, re-associating the mouse) runs from
`applicationShouldTerminate:` rather than after the main loop. The `Quit game` entry of the title and
pause menus, which is how a controller quits, sends the same `terminate:` and so takes the same path as
Cmd+Q.

## Source layout

| | |
|---|---|
| `src/vein.zig`, `src/gut.zig` | anatomy of chapters 1 and 2 as analytic functions: shape, flow, collision, ray casts |
| `src/game.zig` | shared rules: drone, arms and tools, entities, guide triggers; chapter 1's script |
| `src/ch2.zig` | chapter 2: state, stage script, organisms, tether |
| `src/guide.zig`, `src/campaign.zig` | the atlas and comms queue; the chapter table (both bilingual) |
| `src/i18n.zig`, `src/strings.zig`, `src/l10n.zig` | languages, templates and plurals; the string catalogue; the tests that walk all text |
| `src/bot.zig` | scripted pilot used by the tests and `--demo` |
| `src/main.zig`, `src/cli.zig`, `src/app.zig` | entry point and the modes; command-line parsing; screens, menus and the save file |
| `src/draw.zig`, `src/render.zig`, `src/gpu.zig`, `src/shaders/` | scene, arms and HUD; batching; Metal |
| `src/pad.zig`, `src/bindings.zig`, `src/input.zig` | controller state and its shaping; the layout and the names of controls per device; controller input as actions, and the device the prompts follow |
| `src/platform.zig`, `src/audio.zig`, `src/objc.zig` | window, keyboard, mouse, game controller and system language; synthesiser; runtime bridge |
| `src/font.zig`, `src/utf8.zig`, `src/stb_truetype.c`, `vendor/stb/`, `res/fonts/` | glyph atlas and UTF-8 decoding; the rasteriser and the fonts it reads |
