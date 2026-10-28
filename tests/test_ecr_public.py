#!/usr/bin/env python3
"""Exercise ECR Make targets offline with fake AWS and Docker executables."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp)
    shutil.copy(ROOT / 'Makefile', repo / 'Makefile')
    (repo / 'scripts').mkdir()
    shutil.copy(ROOT / 'scripts/image_inventory.py', repo / 'scripts/image_inventory.py')
    (repo / 'fixture').mkdir()
    (repo / 'fixture/Dockerfile').write_text('FROM scratch\n')
    catalog = repo / 'images.yaml'
    catalog.write_text('''images:
  selected:
    repository: "kneaddata"
    version: "1.0"
    revision: 1
    context: "fixture"
    aliases: ["latest"]
    push_ghcr: false
    push_aws: true
  unselected:
    repository: "other"
    version: "1.0"
    revision: 1
    context: "fixture"
    aliases: []
    push_ghcr: false
    push_aws: false
''')
    binaries = repo / 'bin'
    binaries.mkdir()
    log = repo / 'calls.jsonl'
    stub = f'''#!{sys.executable}
import json
import sys
from pathlib import Path
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
if tool == 'docker' and args[0] == 'login':
    assert sys.stdin.read() == 'offline-test-password\\n'
with Path({str(log)!r}).open('a') as output:
    output.write(json.dumps([tool] + args) + '\\n')
if tool == 'aws':
    print('offline-test-password')
'''
    for tool in ('aws', 'docker'):
        executable = binaries / tool
        executable.write_text(stub)
        executable.chmod(0o755)
    env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.defpath)

    def run(target, namespace, profile='offline-publisher'):
        log.write_text('')
        result = subprocess.run([
            'make', '--no-print-directory', target,
            f'PYTHON={sys.executable}', 'INVENTORY=images.yaml',
            f'ECR_REPO={namespace}', f'AWS_ECR_PROFILE={profile}',
            'AWS_REGION=us-west-2',
        ], cwd=repo, env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        return result, calls

    namespace = 'public.ecr.aws/test-alias'
    auth = ['aws', 'ecr-public', 'get-login-password', '--region', 'us-east-1',
            '--profile', 'offline-publisher']
    login = ['docker', 'login', '--username', 'AWS', '--password-stdin', 'public.ecr.aws']
    canonical = namespace + '/kneaddata:1.0-r1'
    for target in ('login-aws', 'push-aws', 'push-aws-aliases'):
        result, calls = run(target, 'test-alias')
        assert result.returncode == 0, f'{target} failed'
        # The AWS and Docker login processes run concurrently in a pipe.
        assert len(calls) >= 2 and auth in calls[:2] and login in calls[:2]
        expected = [] if target == 'login-aws' else [
            ['docker', 'image', 'inspect', 'kneaddata:1.0-r1'],
            ['docker', 'tag', 'kneaddata:1.0-r1', canonical],
            ['docker', 'push', canonical],
        ]
        if target == 'push-aws-aliases':
            expected.append(['docker', 'buildx', 'imagetools', 'create',
                             '--tag', namespace + '/kneaddata:latest', canonical])
        assert calls[2:] == expected, 'Unexpected publication commands'

    for target in ('login-aws', 'push-aws'):
        result, calls = run(target, 'test-alias', '')
        assert result.returncode != 0 and not calls, 'Missing profile must prevent login'

    catalog.write_text(catalog.read_text().replace('push_aws: true', 'push_aws: false'))
    result, calls = run('push-aws-aliases', '', '')
    assert result.returncode == 0 and not calls, 'Unselected images must not require AWS'

print('PASS: public ECR login, canonical pushes, aliases, selection, and required profile')
