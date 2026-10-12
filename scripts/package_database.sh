#!/usr/bin/env bash
# Package a database directory as a reproducible gzip tarball with checksum and metadata.
set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 SOURCE_DIRECTORY OUTPUT_DIRECTORY BUNDLE_NAME" >&2
  exit 2
fi

source_dir=$(realpath -- "$1")
output_dir=$(realpath -m -- "$2")
name=$3
[[ -d "$source_dir" ]] || { echo "Directory not found: $source_dir" >&2; exit 2; }
[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "Invalid bundle name: $name" >&2; exit 2; }
case "$output_dir/" in "$source_dir/"*) echo "Output directory must be outside source directory" >&2; exit 2;; esac
mkdir -p -- "$output_dir"
archive="$output_dir/$name.tar.gz"
[[ ! -e "$archive" ]] || { echo "Archive already exists: $archive" >&2; exit 2; }

# Store directory CONTENTS (./file), not its containing folder.
# GNU tar flags normalize ordering, timestamps, ownership and volatile metadata.
# tar -z uses gzip's default compression level (6).
# Write to a temporary file so failed builds do not leave a finished-looking archive.
tmp="$archive.tmp"
trap 'rm -f -- "$tmp"' EXIT
tar -cvzf "$tmp" \
  --sort=name \
  --mtime='@0' \
  --owner=0 --group=0 --numeric-owner \
  --format=posix --pax-option=delete=atime,delete=ctime \
  -C "$source_dir" .
mv -- "$tmp" "$archive"
trap - EXIT

(
  cd "$output_dir"
  sha256sum "$name.tar.gz" > "$name.tar.gz.sha256"
  sha256sum -c "$name.tar.gz.sha256"
)

python3 - "$archive" "$name" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

archive = pathlib.Path(sys.argv[1])
name = sys.argv[2]
with archive.open('rb') as stream:
    sha256 = hashlib.file_digest(stream, 'sha256').hexdigest()
metadata = {
    'schema_version': 1,
    'name': name,
    'archive': archive.name,
    'archive_bytes': archive.stat().st_size,
    'archive_sha256': sha256,
    'compression': 'gzip (tar -z, default level 6)',
    'layout': 'directory contents; extract with tar -xzf archive -C DESTINATION',
    'tar_version': subprocess.check_output(['tar', '--version'], text=True).splitlines()[0],
    'gzip_version': subprocess.check_output(['gzip', '--version'], text=True).splitlines()[0],
}
(archive.parent / f'{name}.metadata.json').write_text(
    json.dumps(metadata, sort_keys=True, indent=2) + '\n', encoding='utf-8'
)
PY
printf '\nCreated: %s\n' "$archive"
