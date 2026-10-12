#!/usr/bin/env python3
"""Export one local Docker image as inspect.json, image.tar, SHA256 and manifest."""
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    dest = args.output
    dest.mkdir(parents=True, exist_ok=True)
    info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', args.image], text=True))
    if len(info) != 1:
        raise RuntimeError(f'expected exactly one image inspection for {args.image}')
    image = info[0]
    with tempfile.TemporaryDirectory(prefix='.archive-', dir=dest) as tmp_dir:
        tmp = Path(tmp_dir)
        (tmp / 'inspect.json').write_text(json.dumps(info, indent=2) + '\n')
        archive = tmp / 'image.tar'
        with archive.open('wb') as stream:
            subprocess.run(['docker', 'image', 'save', args.image], stdout=stream, check=True)
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
                digest.update(chunk)
        sha = digest.hexdigest()
        (tmp / 'image.tar.sha256').write_text(f'{sha}  image.tar\n')
        manifest = {
            'schema_version': 1,
            'inventory_id': args.id,
            'image_reference': args.image,
            'canonical_tag': args.tag,
            'image_id': image['Id'],
            'repo_digests': image.get('RepoDigests') or [],
            'platform': f"{image.get('Os', 'unknown')}/{image.get('Architecture', 'unknown')}",
            'labels': (image.get('Config') or {}).get('Labels') or {},
            'archive_file': 'image.tar',
            'archive_sha256': sha,
            'archive_size_bytes': archive.stat().st_size,
            'inspect_file': 'inspect.json',
        }
        (tmp / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        # Publish only after every stage succeeds; leave prior bundle untouched on failure.
        for name in ('image.tar', 'inspect.json', 'image.tar.sha256', 'manifest.json'):
            os.replace(tmp / name, dest / name)
    print(f'Archived {args.image} -> {dest} (sha256:{sha})')


if __name__ == '__main__':
    main()
