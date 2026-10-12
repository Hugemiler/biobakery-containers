#!/usr/bin/env python3
"""Build one catalog image, supplying resolved AWS DB credentials only when required."""
import argparse
import configparser
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from image_inventory import load, image_tag


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def preflight(profile):
    if not profile:
        raise RuntimeError("AWS_DB_PROFILE is required for database_source=s3-private; no Docker build was started")
    try:
        identity = run(["aws", "sts", "get-caller-identity", "--profile", profile, "--output", "json"], capture_output=True, text=True)
        account = json.loads(identity.stdout).get("Account", "unknown")
        print(f"Database AWS profile '{profile}' authenticated (account {account})", flush=True)
        result = run(["aws", "configure", "export-credentials", "--profile", profile, "--format", "process"], capture_output=True, text=True)
        data = json.loads(result.stdout)
        if not data.get("AccessKeyId") or not data.get("SecretAccessKey"):
            raise RuntimeError("AWS CLI returned incomplete credentials")
        return data
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError) as error:
        raise RuntimeError(f"AWS_DB_PROFILE '{profile}' authentication failed; check the profile or run aws sso login --profile {profile}. No Docker build was started") from error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--tag', default='')
    parser.add_argument('--artifact-home', default='dist')
    parser.add_argument('--archive-tool', default='scripts/archive_image.py')
    parser.add_argument('--aws-db-profile', default='')
    parser.add_argument('--local-database-source')
    args = parser.parse_args()
    images, _ = load(args.inventory)
    image = images[args.id]
    tag = args.tag or image_tag(image)
    ref = f"{image['repository']}:{tag}"
    source = image.get('database_source')
    local_db_path = Path(args.local_database_source).expanduser().resolve()
    if not local_db_path.is_dir():
        raise RuntimeError(
            f'BUILD_LOCAL_DATABASE_SOURCE={local_db_path} is not a directory; '
            'every build requires the named databases context. '
            'Set BUILD_LOCAL_DATABASE_SOURCE to an existing directory.'
        )
    creds = preflight(args.aws_db_profile) if source == 's3-private' else None
    command = ['docker', 'buildx', 'build', '--load',
               '--build-context', f'databases={local_db_path}',
               '-t', ref, '-f', f"{image['context']}/Dockerfile"]
    if image.get('version_arg'):
        command += ['--build-arg', f"{image['version_arg']}={image.get('version', '')}"]
    if image.get('version'):
        command += ['--label', f"org.opencontainers.image.version={image['version']}"]
    command += ['--label', f'org.biobakery.database.source={source or "none"}']
    if creds:
        # Temporary file only, not a build ARG or environment variable.
        # AWS_PROFILE=default inside the build selects this synthesized file.
        with tempfile.TemporaryDirectory(prefix='biobakery-aws-') as directory:
            path = Path(directory) / 'credentials'
            config = configparser.ConfigParser()
            config['default'] = {
                'aws_access_key_id': creds['AccessKeyId'],
                'aws_secret_access_key': creds['SecretAccessKey'],
            }
            if creds.get('SessionToken'):
                config['default']['aws_session_token'] = creds['SessionToken']
            with path.open('w') as file:
                config.write(file)
            path.chmod(0o600)
            command += ['--secret', f'id=aws_db_credentials,src={path}']
            command.append(image['context'])
            print(f'Building {ref} ({source}); private S3 credentials mounted as BuildKit secret', flush=True)
            run(command)
    else:
        command.append(image['context'])
        print(f'Building {ref} (database_source={source or "none"}; no AWS DB authentication)', flush=True)
        run(command)
    # Canonical builds own all catalog-declared local aliases. Experimental
    # TAG overrides must never retag a release alias.
    if not args.tag:
        for alias in image['aliases']:
            alias_ref = f"{image['repository']}:{alias}"
            print(f'Tagging local alias {alias_ref} -> {ref}', flush=True)
            run(['docker', 'tag', ref, alias_ref])
    if not args.tag and image.get('save', False):
        run([sys.executable, args.archive_tool, '--image', ref, '--id', args.id, '--tag', tag,
             '--output', str(Path(args.artifact_home) / args.id / tag)])


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, KeyError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
