#!/usr/bin/env python3
"""Mock Docker to verify canonical/local-only aliases and experimental tags."""
import contextlib
import io
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_image
from image_inventory import load

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'image-catalog').mkdir()
    (root / 'testimage').mkdir()
    (root / 'testimage' / 'Dockerfile').write_text('FROM scratch\n')
    catalog = root / 'image-catalog' / 'test.yaml'
    catalog.write_text('''images:
  local-only:
    repository: "testimage"
    version: "1.0"
    revision: 2
    context: "testimage"
    aliases: ["1", "latest"]
    push_ghcr: false
    push_aws: false
    save: false
''')
    images, _ = load(root / 'image-catalog')
    assert images['local-only']['aliases'] == ['1', 'latest']
    for custom_tag, expected in [('', [
        ['docker', 'build', '-t', 'testimage:1.0-r2', '-f', 'testimage/Dockerfile'],
        ['docker', 'tag', 'testimage:1.0-r2', 'testimage:1'],
        ['docker', 'tag', 'testimage:1.0-r2', 'testimage:latest'],
    ]), ('scratch-test', [
        ['docker', 'build', '-t', 'testimage:scratch-test', '-f', 'testimage/Dockerfile'],
    ])]:
        commands = []
        def fake_run(command, **kwargs):
            commands.append(command)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(build_image, 'run', side_effect=fake_run), patch.object(
            build_image, 'load', return_value=(images, {})
        ), patch.object(sys, 'argv', [
            'build_image.py', '--inventory', str(root / 'image-catalog'),
            '--id', 'local-only', '--tag', custom_tag,
        ]), contextlib.redirect_stdout(io.StringIO()):
            build_image.main()
        assert len(commands) == len(expected), commands
        for actual, prefix in zip(commands, expected):
            assert actual[:len(prefix)] == prefix, actual
        assert not any('push' in c for c in commands)
print('PASS: local-only aliases, canonical build tagging, experimental override isolation')
