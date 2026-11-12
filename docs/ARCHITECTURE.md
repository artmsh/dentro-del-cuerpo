# Architecture and build decisions

Recorded before implementation and kept current. Design intent (patient, route, chapters, tools, guide) is in
[DESIGN.md](DESIGN.md); this file covers how the program is built.

## Constraints that drove the choices

There are two targets: Apple Silicon Macs with macOS 14 or later, drawn with Metal, and x64 Windows 10
and 11, drawn with Direct3D 11. Game and runtime code is Zig (0.17). The game was written for the Mac
first. The workspace had no engine to reuse, but `~/projects/glance` already drives AppKit and Metal from
Zig through `objc_msgSend`, and that pattern carried over; the Windows version follows the same idea with
Win32 and COM.

## Platform seams

Everything that touches an operating system sits behind four interfaces, and nothing else in the program
imports a system API or asks which system it is on. Each interface is a neutral file that holds the types
both sides share and selects an implementation at compile time with a `switch` on the target, so the
choice is made in one place per seam and the shared code contains no platform conditionals.

| Seam | Neutral file | macOS | Windows |
|---|---|---|---|
| Window, keys, mouse, controller, clock, system language | `src/platform.zig` | `platform/macos.zig` (AppKit, GameController) | `platform/windows.zig` (Win32, Raw Input, XInput) |
| Drawing | `src/gpu.zig` | `gpu/metal.zig` | `gpu/d3d11.zig` |
| Sound output | `src/audio.zig` (the synthesiser) | `audio/audioqueue.zig` | `audio/wasapi.zig` |
| Files, environment, save folder | `src/util.zig` | `os/posix_files.zig` | `os/windows_files.zig` |

`platform.Key` names keys by physical position, after the legend on a US keyboard, and each backend maps
its hardware codes to it in `platform/keymap.zig`: macOS virtual key codes, which are positional already,
and Windows scan codes, which are positional where Windows' virtual keys follow the layout. `W A S D` is
therefore the same cluster of keys on a QWERTY, AZERTY or Ukrainian layout on both systems. The GPU seam
is a struct with a fixed set of methods (`init`, `attach`, `resize`, `uploadMeshes`, `uploadFont`,
`submit`, `readback`) and four CPU-side arrays the renderer fills each frame; `render.zig` describes a
frame as batches and counts and does not know which API draws it. The audio seam is a pull: the output
calls the synthesiser for interleaved float stereo at 48 kHz on its own thread. Images are encoded by
`src/image.zig` with no system API (BMP for `--shots`, PNG and ICO for `--icon`), so the capture and icon
tools are the same code everywhere.

The bindings to both systems are written by hand and need nothing installed. `platform/objc.zig` calls the
Objective-C runtime; `platform/win32.zig` and `gpu/d3d11_api.zig` declare the Win32 functions, structures
and COM interfaces the game calls, each interface as a struct holding a pointer to a table of function
pointers in the order of the SDK header. A table lists every slot, with the unused ones as placeholders,
and compile-time checks pin each used method to its slot number and each structure to its size, so a
mistyped table fails the build on any machine, the Mac included, where those files are compiled for their
checks though never called. The import libraries for the Windows DLLs ship with Zig, which is what lets
`zig build -Dtarget=x86_64-windows-gnu` produce the Windows version on a Mac.

## Rendering stack

On macOS, AppKit and Metal are called directly through the Objective-C runtime, with no Objective-C or
Swift source and no dependency to fetch. The alternatives were a C library (sokol, raylib, SDL) or a Zig
wrapper package. Both would add a dependency and a build step for a renderer that needs about a dozen
Metal calls, and the direct route keeps `zig build` as the only requirement. The same reasoning chose
Direct3D 11 called through its COM interfaces on Windows: it is present on every Windows 10 and 11 machine,
its model of render targets, shader stages and buffers is close enough to Metal's that the two backends
are the same sequence of steps, and it has a software implementation (WARP) for machines and CI runners
with no graphics card. The one piece of third-party code is `vendor/stb/stb_truetype.h`, checked in and
compiled by the same `zig build` (see Text below).

