// The one translation unit that compiles the vendored rasteriser. src/font.zig declares the handful of
// stbtt_* functions it calls and holds a stbtt_fontinfo as opaque storage of the size asserted here.
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

_Static_assert(sizeof(stbtt_fontinfo) <= 256, "FontInfo in src/font.zig is too small for stbtt_fontinfo");
_Static_assert(_Alignof(stbtt_fontinfo) <= 8, "FontInfo in src/font.zig is under-aligned for stbtt_fontinfo");
