#!/usr/bin/env python3
"""Save a canonical Docker image once; never overwrite an existing bundle.

Bundle layout: <output>/<repository>_<tag>.tar{,.sha256}, inspect.json,
manifest.json. Complete bundles are skipped without contacting Docker.
Incomplete bundles fail, rather than silently mixing build artifacts.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def archive_names(image_ref: str, tag: str):
    repository, sep, ref_tag = image_ref.rpartition(':')
    if not sep or not repository or ref_tag != tag:
        raise ValueError(f'expected canonical image reference repository:{tag}; got {image_ref!r}')
    # Docker repository names can contain path separators; safe deterministic filename.
    basename = f'{repository.replace("/", "_")}_{tag}'
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', basename):
        raise ValueError(f'unsafe archive basename {basename!r}')
    return (f'{basename}.tar', f'{basename}.tar.sha256')


def archive_image(image_ref: str, image_id: str, tag: str, dest: Path) -> str:
    tar_name, checksum_name = archive_names(image_ref, tag)
    expected = [tar_name, checksum_name, 'inspect.json', 'manifest.json']
    if dest.exists():
        if not dest.is_dir():
            raise RuntimeError(f'{dest} exists but is not a directory')
        present = [name for name in expected if (dest / name).is_file()]
        other = [p.name for p in dest.iterdir() if p.name not in expected]
        if len(present) == len(expected) and not other:
            print(f'SKIP: {image_ref}: complete artifact bundle exists at {dest}', flush=True)
            return 'skipped'
        raise RuntimeError(
            f'Incomplete or unexpected bundle at {dest}. Present: {present}; extra: {other}. '
            'Remove the artifact directory explicitly to regenerate it.'
        )

    dest.parent.mkdir(parents=True, exist_ok=True)
    # Sibling staging directory, so final rename is atomic on the same filesystem.
    tmp = Path(tempfile.mkdtemp(prefix=f'.{dest.name}.staging-', dir=dest.parent))
    try:
        info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', image_ref], text=True))
        if len(info) != 1:
            raise RuntimeError(f'expected exactly one image inspection for {image_ref}')
        image = info[0]
        (tmp / 'inspect.json').write_text(json.dumps(info, indent=2) + '\n')
        archive = tmp / tar_name
        with archive.open('wb') as stream:
            subprocess.run(['docker', 'image', 'save', image_ref], stdout=stream, check=True)
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
                digest.update(chunk)
        sha = digest.hexdigest()
        (tmp / checksum_name).write_text(f'{sha}  {tar_name}\n')
        manifest = {
            'schema_version': 1,
            'inventory_id': image_id,
            'image_reference': image_ref,
            'canonical_tag': tag,
            'image_id': image['Id'],
            'repo_digests': image.get('RepoDigests') or [],
            'platform': f"{image.get('Os', 'unknown')}/{image.get('Architecture', 'unknown')}",
            'labels': (image.get('Config') or {}).get('Labels') or {},
            'archive_file': tar_name,
            'archive_sha256': sha,
            'archive_size_bytes': archive.stat().st_size,
            'inspect_file': 'inspect.json',
        }
        (tmp / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        # Never overwrite on a race; os.rename on POSIX fails if destination is a
        # non-empty directory, which is the intended protection here.
        if dest.exists():
            raise RuntimeError(f'{dest} appeared while staging; refusing to overwrite')
        tmp.rename(dest)
    finally:
        if tmp.exists():
            shutil.rmtree(tmp)
    print(f'Archived {image_ref} -> {dest} (sha256:{sha})', flush=True)
    return 'created'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    archive_image(args.image, args.id, args.tag, args.output)


if __name__ == '__main__':
    main()