Shaders are one file per backend, `src/shaders/shaders.metal` and `src/shaders/shaders.hlsl`, compiled at
launch: by `newLibraryWithSource:` on macOS and by `D3DCompile` from `d3dcompiler_47.dll`, a part of
Windows, on Windows. Offline compilation would need the Metal toolchain component of Xcode or the Windows
SDK's `fxc`, neither of which is guaranteed to be installed, and runtime compilation lets the shader file
shipped beside the program be edited without rebuilding. The binary embeds the same source as a fallback
when the file is not there.

The HLSL file is a port of the Metal one by hand, in the same order with the same function names, so that
the two can be read side by side and changed together. Nothing but discipline would otherwise keep them
equal, so `src/gpu/shader_parity.zig` tests it: both files must declare the same functions in the same
order, and the functions that hold the look of the game (the noise helpers, the whole scene fragment
function with every material, the particle and post-processing fragment functions) must be the same
text line for line once the Metal spelling is rewritten in HLSL's (`mix` to `lerp`, `fract` to `frac`,
`in.` to `IN.`, `sample` to `SampleLevel`). A change to the lighting made in one file and not the other
fails `zig build test` on every platform. The vertex functions are exempt because they are where the two
APIs differ. The differences that had to be handled are these. Metal's `vertex_id` and `instance_id`
include the draw call's base vertex and base instance, and Direct3D's `SV_VertexID` and `SV_InstanceID` do
not, so the Direct3D backend issues every draw from zero and passes the two bases in a small constant
buffer that the vertex shader adds. Both APIs use a clip-space depth of 0 to 1 and put a texture's origin
at the top left, so no axis is flipped. The game's matrices are column-major and multiply column vectors,
which is HLSL's default packing with `mul(M, v)`. HLSL refuses an implicit mip level inside a loop or a
branch, so the post pass names level 0 where Metal leaves it to the sampler, and the HUD samples its glyph
before the branch that decides whether to use it. The back buffer is BGRA8 without an sRGB view on both
systems and the shader applies the gamma itself.

The patterns that look random are computed in integers in both files. The Voronoi cells of the vessel
wall and the gut epithelium, the lattice behind the value noise of every mottled surface, and the film
grain each need a hash: a number that looks random and is the same whenever it is asked for the same cell,
lattice point or pixel. The usual shader idiom takes the fraction of a sine, or of a product of fractions,
multiplied by a large constant, and the first version of both files used it. Such a hash turns a
difference in the last bit of its argument into a different result, and graphics APIs do not fix the last
bit of floating-point work: Direct3D specifies `sin` only between -100π and 100π, leaves it to the driver
whether a multiplication and an addition are fused into one rounding, and compiles `fmod` into a division
and a multiplication whose remainder of two whole numbers is not always whole. On WARP this showed as film
grain in diagonal stripes and as cells laid out differently from the Mac's. On an NVIDIA card it showed as
a fault: the driver rounded the argument of the cell hash differently at the three places where `voronoi`
asks for it, so a cell's border was measured against a displaced copy of the cell's own centre, the layout
was uneven and whole cells were drawn dark. An interim version reproduced Metal's rounding in the HLSL file
with a sine reduced in integers and a fused multiply-add assembled from error-free additions, which made
WARP agree with the Mac and did not survive that driver. The hashes are therefore the PCG hashes of
Jarzynski and Olano ("Hash Functions for GPU Rendering", 2020) applied to the whole-number coordinates as
32-bit integers, and the column of a cell on a pattern that closes around a tube is wrapped by an integer
remainder. Integer arithmetic has one answer on every GPU, so a cell has the same hash wherever it is asked
for and every machine draws the same cells, the same mottling and, for a given frame time, the same grain.
What remains in floating point is smooth (the interpolation between lattice values, the distances inside a
cell, the sines that move a surface), and there a different last bit moves a colour by less than can be
seen. Frames from two GPUs are consequently alike without being equal byte for byte, and nothing in CI
assumes they are. The parity test refuses a hash that contains a sine, a fraction, a remainder or a dot
product, and carries transcriptions of both hashes whose output it checks for uniformity and for the
absence of any relation between neighbouring cells, pixels and frames, which in the grain would be visible
as stripes.

