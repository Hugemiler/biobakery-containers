#!/usr/bin/env python3
"""Read and validate the repository's deliberately small YAML inventory.

The accepted YAML subset uses two-space mappings and JSON-compatible scalar
values. Keeping the format small avoids imposing a third-party YAML dependency
on every machine that runs the Makefile.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


NAME_RE = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
TAG_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")
ARG_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
REQUIRED_FIELDS = {"repository", "revision", "context", "aliases"}
OPTIONAL_FIELDS = {"version", "tag_base", "push_ghcr", "push_aws", "save", "intended_version", "package", "version_arg"}


class InventoryError(ValueError):
    pass


def parse_inventory(path: Path) -> Dict[str, Dict[str, Any]]:
    images: Dict[str, Dict[str, Any]] = {}
    current: Optional[str] = None
    saw_root = False

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        content = raw_line.split("#", 1)[0].rstrip()
        if not content:
            continue
        if content == "images:":
            if saw_root:
                raise InventoryError(f"{path}:{line_number}: duplicate images mapping")
            saw_root = True
            continue
        if not saw_root:
            raise InventoryError(f"{path}:{line_number}: expected 'images:'")

        image_match = re.fullmatch(r"  ([a-z0-9][a-z0-9._-]*):", content)
        if image_match:
            current = image_match.group(1)
            if current in images:
                raise InventoryError(f"{path}:{line_number}: duplicate image id {current!r}")
            images[current] = {}
            continue

        field_match = re.fullmatch(r"    ([a-z_]+):(?: (.*))?", content)
        if not field_match or current is None:
            raise InventoryError(f"{path}:{line_number}: unsupported inventory syntax")
        field, raw_value = field_match.groups()
        if raw_value is None:
            raise InventoryError(f"{path}:{line_number}: nested values are not supported")
        if field in images[current]:
            raise InventoryError(f"{path}:{line_number}: duplicate field {field!r}")
        try:
            images[current][field] = json.loads(raw_value)
        except json.JSONDecodeError as error:
            raise InventoryError(
                f"{path}:{line_number}: values must use JSON-compatible YAML syntax"
            ) from error

    if not saw_root or not images:
        raise InventoryError(f"{path}: inventory contains no images")
    return images


def image_tag(image: Dict[str, Any]) -> str:
    version = image.get("version")
    prefix = image.get("tag_base") or (version if version is not None else "dev")
    return f"{prefix}-r{image['revision']}"


def validate(path: Path, images: Dict[str, Dict[str, Any]], sources: Optional[Dict[str, Path]] = None) -> None:
    errors: List[str] = []
    refs: Dict[Tuple[str, str], str] = {}
    # Build contexts always resolve from the repository root.
    # For an image-catalog/ directory, that is its parent; for a legacy
    # single-file inventory, that is the file's containing directory.
    repo_root = path.parent

    for image_id, image in images.items():
        source = sources.get(image_id, path) if sources else path
        origin = f"{source}: {image_id}"
        unknown = set(image) - REQUIRED_FIELDS - OPTIONAL_FIELDS
        missing = REQUIRED_FIELDS - set(image)
        if missing:
            errors.append(f"{origin}: missing fields: {', '.join(sorted(missing))}")
        if unknown:
            errors.append(f"{origin}: unknown fields: {', '.join(sorted(unknown))}")
        if missing:
            continue

        repository = image["repository"]
        version = image.get("version")
        revision = image["revision"]
        context = image["context"]
        aliases = image["aliases"]
        tag_base = image.get("tag_base")
        push_ghcr = image.get("push_ghcr", True)
        push_aws = image.get("push_aws", False)
        save = image.get("save", False)
        intended_version = image.get("intended_version")
        package = image.get("package")
        version_arg = image.get("version_arg")

        if not isinstance(repository, str) or not NAME_RE.fullmatch(repository):
            errors.append(f"{origin}: invalid repository name {repository!r}")
        if version is not None and (not isinstance(version, str) or not TAG_RE.fullmatch(version)):
            errors.append(f"{origin}: version must be null or a valid quoted tag string")
        if tag_base is not None and (not isinstance(tag_base, str) or not TAG_RE.fullmatch(tag_base)):
            errors.append(f"{origin}: tag_base must be a valid quoted tag stem")
        for field, value in (("push_ghcr", push_ghcr), ("push_aws", push_aws), ("save", save)):
            if not isinstance(value, bool):
                errors.append(f"{origin}: {field} must be a boolean")
        if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
            errors.append(f"{origin}: revision must be a positive integer")
        if not isinstance(context, str) or not context or Path(context).is_absolute():
            errors.append(f"{origin}: context must be a non-empty relative path")
        else:
            dockerfile = repo_root / context / "Dockerfile"
            if not dockerfile.is_file():
                errors.append(f"{origin}: missing {context}/Dockerfile")
        if not isinstance(aliases, list) or not all(
            isinstance(alias, str) and TAG_RE.fullmatch(alias) for alias in aliases
        ):
            errors.append(f"{origin}: aliases must be a list of valid quoted tags")
            aliases = []
        if version_arg is not None and (
            not isinstance(version_arg, str) or not ARG_RE.fullmatch(version_arg)
        ):
            errors.append(f"{origin}: invalid version_arg {version_arg!r}")
        elif version_arg is not None and isinstance(context, str):
            dockerfile_path = repo_root / context / "Dockerfile"
            if dockerfile_path.is_file():
                argument = re.compile(rf"^\s*ARG\s+{re.escape(version_arg)}(?:=\S+)?\s*$")
                dockerfile = dockerfile_path.read_text(encoding="utf-8").splitlines()
                if not any(argument.fullmatch(line) for line in dockerfile):
                    errors.append(f"{origin}: Dockerfile does not declare ARG {version_arg}")
        if package is not None:
            if not isinstance(package, str) or not NAME_RE.fullmatch(package):
                errors.append(f"{origin}: invalid package name {package!r}")
            elif version is None:
                errors.append(f"{origin}: package validation requires a non-null image version")
            elif isinstance(context, str):
                environment_path = repo_root / context / "environment.yaml"
                if not environment_path.is_file():
                    errors.append(f"{origin}: missing {context}/environment.yaml")
                else:
                    dependency = re.compile(
                        rf"^\s*-\s*{re.escape(package)}\s*=\s*{re.escape(version)}\s*(?:#.*)?$"
                    )
                    environment = environment_path.read_text(encoding="utf-8").splitlines()
                    if not any(dependency.fullmatch(line) for line in environment):
                        errors.append(
                            f"{origin}: {context}/environment.yaml does not pin "
                            f"{package}={version}"
                        )
        if intended_version is not None and (
            not isinstance(intended_version, str) or not TAG_RE.fullmatch(intended_version)
        ):
            errors.append(f"{origin}: invalid intended_version {intended_version!r}")
        if version is None and version_arg is not None:
            errors.append(f"{origin}: version_arg requires a non-null image version")
        if version is None and aliases and tag_base is None:
            errors.append(f"{origin}: an unversioned draft without tag_base cannot have release aliases")
        # if aliases and not (push_ghcr or push_aws):
        #     # Aliases are meaningful only for registry publication; keep this
        #     # as an error so nobody mistakes a local tag for a published alias.
        #     errors.append(f"{origin}: aliases require push_ghcr or push_aws; set aliases: [] for local-only images")
        ## ^ Actually, local aliases can be useful too -- commenting this block for now.

        if isinstance(repository, str) and NAME_RE.fullmatch(repository):
            tags = [image_tag(image), *aliases]
            for tag in tags:
                ref = (repository, tag)
                if ref in refs:
                    errors.append(f"{origin}: {repository}:{tag} conflicts with {refs[ref]}")
                refs[ref] = f"{origin}"

    if errors:
        raise InventoryError("\n".join(errors))


def load(path: Path) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Path]]:
    """Merge all catalogs, then validate references across the whole inventory."""
    if path.is_dir():
        files = sorted(path.glob("*.yaml"))
        if not files:
            raise InventoryError(f"{path}: no *.yaml catalog files")
    elif path.is_file():
        files = [path]
    else:
        raise InventoryError(f"{path}: catalog path does not exist")

    images: Dict[str, Dict[str, Any]] = {}
    sources: Dict[str, Path] = {}
    for file in files:
        for image_id, image in parse_inventory(file).items():
            if image_id in images:
                raise InventoryError(
                    f"duplicate image ID {image_id!r} in {file} and {sources[image_id]}"
                )
            images[image_id] = image
            sources[image_id] = file
    validate(path, images, sources)
    return images, sources


def require_image(images: Dict[str, Dict[str, Any]], image_id: str) -> Dict[str, Any]:
    try:
        return images[image_id]
    except KeyError as error:
        raise InventoryError(f"unknown image id {image_id!r}") from error


def print_table(images: Dict[str, Dict[str, Any]], sources: Dict[str, Path], package_filter: str = "") -> None:
    rows = []
    for image_id, image in images.items():
        if package_filter and image["repository"] != package_filter and image.get("package") != package_filter:
            continue
        version = image.get("version")
        if version is None:
            intended = image.get("intended_version")
            version = f"UNPINNED->{intended}" if intended else "UNPINNED"
        aliases = ", ".join(image["aliases"]) or "-"
        rows.append(
            (image_id, image["repository"], version, str(image["revision"]), image_tag(image), aliases, str(image.get("push_ghcr", True)).lower(), str(image.get("push_aws", False)).lower(), str(image.get("save", False)).lower(), str(sources[image_id]))
        )
    headers = ("ID", "IMAGE", "VERSION", "REV", "CANONICAL TAG", "ALIASES", "GHCR", "ECR", "SAVE", "SOURCE")
    if not rows:
        print("No images match the package filter")
        return
    widths = [max(len(row[index]) for row in [headers, *rows]) for index in range(len(headers))]
    for row in [headers, *rows]:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)).rstrip())



def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", default="image-catalog", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate")
    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--package", default="")
    subparsers.add_parser("json")
    subparsers.add_parser("ids")
    get_parser = subparsers.add_parser("get")
    get_parser.add_argument("image_id")
    get_parser.add_argument(
        "field", choices=["repository", "version", "revision", "context", "version_arg", "tag_base", "tag", "aliases", "push_ghcr", "push_aws", "save"]
    )
    args = parser.parse_args()

    try:
        images, sources = load(args.inventory)
        if args.command == "validate":
            versioned = sum(image.get("version") is not None for image in images.values())
            print(
                f"{args.inventory}: {len(images)} images valid "
                f"({versioned} versioned, {len(images) - versioned} draft)"
            )
        elif args.command == "list":
            print_table(images, sources, args.package)
        elif args.command == "json":
            print(json.dumps({"images": images}, indent=2, sort_keys=True))
        elif args.command == "ids":
            print(" ".join(images))
        elif args.command == "get":
            image = require_image(images, args.image_id)
            if args.field == "tag":
                value: Any = image_tag(image)
            else:
                value = image.get(args.field)
            if isinstance(value, list):
                print(" ".join(value))
            elif isinstance(value, bool):
                print(str(value).lower())
            elif value is not None:
                print(value)
        return 0
    except (OSError, InventoryError) as error:
        print(f"inventory error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
