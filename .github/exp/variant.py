"""Temporary: write a variant of a shader file for the border experiment. variant.py <src> <dst> <A|B|D|E>"""
import sys
src, dst, v = sys.argv[1:4]
s = open(src, newline='').read()
hlsl = src.endswith('.hlsl')
def rep(old, new):
    global s
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)
if v == 'B':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '')
elif v == 'D':
    rep('    for (int j = -2; j <= 2; j++)\n        for (int i = -2; i <= 2; i++) {\n            float2 g = mg + float2(i, j);'.replace('\n', '\r\n' if '\r\n' in s else '\n'),
        '    for (int j2 = -2; j2 <= 2; j2++)\n        for (int i2 = -2; i2 <= 2; i2++) {\n            float2 g = mg + float2(i2, j2);')
elif v == 'E':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(vo.y * 3.0, vo.x, vo.z, 1.0);')
elif v == 'F':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(edge, near, goblet, 1.0);')
elif v == 'G':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(albedo, 1.0);')
elif v == 'H':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(mott, band, vo.z, 1.0);')
elif v == 'I':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(smoothstep(0.0, 0.1, vo.y), saturate(vo.y * 10.0), vo.y * 3.0, 1.0);')
elif v == 'J':
    rep('        float edge = lerp(1.0, smoothstep(0.0, 0.1, vo.y), near);' if hlsl else '        float edge = mix(1.0, smoothstep(0.0, 0.1, vo.y), near);',
        '        float e_t = saturate(vo.y * 10.0); float edge = 1.0 + (e_t * e_t * (3.0 - 2.0 * e_t) - 1.0) * near;')
elif v == 'K':
    rep('        N = normalize(N - (1.0 - edge) * 0.5 * V);', '        return float4(edge, 1.0 + (smoothstep(0.0, 0.1, vo.y) - 1.0) * near, smoothstep(0.0, 0.1, vo.y), 1.0);')
open(dst, 'w', newline='').write(s)