The Direct3D device can be taken away while the game runs (a driver update, a remote-desktop session, a
laptop switching graphics cards). The backend keeps the shader source, the mesh data and the font atlas on
the CPU side, and when a present reports the device removed it rebuilds the device and everything on it
and carries on with the next frame. Setting `DENTRO_FORCE_DEVICE_LOSS=<n>` makes it do so before the n-th
frame, which CI uses to check that a rebuilt renderer draws exactly the frames an undisturbed one does.

A frame is two passes. The scene renders to an RGBA16F target with 4x MSAA, is resolved, and gets a mip
chain; the post pass reads that chain for bloom, applies exposure, ACES tone mapping, vignette, transit warp
and damage flashes, and draws the HUD in the same pass. There are no vertex descriptors: vertex and instance
data are pulled from buffers by `vertex_id` and `instance_id`, which keeps pipeline setup to a few lines.
Materials are a small integer id per instance switched in one fragment function (vessel wall, cell membrane,
metal, fibrin, biofilm, leaflet, clot, calcified, mucosa, crypt floor, hologram, unlit). The first-person arms are drawn after
the world in the front slice of the depth range with their own projection, so they never clip into tissue.

Audio is a procedural synthesiser; there are no sample files. The game thread sends events through a
single-producer ring and continuous parameters (drill load per arm, flow, heart rate) through atomics, and
each arm's sounds are panned to its side. The system output pulls from it: an AudioQueue on macOS, and on
Windows a WASAPI shared-mode stream on the default playback device, opened as 48 kHz float stereo (Windows
converts to the device's own format) and refilled by a thread that the device wakes whenever the stream
has room. A Windows machine may have no playback device at all, and the default device can change while
the game runs, so neither is treated as an error: with no device the thread keeps the synthesiser's clock
running into nothing and looks again every few seconds, and once a second it compares the stream's device
with the current default and reopens on the new one.

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

Keyboard and mouse events arrive through the platform backend's event pump (AppKit's on macOS, the Win32
message queue on Windows) as `platform.Input`, and are turned into the game's actions by `gather` in
`src/main.zig`. Both pumps keep one rule: a key that was recorded going down must be seen coming up,
whatever modifier is held at the time, and a key pressed with the system's shortcut modifier is offered to
the window before the game sees it. The second half is what `platform.Shortcut` describes (Cmd with `F`
and `Q` on macOS, Alt with `Enter` and `F4` on Windows), so that the input test can press the right keys on
either system. The same description is the only source of these shortcuts' names on screen. The title and
pause menus print the quit shortcut beside their Quit entry and the pause screen lists the full-screen
one, and the first Windows build printed `Cmd+Q` there because the name was a string in the catalogue. The
catalogue now holds neither: `main.zig` hands `platform.quit_keys` and `platform.fullscreen_keys` to the
app as `bindings.WindowKeys`, a test in `src/l10n.zig` fails if any text of the game spells a modifier
shortcut, each backend has a test of the names it supplies, and the input test checks in the running
window that the menus name this system's shortcut.

On macOS the pump records key events itself and never forwards them to AppKit, which would beep at keys no
view handles and which discards a key-up that arrives while Cmd is held: releasing an arrow key between
pressing Cmd+F and letting go of Cmd would otherwise leave the view turning until the key was tapped again.
A key-down under Cmd is first offered to the menu bar (`performKeyEquivalent:`), which is what keeps Cmd+F
and Cmd+Q working; if the menu takes it the game does not see the key, and its repeats are dropped until
the key comes up, and if the menu has no use for it the key is recorded like any other. On Windows the same
rule takes a different shape because the system reports keys differently: a key pressed or released while
Alt is held arrives as `WM_SYSKEYDOWN` or `WM_SYSKEYUP` instead of the plain messages, and the window
procedure sends all four to one handler, which takes Alt+Enter, F11 and Alt+F4 for the window and records
everything else. The releases Windows never delivers are the ones that happen while another window has the
focus or while a modal loop of the system's is running (the system menu, a drag of the frame), so losing
the focus, leaving a menu and ending a move or resize each release every key.

