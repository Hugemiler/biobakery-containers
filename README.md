# Biobakery Containers

Docker and apptainer build files.
Heavily inspired by https://github.com/tvatanen/microbiome_pipelines

## Building containers

The canonical image catalog is the collection of files under [`image-catalog/`](image-catalog/). The Makefile
derives its image targets, registry names, canonical tags, aliases, Docker build
contexts, and Apptainer sources from these files. The inventory describes
container images; it does not assume that an image corresponds to one Python,
Conda, or other software package.

### Inspecting and validating the inventory

Display the inventory as a table or validate it without building anything:

```sh
make images
make images PACKAGE=humann  # filter by repository or package
make catalog-json           # merged machine-readable catalog
make validate
```

Validation checks required fields, names and tag syntax, duplicate registry
references, build contexts and Dockerfiles, plus any optional `package` or
`version_arg` consistency checks an entry declares. It also rejects aliases
for unpublished images and conflicting aliases within one repository.

The inventory uses a deliberately restricted YAML subset so it can be parsed
with the Python standard library. Quote all strings, use JSON-style inline
lists such as `["4", "latest"]`, use integer revisions, and omit `version` for an unversioned draft.
Nested field values are not supported.

### Multi-file catalog layout

Each software family has a separate catalog file, such as
`image-catalog/humann.yaml` or `image-catalog/metaphlan.yaml`. Each file contains
its own `images:` mapping, using the **unchanged** per-image field schema.
All catalog entries are merged and globally validated: image IDs, canonical
references, and aliases must remain unique across files as appropriate.
`context` paths always resolve relative to the **repository root**, never to
individual YAML files. A single-file catalog can still be tested with
`python3 scripts/image_inventory.py --inventory /path/to/test.yaml validate`.
The `make catalog-json` command exports the globally validated catalog to stdout
for future read-only user interfaces.

### Inventory fields

Each key under `images` is a unique, stable inventory ID used for Make targets
and SIF filenames. The repository's normal image and its database-bundled image
are **different entries** but can have the same `repository`, `version`, and
`package`. Each entry points to its own directory and Dockerfile.

```yaml
images:
  humann-400a:
    repository: "humann"
    version: "4.0.0"
    revision: 1
    context: "humann/4.0.0a-dev/nodb"
    aliases: ["4", "4.0", "4.0.0a", "latest"]
    package: "humann"

  humann-400a-chocophlan:
    repository: "humann"
    version: "4.0.0"
    tag_base: "4.0.0-chocophlan-2019.01"
    revision: 1
    context: "humann/4.0.0a-dev/chocophlan-2019.01"
    aliases: []
    package: "humann"
    push_ghcr: false
    push_aws: false
    save: true
```

| Field | Required | Purpose |
| --- | --- | --- |
| `repository` | Yes | Docker image repository (for example `humann`). |
| `version` | No | Expected primary application version. For Conda images, `package` can validate its pin. |
| `revision` | Yes | Positive, independent packaging revision for this canonical image variant. |
| `context` | Yes | Build directory containing `Dockerfile` (and possibly `environment.yaml`). |
| `aliases` | Yes | Human-friendly mutable registry tags; `[]` for none. |
| `tag_base` | No | Canonical tag stem; defaults to `version`, or `dev` if there is no version. |
| `push_ghcr` | No | Publish canonical image and selected aliases to GHCR. Defaults to `true` for backward compatibility. |
| `push_aws` | No | Publish canonical image and selected aliases to AWS ECR. Defaults to `false`. |
| `save` | No | Automatically archive after successful canonical builds. Defaults to `false`. |
| `package` | No | Check `context/environment.yaml` contains the exact `package=version` pin. |
| `version_arg` | No | Pass `version` as the specified Dockerfile `ARG`. |
| `intended_version` | No | Informational version planned for an unversioned draft. |

The inventory deliberately supports only shallow mappings and JSON-compatible
scalar values; it is parsed with Python's standard library. Quote strings, use
integer revisions, and write lists inline. Version is **not** an image uniqueness
key. Within each repository, canonical tags and aliases must not collide.

### Canonical tags and aliases

Canonical tags are `<tag_base or version or dev>-r<revision>`. Examples:

