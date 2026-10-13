#!/usr/bin/env python3
"""Create immutable, Switch-only PsyCross source overlay. Never edits upstream."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

BRANCH = 'playable/switch-experimental'
BASE = 'bd8d8842f6aeeb38659c21c190857120dd19236c'
MARKER = '.stage14f-overlay.json'


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def patch_files(src: Path, dst: Path) -> list:
    paths = ['src/platform.h', 'include/PsyX/PsyX_render.h']
    platform = dst / paths[0]
    s = platform.read_text()
    anchor = '#include <stdio.h>\n'
    if s.count(anchor) != 1 or 'SH14F Switch overlay' in s:
        raise RuntimeError('platform.h anchor unexpected; upstream is unchanged')
    s = s.replace(anchor, anchor + '''/* SH14F Switch overlay: SDL types used by libcd.c. */
#if defined(__SWITCH__)
#  include <SDL.h>
#endif
''', 1)
    platform.write_text(s)
    render = dst / paths[1]
    s = render.read_text()
    anchor = '#elif defined(__RPI__)\n#   define RENDERER_OGLES\n#   define OGLES_VERSION (3)\n'
    if s.count(anchor) != 1 or 'SH14F Switch overlay' in s:
        raise RuntimeError('PsyX_render.h renderer selector has changed; refusing blind patch')
    s = s.replace(anchor, '''/* SH14F Switch overlay: Khronos GLES3/EGL, no desktop GLAD. */
#elif defined(__SWITCH__)
#   define RENDERER_OGLES
#   define OGLES_VERSION (3)
''' + anchor, 1)
    render.write_text(s)
    return [{'file': p, 'source_sha256': sha(src / p), 'overlay_sha256': sha(dst / p)} for p in paths]


def check_existing(src: Path, out: Path) -> None:
    f = out / MARKER
    if not f.is_file():
        raise RuntimeError('Existing overlay lacks manifest; refusing to touch it')
    manifest = json.loads(f.read_text())
    for e in manifest['files']:
        if not (out / e['file']).is_file() or sha(out / e['file']) != e['overlay_sha256']:
            raise RuntimeError('Overlay changed after creation; preserve manual work')
        if sha(src / e['file']) != e['source_sha256']:
            raise RuntimeError('Upstream source changed; rebuild overlay under a new name')
    print('Overlay already present and verified:', out)


def main() -> None:
    repo = Path(os.environ.get('SH_REPO', str(Path.home() / 'Documentos/projetos_decompilacao/_silent_hill_playable_pilot/source-20261012T230037Z'))).expanduser().resolve()
    root = Path(os.environ.get('SH_PILOT_ROOT', str(repo.parent))).expanduser().resolve()
    src = repo / 'pc_port/PsyCross'
    out = root / 'switch-14f-psycross-overlay'
    wrapper = root / 'switch-14f-psycross-wrapper'
    for rel in ('src/platform.h', 'include/PsyX/PsyX_render.h', 'CMakeLists.txt'):
        if not (src / rel).is_file():
            raise RuntimeError(f'PsyCross source missing: {rel}')
    branch = subprocess.check_output(['git', '-C', str(repo), 'symbolic-ref', '--short', 'HEAD'], text=True).strip()
    if branch != BRANCH:
        raise RuntimeError(f'Expected branch {BRANCH}, found {branch}')
    subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', BASE, 'HEAD'], check=True)
    root.mkdir(parents=True, exist_ok=True)
    if out.exists():
        check_existing(src, out)
    else:
        tmp = Path(tempfile.mkdtemp(prefix='.stage14f-', dir=root))
        try:
            # Source is only read. No recursive git metadata or preexisting build products.
            shutil.rmtree(tmp)
            shutil.copytree(src, tmp, symlinks=True,
                ignore=shutil.ignore_patterns('.git', 'build', 'build-*', '*.o', '*.obj', '*.a', '*.so'))
            files = patch_files(src, tmp)
            (tmp / MARKER).write_text(json.dumps({'version': 1, 'files': files}, indent=2) + '\n')
            tmp.rename(out)
        except BaseException:
            if tmp.exists():
                shutil.rmtree(tmp)
            raise
        print('Switch-only overlay created:', out)
    wrapper.mkdir(exist_ok=True)
    cmake = wrapper / 'CMakeLists.txt'
    content = '''cmake_minimum_required(VERSION 3.16)
project(SHPsyCrossSwitch14F LANGUAGES C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory("''' + str(out) + '''" "${CMAKE_BINARY_DIR}/psycross")
'''
    if cmake.exists() and cmake.read_text() != content:
        raise RuntimeError('Existing CMake wrapper differs; refusing to overwrite')
    cmake.write_text(content)
    print('CMake wrapper:', cmake)
    print('Original upstream PsyCross: NOT MODIFIED')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print('ERROR:', exc, file=sys.stderr)
        raise SystemExit(1)