When the mouse is captured on macOS the cursor is warped to the centre of the window, and the warp is the
one place where two coordinate spaces meet: AppKit's window frame has its origin at the bottom left of the
primary display with y up, `CGWarpMouseCursorPosition` takes a point from the top left of the primary
display with y down, and both span all displays. The flip is therefore about the height of
`NSScreen.screens[0]`, not of `mainScreen`, which is the display of the key window and gives a wrong point
as soon as the window is on a second display of a different height (`warpTarget` in
`src/platform/macos.zig`, unit-tested; not run on two displays).

A game controller takes a different route, laid out so that each platform has one small thing to
supply. `src/pad.zig` defines `pad.State`: whether a
controller is attached, its family (Xbox, PlayStation or generic), two sticks, two analog triggers and a
set of sixteen buttons, all as the device reports them. The module imports nothing but the standard
library. A platform backend fills that struct once a frame into `Platform.pad` and does nothing else; the
dead zones, response curves, trigger thresholds, press edges and menu auto-repeat are all applied on the
neutral side, so they behave identically on every platform and are unit-tested without a device.

The macOS backend is the `Gamepad` struct in `src/platform/macos.zig`, which reads the GameController framework
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

The Windows backend fills the same `pad.State` from two sources. XInput (`platform/xinput.zig`) covers
Xbox controllers and everything that imitates one; its DLL is loaded at run time, trying `xinput1_4.dll`,
then `xinput9_1_0.dll`, then `xinput1_3.dll`, so a machine without it still starts the game. Connected
slots are read every frame. Asking about an empty slot costs a device enumeration, so empty slots are
probed at most one per frame, each after a delay that doubles from a quarter of a second to two seconds,
which bounds both the cost of having no controller and the time a newly plugged one takes to appear.
XInput does not say what kind of controller it is talking to, so the family is always Xbox. Sony's
controllers do not speak XInput, and they are read from their HID reports instead: the window registers
for Raw Input from game pads, identifies a device by vendor and product id (054C with the DualShock 4 and
DualSense ids), and `platform/pshid.zig` parses the USB and Bluetooth report layouts into a `pad.State`
with the PlayStation family. The parser is a pure function with tests for each layout, written from the
published descriptions of those reports; it has not been run against a physical controller.

A controller can be visible both ways at once, because Steam Input and tools such as DS4Windows create an
XInput controller that mirrors a Sony one, and a press would then arrive twice. Steam says which devices it
has taken over in `SDL_GAMECONTROLLER_IGNORE_DEVICES`, and the backend leaves those alone. For the other
tools `platform/padsel.zig` chooses: the controller touched last is the current one, as on macOS; XInput
wins when both kinds are in use in the same frame; and once that has been seen the directly read
controllers stand down until one of them has been used for a second with every XInput controller idle,
which a mirror cannot do. Its tests drive it frame by frame, including a mirrored controller whose two
copies arrive a frame apart in either order.

