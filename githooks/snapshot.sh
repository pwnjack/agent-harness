#!/bin/bash
# Export a private index snapshot using read-only Git commands. Its minimal Git
# metadata supports tracked-file discovery without sharing writable state with
# the real repository. No stash, checkout, staging, or temporary branch.
set -euo pipefail
python3 - "$@" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zlib

repo, target = map(Path, sys.argv[1:])
def git(*args, env=None):
    return subprocess.check_output(['git', '-C', str(repo), *args], env=env)

work = target / 'worktree'
metadata = work / '.git'
metadata.mkdir(parents=True)
(metadata / 'objects').mkdir()
(metadata / 'refs').mkdir()
(metadata / 'HEAD').write_text('ref: refs/heads/snapshot\n')
object_format = git('rev-parse', '--show-object-format').decode().strip()
config = '[core]\n\trepositoryformatversion = 0\n\tbare = false\n'
if object_format != 'sha1':
    config = f'[core]\n\trepositoryformatversion = 1\n\tbare = false\n[extensions]\n\tobjectFormat = {object_format}\n'
(metadata / 'config').write_text(config)
index = Path(os.fsdecode(git('rev-parse', '--path-format=absolute', '--git-path', 'index')).strip())
shutil.copyfile(index, metadata / 'index')
gitdir = Path(os.fsdecode(git('rev-parse', '--absolute-git-dir')).strip())
for shared in gitdir.glob('sharedindex.*'):
    shutil.copyfile(shared, metadata / shared.name)
env = dict(os.environ, GIT_INDEX_FILE=str(metadata / 'index'))
# All three listings read the same copied index, including partial staging.
entries = git('ls-files', '--stage', '-z', env=env).split(b'\0')
for filename, extra in [('lint-paths', ['--diff-filter=ACM']), ('changed-paths', [])]:
    (target / filename).write_bytes(git('diff', '--cached', '--name-only', '--no-renames', '-z', *extra, env=env))

with subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env) as blobs:
    try:
        for entry in entries:
            if not entry:
                continue
            fields, raw_path = entry.split(b'\t', 1)
            mode, oid, stage = fields.split()
            if stage != b'0':
                raise RuntimeError('Resolve staged conflicts before running checks')
            if mode not in (b'100644', b'100755', b'120000'):
                raise RuntimeError(f'Unsupported staged file mode: {os.fsdecode(raw_path)}')
            path = Path(os.fsdecode(raw_path))
            if path.is_absolute() or any(part in ('.git', '..') for part in path.parts):
                raise RuntimeError('Unsafe staged path')
            destination = work / path
            if any(parent.is_symlink() for parent in destination.parents):
                raise RuntimeError('Staged file has a symlink parent')
            destination.parent.mkdir(parents=True, exist_ok=True)
            blobs.stdin.write(oid + b'\n')
            blobs.stdin.flush()
            header = blobs.stdout.readline().split()
            if len(header) != 3 or header[1] != b'blob':
                raise RuntimeError(f'Cannot read staged blob: {os.fsdecode(raw_path)}')
            size = int(header[2])
            content = blobs.stdout.read(size)
            if len(content) != size or blobs.stdout.read(1) != b'\n':
                raise RuntimeError('Incomplete staged blob')
            if mode == b'120000':
                destination.symlink_to(os.fsdecode(content))
            else:
                destination.write_bytes(content)
                destination.chmod(int(mode, 8) & 0o777)
            # Private blob storage also permits git show :path in test suites.
            object_path = metadata / 'objects' / oid[:2].decode() / oid[2:].decode()
            object_path.parent.mkdir(exist_ok=True)
            object_path.write_bytes(zlib.compress(b'blob ' + str(size).encode() + b'\0' + content))
    finally:
        blobs.stdin.close()
    if blobs.wait() != 0:
        raise RuntimeError('Git failed while exporting staged files')
PY