```text
ghcr.io/klepac-ceraj-lab/humann:4.0.0-r1
ghcr.io/klepac-ceraj-lab/humann:4.0.0-chocophlan-2019.01-r1
```

The aliases `4`, `4.0`, and `latest` are independently chosen conveniences.
They are promoted **only** with `make push-aliases`, and they are allowed only
when at least one push flag is true. To avoid claiming release aliases for an unversioned draft,
set `aliases: []` unless that entry has an explicit `tag_base`.

### Building, saving, and publishing

```sh
make images            # print complete catalog
make images PACKAGE=metaphlan  # only MetaPhlAn
make catalog-json > catalog.json  # generated export, not authoritative
make validate          # check metadata and paths (requires all listed contexts)
make humann-400a        # build one normal image
make humann-400a-chocophlan   # build DB-bearing image, then save its archive
make build             # build all images, archive those with save: true
make archive-humann-400a-chocophlan  # archive an already-built canonical image
make push              # publish to selected GHCR and ECR destinations
make push-ghcr         # publish GHCR-eligible canonical images only
make push-aws          # publish ECR-eligible canonical images only
make push-aliases      # first push canonicals, then promote their aliases
```

`make build` never pushes. `make push` never builds. Setting `TAG=test` on a
single build is for local experiments and intentionally skips auto-archiving;
`push` and `archive` require canonical tags. `make archive` processes all entries
with `save: true` using already-built images.

By default, archive bundles are placed under
`dist/<inventory-id>/<canonical-tag>/` with:

```text
image.tar
image.tar.sha256
inspect.json
manifest.json
```

`image.tar` is generated with `docker image save` rather than `docker export`.
`image.tar.sha256` verifies the exact exported bytes, and `manifest.json`
records the image ID, platform, labels, archive checksum, and any available
registry digests. A local-only image normally has no registry `RepoDigest`.
Use `ARTIFACT_HOME=/path` to choose another output location.

For DB-bearing Dockerfiles, use versioned HTTPS archives, verify their
**input** checksum inside the Docker build, and place the data at a documented
path (for example `/Databases`). Container archive checksums are a separate
verification of the **output**. The Makefile does not interpret database URLs:
those details remain plainly visible in each Dockerfile.

### GHCR / ECR publication policy

Two independent optional boolean fields control registry pushes:

```yaml
push_ghcr: true
push_aws: false
save: true
```

All four combinations are supported: GHCR only, ECR only, both, or neither.
`save` is independent and still produces the Docker archive and provenance bundle.
An image with both push flags false should use `aliases: []`.

`make push` handles the selected registries without rebuilding. The local image
reference is a local `repository:tag` image; for either registry destination,
Make tags the same local image before pushing. `make push-aliases` promotes
aliases separately in each selected registry. `make push-ghcr` and
`make push-aws` limit publishing to one destination.

For GHCR, set `GHCR_HANDLE`, `GHCR_USER`, and `GHCR_PAT`. For ECR, set
`ECR_REPO` to the registry namespace/prefix, e.g.
`123456789012.dkr.ecr.us-east-1.amazonaws.com/biobakery`, plus `AWS_REGION`
and optionally `AWS_PROFILE`. The ECR repositories under that prefix must
already exist; this Makefile does not create them. An ECR push uses the Docker
registry protocol, not an S3 upload.

### Apptainer

```sh
make apptainer-metaphlan-425
make apptainer-metaphlan-425-db
make apptainer
```

Apptainer uses `docker-daemon://` for every entry, so it does not depend
on which registry (if any) the image was published to. The canonical Docker
image must first be built locally. SIFs are placed under `CONTAINER_HOME`
(default `$HOME/containers`) and named after inventory IDs.

### Limitations

The catalog's `package` sanity check reads environment YAML text; it is not
an end-to-end runtime version test, nor does it verify a source patch or
actually test whether an embedded database works. A Docker build and an
application-level smoke test remain necessary. Versioned image tags can be
rebuilt, so the `image.tar.sha256` identifies the precise distributed file.

### Manual Docker builds

Docker containers are managed by the docker daemon,
rather than having absolute paths.
Assuming the docker daemon is running,