On Windows the mouse is read through Raw Input as well, which reports the device's movement without
pointer acceleration and does not stop at the edge of the screen. While the game holds the mouse the
cursor is hidden and confined to the window. Keys arrive as window messages and are identified by scan
code. Windows' default handling of `Alt` and `F10` puts a window into menu mode, which would freeze the
game on a stray key press, so the window keeps those keys from it: key messages are not translated into
characters, and `Alt+Enter`, `F11`, `Alt+F4` and, outside flight, `Alt+Space` for the system menu are
recognised by the window procedure itself.

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
- `dentro --inputtest` opens the window and posts synthetic key events to the app's own queue (`NSEvent`s
  on macOS, key messages carrying scan codes on Windows), so the real input path is exercised without
  touching other applications. It includes the language key and reads the menu back (the menu bar on
  macOS, the window's system menu on Windows) to see that it followed, and it covers the keys under the
  shortcut modifier: an arrow key released while the modifier is held stops the turn, a key the window has
  no shortcut for reaches the game with the modifier down, and the full-screen shortcut (Cmd+F, Alt+Enter)
  reaches the full-screen command exactly once without also being read as a key of the game's, as the
  quit shortcut (Cmd+Q, Alt+F4) reaches the quit command. For those checks each command is pointed at a
  counter for a few frames, so the window neither changes mode nor closes.
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
  on Create. Those have been run only with no controller attached. XInput offers no way to create a
  controller, so on Windows the test writes an XInput report (`XINPUT_GAMEPAD`) and the pump reads it
  with `xinput.toState`, the function that reads a real controller's report; the DLL call, the slot
  polling and the Raw Input path are below that and are covered by unit tests of their logic only.
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
with 2, and `--help` exits with 0. `--software` asks the GPU backend for the system's software rasteriser
and applies to every mode that draws; Direct3D has one and Metal does not, so on macOS it changes nothing.
`zig build test` runs the binary with a handful of such lines and checks the exit status and the message,
because the status is decided in `main`, outside what a unit test of the parser reaches. The checks run
against the executable for the host on either system, the Windows GUI executable included, since a GUI
program still writes to the pipes it is started with; the one line that differs is the directory `--shots`
must fail to create, which is a path under the null device in each system's spelling. Cocoa's own `-AppleLanguages "(uk)"` argument is passed through, which makes the
system-preference path testable without changing system settings.

Scripted and bot-driven modes never read or write the save file.

CI runs all of this on both systems for every push (`.github/workflows/ci.yml`). The Windows job runs on a
GitHub-hosted Windows Server machine, which has a desktop session but no graphics card, no sound device
and no controller. It runs `zig build test` natively, the release executable's `--selftest`, `--shots` in
both languages through WARP, the same render with a forced device loss, and `--inputtest` and `--padtest`
in a real window, and it checks the packaged executable's subsystem, resources and imported DLLs with
`.github/scripts/check-windows-exe.py`. A third job compares the two systems' `--selftest` output line by
line, since the simulation is meant to play out identically on both, and a release is published only when
all three have passed. Each job checks that its zip holds the game's two licence files. The release job
can be run again for the same commit: a re-run has the same run number and therefore the same version, so
when the release already exists its files are replaced instead of the job failing on the tag. The WARP frames are kept as a build artifact so that the Direct3D
renderer's output can be looked at beside the Metal one's; no job compares frames between the two systems
numerically, because they are not expected to be equal to the byte.

## Build and packaging

On macOS `zig build` produces `zig-out/bin/dentro` and assembles `zig-out/Dentro del cuerpo.app` (binary, Info.plist,
icon, shader source, licences), then seals the bundle with an ad-hoc signature. The bundle is signed where it is
installed: the path given to `codesign` is resolved against the install prefix when the step runs, so
`zig build --prefix DIR` seals `DIR/Dentro del cuerpo.app`, and a `codesign --verify --strict` step after
it fails the build if the seal does not match the bundle's contents. The fonts are inside the binary, so
the bundle carries no font files, only their licence texts under `Resources/licenses/`. `Info.plist` declares both localisations (`CFBundleLocalizations`), the
key macOS reads to offer an application its own language setting, and that it supports extended gamepads
(`GCSupportedGameControllers`, `GCSupportsControllerUserInteraction`), which is how macOS knows the game
can be driven from a controller. The icon is rendered by the game
itself (`dentro --icon`) and checked in as `res/AppIcon.icns`.

On macOS the save file is `~/Library/Application Support/Dentro del cuerpo/save.txt`, one line of space-separated
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
Cmd+Q. On Windows nothing exits from inside the pump. The entry posts `WM_CLOSE`, the message that Alt+F4
and the system menu's Close also end in, and the window procedure answers it by raising a flag instead of
destroying the window, so the main loop leaves on its next turn and its own cleanup runs. The exception is
the end of the Windows session, where the process may be ended as soon as `WM_ENDSESSION` returns, and
that message runs the same hook `applicationShouldTerminate:` does.

For Windows (`zig build -Dtarget=x86_64-windows-gnu`, on any host) the build produces the folder
`zig-out/Dentro del cuerpo/`: `Dentro del cuerpo.exe`, `shaders/shaders.hlsl`, the licences and a
`README.txt` with the SmartScreen note, the controls and the save location. CI zips that folder as
`Dentro-del-cuerpo-windows-x64.zip`. The target is the GNU ABI, so the C runtime is the Universal CRT that
is part of Windows and the executable imports only system DLLs; there is no redistributable to install.
The executable is linked for the GUI subsystem, so starting it opens no console window. The test modes
still have to print, so at startup the program attaches to its parent's console when it was given no
output handles of its own, which is the case when a GUI program is started from a terminal without
redirection. Three things are embedded as resources: the icon (`res/windows/AppIcon.ico`, nine sizes from
16 to 256 pixels, written by `dentro --icon` from the same drawing as the Mac icon), a manifest that
declares per-monitor-v2 DPI awareness so Windows never scales the window's pixels, and a version resource
that the build stamps from `-Dversion`, which CI sets to the release number. The window is sized in units
of 1/96 inch and scaled by the monitor's DPI, and follows the suggested rectangle when it is dragged to a
monitor of another density. Full screen is a borderless window covering the monitor, which the flip-model
swap chain presents without a display-mode change. The two window commands, full screen and quit, are in
the window's system menu with their titles in the game's language, since a game window has no menu bar
to put them in. The save file is `%APPDATA%\Dentro del cuerpo\save.txt`, in the same format and written
under the same guarantee as on macOS: missing folders are created one level at a time, the bytes go to a
temporary file beside the save, are flushed, and the file is moved over the save with `MoveFileExW` and
`MOVEFILE_REPLACE_EXISTING`, which replaces the old file in one step. The preferred language comes from
the user's display-language list (`GetUserPreferredUILanguages`).

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
| `src/draw.zig`, `src/render.zig` | scene, arms and HUD; batching |
| `src/gpu.zig`, `src/gpu/metal.zig`, `src/gpu/d3d11.zig`, `src/gpu/d3d11_api.zig` | the frame description and the GPU seam; the Metal and Direct3D 11 backends; Direct3D declarations |
| `src/shaders/`, `src/gpu/shader_parity.zig` | the Metal and HLSL shader files; the test that holds them together |
| `src/pad.zig`, `src/bindings.zig`, `src/input.zig` | controller state and its shaping; the layout and the names of controls per device; controller input as actions, and the device the prompts follow |
| `src/platform.zig`, `src/platform/keymap.zig` | the platform seam: keys, input state, window; hardware key codes to keys |
| `src/platform/macos.zig`, `src/platform/objc.zig` | AppKit window, event pump, GameController; the Objective-C runtime bridge |
| `src/platform/windows.zig`, `src/platform/win32.zig` | Win32 window, message pump, Raw Input; Win32 and COM declarations |
| `src/platform/xinput.zig`, `src/platform/pshid.zig`, `src/platform/padsel.zig` | XInput mapping and slot polling; DualShock 4 and DualSense report parsers; which controller is current |
| `src/audio.zig`, `src/audio/audioqueue.zig`, `src/audio/wasapi.zig` | synthesiser; its outputs |
| `src/util.zig`, `src/os/` | files, environment and the save folder, per system |
| `src/image.zig` | BMP, PNG and ICO encoding |
| `build.zig`, `res/`, `.github/` | the app bundle and the Windows folder; icons, manifest, package README; CI |
| `src/font.zig`, `src/utf8.zig`, `src/stb_truetype.c`, `vendor/stb/`, `res/fonts/` | glyph atlas and UTF-8 decoding; the rasteriser and the fonts it reads |
