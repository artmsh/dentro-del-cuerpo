#!/usr/bin/env python3
"""Build Dentro del cuerpo for the Samsung Q80D with tvengine (the `engine` submodule).

  tv/build.sh --test --unsigned        the game's tests, an unsigned package and the ABI checks
  tv/build.sh --install                signed package, installed and launched on the television
  DEBUG_HOST=<ip> SELFTEST=1 CHAPTER=2 tv/build.sh --install
                                       the scripted pilot flies chapter 2, with telemetry to <ip>

Environment: TV (address:port of the television), CERT_PROFILE (signing profile, `dev`), SCENE_HEIGHT,
MIN_SCENE_HEIGHT and MSAA (what the scene pass may spend), CAPTURE=1 (send frames to engine/tools/capture-server.py),
MUTE=1 (no audio stream), PROFILE=1 (time each phase of the frame, which slows it),
COMPUTED_PATTERNS=1 (compute the materials' patterns per pixel as the desktop does, instead of baking them),
NO_HOLD=1 / FORCE_HOLD=1 (the engine's CPU clock hold), VERSION (major.minor.patch).
"""
import os, pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
engine = pathlib.Path(os.getenv('TVENGINE', root / 'engine'))
if not (engine / 'tools/tvbuild.py').exists():
    sys.exit('engine submodule missing: run `git submodule update --init`')
sys.path.insert(0, str(engine / 'tools'))
import tvbuild

MATH = 'sin cos tan sincos exp exp2 log log2 log10 fmod fma floor ceil round trunc sqrt fabs fmin fmax'.split()


def hard_float_math(build):
    """The math functions of Zig's runtime library, compiled to use the processor's floating point.

    Zig builds its runtime (compiler-rt, which holds sin, cos, exp and the rest) for this target with
    floating point emulated in integer code, as the target's calling convention suggests. A sine then
    costs 0.6 microseconds on the television, and the simulation, which evaluates thousands a step, ran
    hundreds of times slower than on a desktop. The same sources are compiled here the way tvbuild
    compiles the game (LLVM IR, soft-float attributes removed, clang with softfp), and only the math
    functions are kept as symbols. The object is linked ahead of the runtime library, so these are the
    definitions the game and its C code use.
    """
    out = build / 'rt' / 'math.o'
    version = subprocess.check_output(['zig', 'version'], text=True).strip()
    stamp = build / 'rt' / 'zig-version'
    if out.exists() and stamp.exists() and stamp.read_text() == version:
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    lib = re.search(r'lib_dir\W+"([^"]+)"', subprocess.check_output(['zig', 'env'], text=True)).group(1)
    ir = out.with_suffix('.ll')
    tvbuild.run('zig', 'build-obj', '-target', tvbuild.TARGET, f'-mcpu={tvbuild.CPU}', '-O', 'ReleaseFast', '-fPIC',
                '-fstrip', '-lc', f'-Mroot={lib}/compiler_rt.zig', f'-femit-llvm-ir={ir}', '-fno-emit-bin')
    text = ir.read_text()
    assert '"use-soft-float"="true"' in text, 'Zig no longer emits use-soft-float; revisit the softfp pipeline'
    text = text.replace(' "use-soft-float"="true"', '').replace(' noimplicitfloat', '')
    keep = {name + suffix for name in MATH for suffix in ('', 'f')}
    # Every exported name is an alias of a private function. The ones that are not math functions are
    # made internal to the object, so the runtime library's own definitions of them stay in use.
    alias = re.compile(r'@([\w.]+) = weak_odr hidden alias ')
    lines, kept = [], set()
    for line in text.splitlines(keepends=True):
        m = alias.match(line)
        if m and m.group(1) in keep:
            kept.add(m.group(1))
        elif m:
            line = line.replace(' = weak_odr hidden alias ', ' = internal alias ', 1)
        lines.append(line)
    assert kept == keep, f'the runtime library no longer exports {sorted(keep - kept)}'
    fixed = out.with_suffix('.softfp.ll')
    fixed.write_text(''.join(lines))
    tvbuild.run('zig', 'cc', '-target', tvbuild.TARGET, f'-mcpu={tvbuild.CPU}', '-mfloat-abi=softfp', '-mfpu=neon', '-O2',
                '-fPIC', '-Wno-override-module', '-c', fixed, '-o', out)
    stamp.write_text(version)
    return out


# The package carries the version of the latest release tag unless VERSION names another.
tag = subprocess.run(['git', '-C', str(root), 'describe', '--tags', '--abbrev=0'], capture_output=True, text=True).stdout.strip()
app = tvbuild.App(
    id='jo.dentro', exe='dentro', label='Dentro del cuerpo', version=os.getenv('VERSION') or tag.lstrip('v') or '0.0.0',
    root='src/tv.zig', icon='tv/icon.png',
    # The fonts are embedded by name, as build.zig embeds them for the desktop.
    modules={
        'font-regular': 'res/fonts/NotoSans-ExtraCondensedMedium.ttf',
        'font-bold': 'res/fonts/NotoSans-ExtraCondensedSemiBold.ttf',
        'font-symbols': 'res/fonts/DejaVuSans.ttf',
    },
    c_sources=['src/stb_truetype.c'], c_flags=['-Ivendor/stb', '-fno-sanitize=undefined'],
    resources=[
        ('LICENSE', 'licenses/LICENSE.txt'), ('LICENSE-ARTWORK.txt', 'licenses/LICENSE-ARTWORK.txt'),
        ('res/fonts/OFL-NotoSans.txt', 'licenses/NotoSans-OFL.txt'),
        ('res/fonts/LICENSE-DejaVu.txt', 'licenses/DejaVuSans-LICENSE.txt'),
        ('vendor/stb/LICENSE', 'licenses/stb_truetype-LICENSE.txt'),
    ],
    flags={'selftest': False, 'capture': False, 'mute': False, 'profile': False, 'computed_patterns': False, 'no_hold': False, 'force_hold': False},
    # scene_height, min_scene_height: the most and the fewest rows of the scene image, which is scaled up
    # to the 1080 of the output; the game moves between them as the GPU keeps up with the display or does
    # not. msaa: samples per pixel of the scene pass. chapter: the one the scripted pilot flies.
    values={'scene_height': 510, 'min_scene_height': 254, 'msaa': 4, 'chapter': 1},
    host_modules=False, root_dir=root)
if tvbuild.softfp():
    for cache in ('ZIG_GLOBAL_CACHE_DIR', 'ZIG_LOCAL_CACHE_DIR'):
        os.environ.setdefault(cache, str(root / '.build/zig-cache'))
    app.objects = [hard_float_math(root / '.build')]
if '--test' in sys.argv:
    subprocess.run(['zig', 'build', 'test'], cwd=root, check=True)
tvbuild.main(app)
