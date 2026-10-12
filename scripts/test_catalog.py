#!/usr/bin/env python3
"""Offline catalog regression checks; no Docker daemon or third-party packages."""
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('image_inventory', ROOT / 'scripts/image_inventory.py')
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

catalog = ROOT / 'image-catalog'
images = {}
for source in sorted(catalog.glob('*.yaml')):
    for image_id, image in mod.parse_inventory(source).items():
        assert image_id not in images, image_id
        images[image_id] = image

with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp)
    shutil.copytree(catalog, repo / 'image-catalog')
    for image in images.values():
        folder = repo / image['context']
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'Dockerfile').write_text('FROM scratch\n' + ('ARG ' + image['version_arg'] + '\n' if image.get('version_arg') else ''))
        if image.get('package'):
            (folder / 'environment.yaml').write_text(f"dependencies:\n  - {image['package']}={image['version']}\n")
    new, sources = mod.load(repo / 'image-catalog')
    assert images == new
    assert len(images) == 24
    assert len({(value['repository'], mod.image_tag(value)) for value in new.values()}) == len(new)
    cmd = [sys.executable, str(ROOT / 'scripts/image_inventory.py'), '--inventory', str(repo / 'image-catalog')]
    for task in (['validate'], ['list', '--package', 'humann'], ['json'], ['ids'], ['get', 'humann-400a', 'tag']):
        subprocess.run(cmd + task, check=True, stdout=subprocess.DEVNULL)
    assert len(mod.load(repo / 'image-catalog')[0]) == 24
    with (repo / 'image-catalog/halla.yaml').open('a') as file:
        file.write('\n  humann-400a:\n    repository: "halla"\n')
    try:
        mod.load(repo / 'image-catalog')
    except mod.InventoryError as exc:
        assert 'duplicate image ID' in str(exc)
    else:
        raise AssertionError('cross-file duplicate ID not rejected')
    shutil.copy(catalog / 'halla.yaml', repo / 'image-catalog/halla.yaml')
    halla = repo / 'image-catalog/halla.yaml'
    halla.write_text(halla.read_text().replace('repository: "halla"', 'repository: "humann"').replace('aliases: ["0.8", "latest"]', 'aliases: ["0.8", "latest", "4"]'))
    try:
        mod.load(repo / 'image-catalog')
    except mod.InventoryError as exc:
        assert 'conflicts' in str(exc)
    else:
        raise AssertionError('cross-file tag conflict not rejected')
print('PASS: 24 entries, CLI, global tags, duplicate IDs, and cross-file collisions')
