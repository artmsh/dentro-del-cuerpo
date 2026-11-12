"""Checks the packaged Windows executable before it is released.

    python check-windows-exe.py <exe> <version>

It must be a 64-bit GUI program (no console window behind the game), carry its icon, its DPI manifest and
a version resource equal to <version>, and import nothing but DLLs that are part of Windows 10 and 11, so
that the zip runs on a clean machine with nothing installed.
"""
import struct
import sys

# System DLLs. The api-ms-win-crt-* names are the Universal C Runtime, part of Windows since 10.
ALLOWED = {"kernel32.dll", "ntdll.dll", "user32.dll", "shell32.dll", "ole32.dll", "shcore.dll", "d3d11.dll"}


def main(path, version):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    assert d[pe:pe + 4] == b"PE\0\0", "not a PE file"
    machine, nsec, _, _, _, optsz, _ = struct.unpack_from("<HHIIIHH", d, pe + 4)
    opt = pe + 24
    assert machine == 0x8664, f"machine is 0x{machine:04x}, not x86-64"
    assert struct.unpack_from("<H", d, opt)[0] == 0x20B, "not PE32+"
    subsystem = struct.unpack_from("<H", d, opt + 68)[0]
    assert subsystem == 2, f"subsystem is {subsystem}, not 2 (Windows GUI)"
    ndirs = struct.unpack_from("<I", d, opt + 108)[0]
    dirs = [struct.unpack_from("<II", d, opt + 112 + 8 * i) for i in range(ndirs)]
    secs = [struct.unpack_from("<8sIIII", d, opt + optsz + 40 * i) for i in range(nsec)]

    def off(rva):
        for _, vsz, va, rsz, rptr in secs:
            if va <= rva < va + max(vsz, rsz):
                return rva - va + rptr
        raise ValueError(f"rva 0x{rva:x} is in no section")

    def cstr(o):
        return d[o:d.index(b"\0", o)].decode()

    imports = []
    o = off(dirs[1][0])
    while True:
        name = struct.unpack_from("<IIIII", d, o)[3]
        if not name:
            break
        imports.append(cstr(off(name)))
        o += 20
    assert dirs[13][0] == 0, "delay-loaded imports are not expected"
    foreign = [n for n in imports if n.lower() not in ALLOWED and not n.lower().startswith("api-ms-win-crt-")]
    assert not foreign, f"imports DLLs that are not part of Windows: {foreign}"

    base = off(dirs[2][0])
    found = {}

    def walk(o, path):
        named, ids = struct.unpack_from("<HH", d, o + 12)
        for i in range(named + ids):
            ident, data = struct.unpack_from("<II", d, o + 16 + 8 * i)
            if data >> 31:
                walk(base + (data & 0x7FFFFFFF), path + [ident])
            else:
                rva, size = struct.unpack_from("<II", d, base + data)
                found.setdefault(path[0], []).append(d[off(rva):off(rva) + size])

    walk(base, [])
    assert 14 in found and len(found.get(3, [])) >= 4, "no icon with several sizes"
    assert 24 in found and b"PerMonitorV2" in found[24][0], "no per-monitor-v2 DPI manifest"
    assert 16 in found, "no version resource"
    info = found[16][0]
    fixed = info.find(struct.pack("<I", 0xFEEF04BD))
    ms, ls = struct.unpack_from("<II", info, fixed + 8)
    stamped = f"{ms >> 16}.{ms & 0xFFFF}.{ls >> 16}"
    assert stamped == version, f"version resource says {stamped}, expected {version}"

    print(f"{path}: x86-64 GUI executable, version {stamped}, {len(found[3])} icon sizes, per-monitor-v2 manifest")
    print("imports: " + ", ".join(sorted(imports, key=str.lower)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
