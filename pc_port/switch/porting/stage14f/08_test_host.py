#!/usr/bin/env python3
"""Fast host tests for exact Switch-only patch anchors and isolation."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import subprocess
import sys

this = Path(__file__).parent
spec = importlib.util.spec_from_file_location('overlay', this / 'prepare_overlay.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
with TemporaryDirectory() as d:
    src = Path(d) / 'src'
    dst = Path(d) / 'out'
    for root in (src, dst):
        (root / 'src').mkdir(parents=True)
        (root / 'include/PsyX').mkdir(parents=True)
        (root / 'src/platform.h').write_text('''#ifndef PLAT_H\n#define PLAT_H\n#include <stdio.h>\n#endif\n''')
        (root / 'include/PsyX/PsyX_render.h').write_text('''#ifndef RENDER_H\n#define RENDER_H\n#if defined(__ANDROID__)\n#   define RENDERER_OGLES\n#   define OGLES_VERSION (3)\n#elif defined(__RPI__)\n#   define RENDERER_OGLES\n#   define OGLES_VERSION (3)\n#endif\n#endif\n''')
    before = [(p.relative_to(src), p.read_bytes()) for p in src.rglob('*.h')]
    files = m.patch_files(src, dst)
    assert len(files) == 2
    after = [(p.relative_to(src), p.read_bytes()) for p in src.rglob('*.h')]
    assert before == after, 'Original header was modified'
    render = (dst / 'include/PsyX/PsyX_render.h').read_text()
    assert 'defined(__SWITCH__)' in render
    assert '#   define OGLES_VERSION (3)' in render
    assert '#   define RENDERER_OGLES' in render
    assert (dst / 'src/platform.h').read_text().count('#  include <SDL.h>') == 1
    # C preprocessor selection: Switch => GLES3, Linux => no Switch branch.
    for flags, expect in [(['-D__SWITCH__'], 'GLES3_SELECTED'), ([], 'NO_SWITCH_GLES')]:
        code = render + '''\n#ifdef RENDERER_OGLES\nGLES3_SELECTED\n#else\nNO_SWITCH_GLES\n#endif\n'''
        r = subprocess.run(['gcc', '-E', '-P', '-x', 'c', *flags, '-'], input=code,
                           text=True, capture_output=True, check=True)
        assert expect in r.stdout, (flags, r.stdout)
    # The same file cannot be blindly patched twice.
    try:
        m.patch_files(src, dst)
    except RuntimeError:
        pass
    else:
        raise AssertionError('Second patch should refuse to apply')
print('PASS: renderer Switch GLES3 selection, SDL injection, upstream untouched, idempotency refusal')
