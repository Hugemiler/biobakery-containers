#!/usr/bin/env bash
# Reproducible (on a pinned GNU tar + zstd toolchain) database archive and provenance sidecars.
set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 SOURCE_DIRECTORY OUTPUT_DIRECTORY BUNDLE_NAME" >&2
  echo "Example: $0 /data/metaphlan/mpa_vOct22_202403 /dist/metaphlan/mpa_vOct22_202403 metaphlan-mpa_vOct22_202403" >&2
  exit 2
fi

source_dir=$(realpath -- "$1")
output_dir=$(realpath -m -- "$2")
name=$3
[[ -d "$source_dir" ]] || { echo "Missing source directory: $source_dir" >&2; exit 2; }
[[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || { echo "Invalid bundle name" >&2; exit 2; }
command -v zstd >/dev/null || { echo 'zstd is required' >&2; exit 2; }
command -v sha256sum >/dev/null || { echo 'sha256sum is required' >&2; exit 2; }
mkdir -p -- "$output_dir"
# Do not archive an output folder nested inside the input directory.
case "$output_dir/" in "$source_dir/"*) echo 'OUTPUT_DIRECTORY must be outside SOURCE_DIRECTORY' >&2; exit 2;; esac
archive="$output_dir/$name.tar.zst"
[[ ! -e "$archive" ]] || { echo "Already exists: $archive (refusing to overwrite)" >&2; exit 2; }

# Archive the directory CONTENTS, so extraction with -C /Databases/<tool> is predictable.
# Exclude volatile pax atime/ctime; normalize uid/gid and mtime.
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --format=posix --pax-option=delete=atime,delete=ctime \
  -C "$source_dir" -cf - . | zstd -T8 -6 -q -o "$archive"
(
  cd "$output_dir"
  sha256sum "$name.tar.zst" > "$name.tar.zst.sha256"
  sha256sum -c "$name.tar.zst.sha256"
)

python3 - "$archive" "$name" "$source_dir" <<'PY'
import json, pathlib, subprocess, sys
archive = pathlib.Path(sys.argv[1])
name, source = sys.argv[2:]
def version(cmd):
    return subprocess.check_output(cmd, text=True).splitlines()[0]
metadata = {
    'schema_version': 1,
    'name': name,
    'archive': archive.name,
    'archive_sha256': (archive.parent / (name + '.tar.zst.sha256')).read_text().split()[0],
    'archive_bytes': archive.stat().st_size,
    'layout': 'directory contents; extract into destination with tar -C',
    'source_directory_name': pathlib.Path(source).name,
    'compression': 'zstd -T1 -19',
    'tar_options': ['--sort=name', "--mtime=@0", '--owner=0', '--group=0', '--numeric-owner', '--format=posix', '--pax-option=delete=atime,delete=ctime'],
    'tar_version': version(['tar', '--version']),
    'zstd_version': version(['zstd', '--version']),
}
(archive.parent / (name + '.metadata.json')).write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n', encoding='utf-8')
PY
printf 'Created: %s\n' "$archive"