1. Navigate to this repo
2. Build container
3. (optional) Upload to registry

For example,

```
$ docker buildx -t my-biobakery-build:v0.1 .
$ docker tag my-biobakery-build:v0.1 kescobo/my-biobakery-build:v0.1
$ docker push my-biobakery-build:v0.1

```

Here, `my-biobakery-build:v0.1` has 2 parts, the container name (eg `my-biobakery-build`)
and the tag (`v0.1`).
If you want to build with additional tags, you can, and they will be almost instantaneous.

On Dockerhub, the tags have 2 parts themselves, eg `v4-v0.1`,
where the first part `v4` is the biobakery tool versions for humann/metaphlan
and the second part `v0.1` is the container version for this repo.
At some point I should probably have different branches for managing
the biobakery versions, but that's a problem for another day.

To test locally, use eg

```
$ docker run -it --rm my-humann-build humann --help
```

### Apptainer (formerly Singularity)

Apptainer containers are contained in `.sif` files,
which can be nice, because they're portable.
Eg, you can build the container locally, and then put it on other systems.

1. navigate to the root of this repository
2. build

```sh
$ sudo singularity build $CONTAINER_PATH/kneaddata.sif $REPO_PATH/apptainer_files/kneaddata.def
```

where `CONTAINER_PATH` is where you want the container to live,
and `REPO_PATH` is the path to this repository.

## Running containers

To run a biobakery program, use `docker run` or `singularity exec`. For example, to run `humann`,

```sh
$ docker run -it --rm my-biobakery-build humann --version
```

or

```sh
$ singularity exec $CONTAINER_PATH/humann.sif humann $ARGS...
```

But this is pretty annoying, so you can also create and shell script
and alias or symlink it to something in your `$PATH`, for example`/usr/local/bin/humann`:

```sh
#!/bin/sh

singularity exec /murray/containers/humann.sif humann "$@"
```

then `alias humann=/usr/local/bin/humann` or
`ln -s /usr/local/bin/humann ~/.local/human`


Mounting additional files systems

By default, singularity only mounts your working directory and its parents.
If you need to mount other file systems, use `--bind`. 

Eg. if you're running the container from your home folder,
but need to include `/some_filesystem`, run

```sh
$ singularity exec --bind /some_filesystem:/some_filesystem $CONTAINER_PATH/humann.sif humann $ARGS...
```

### Running `metaphlan`

Note - if you try to run metaphlan without specifying a location for the bowtie2 database,
it will try to download it and fail.
To avoid this, download the database to some location,
and then always run metaphlan with `--bowtie2db` specified.

For example,

```sh
$ singularity exec $CONTAINER_PATH/metaphlan.sif metaphlan --install --bowtie2db $BOWTIE2_DB
```

where `$BOWTIE2_DB` is the location that you want the database to live.
Once this is done, run `metaphlan` with

```sh
$ singularity exec $CONTAINER_PATH/metaphlan.sif metaphlan sample1.fastq.gz sample1_profile.tsv --bowtie2db $BOWTIE2_DB
```

To simplify this, you can create a shell script, for example on `hopper`:

```sh
#!/bin/sh

singularity exec --bind $PWD:$PWD --bind /murray:/murray /murray/containers/metaphlan.sif metaphlan "$@" --bowtie2db /murray/databases/metaphlan
```

### Local image identity and independent registries

`make build` always produces `repository:<canonical-tag>` in the local Docker daemon.
`REPO_TYPE` is not used. `make push-ghcr` and `make push-aws` retag the same
local image and push only entries enabled by `push_ghcr` or `push_aws`.
`make push` invokes both. `make push-aliases` promotes configured aliases
independently in each enabled registry. Neither publishing nor archiving rebuilds
images. `make archive` and `make apptainer` also use the local image.

**Known verification boundary:** Docker builds, uploads to authenticated registries,
and Apptainer conversion must be exercised in an environment with those services.


### Offline catalog regression tests

Run `python3 tests/test_catalog.py` to check multi-file loading, CLI commands,
canonical reference collisions, and duplicate IDs using temporary Dockerfile
fixtures. This test does not build Docker images or contact GHCR/ECR.
