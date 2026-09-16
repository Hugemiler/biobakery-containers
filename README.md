# Biobakery Containers

Docker and apptainer build files.
Heavily inspired by https://github.com/tvatanen/microbiome_pipelines

## Building containers

The canonical image inventory is [`images.yaml`](images.yaml). The Makefile
derives its image targets, registry names, canonical tags, aliases, Docker build
contexts, and Apptainer sources from this file. The inventory describes
container images; it does not assume that an image corresponds to one Python,
Conda, or other software package.

### Inspecting and validating the inventory

Display the inventory as a table or validate it without building anything:

```sh
make images
make validate
```

Validation checks required fields, names and tag syntax, duplicate registry
references, build contexts and Dockerfiles, plus any optional `package` or
`version_arg` consistency checks an entry declares. It also rejects aliases on
unversioned images and conflicting aliases within one repository.

The inventory uses a deliberately restricted YAML subset so it can be parsed
with the Python standard library. Quote all strings, use JSON-style inline
lists such as `["4", "latest"]`, use integer revisions, and use `null` for an
unversioned draft. Nested field values are not supported.

### Inventory fields

Each key directly below `images` is a stable inventory ID:

```yaml
images:
  metaphlan-4:
    repository: "metaphlan"
    version: "4.2.2"
    package: "metaphlan"
    revision: 1
    context: "metaphlan/4"
    aliases: ["4"]
```

The ID is used for the individual Make target and Apptainer filename. In this
example, it provides `make metaphlan-4`, `make apptainer-metaphlan-4`, and
`metaphlan-4.sif`. It does not become the registry repository name.

| Field | Required | Purpose |
| --- | --- | --- |
| `repository` | Yes | Container registry repository. Multiple versions of the same software share this value, so both MetaPhlAn entries publish under `metaphlan`. |
| `version` | Yes | Release version of the container image as a quoted string. It may mirror an application version, represent a multi-tool bundle, use calendar versioning, or follow another project-defined scheme. Use `null` for an unversioned draft. |
| `revision` | Yes | Positive packaging revision. Increment it when the container recipe changes without creating a new image release. |
| `context` | Yes | Repository-relative Docker build context containing a `Dockerfile`. |
| `aliases` | Yes | Mutable tags promoted only by `make push-aliases`; use `[]` when none are wanted. |
| `package` | No | Optional check for a single-application Conda image. The validator requires `context/environment.yaml` to contain an exact `package=version` pin. It is not appropriate or required for every image. |
| `version_arg` | No | Optional Dockerfile `ARG` to which Make passes the image version, used when that version is also a build input. |
| `intended_version` | No | Planned image version for an unversioned draft. It is informational and does not affect the generated tag. |

`package` and `version_arg` are independent, optional mechanisms. They are not
the source of an image's identity and should only be declared when their checks
accurately describe the build. For example:

```yaml
# Conda-backed: environment.yaml must contain metaphlan=4.2.2
version: "4.2.2"
package: "metaphlan"

# Docker-argument-backed: Dockerfile must declare ARG OMIXER_VERSION
version: "1.1"
version_arg: "OMIXER_VERSION"

# Toolbox bundle: no single package owns the image version
version: "2026.08"
```

An image may contain any number of packages, compiled programs, operating-system
tools, or other components without declaring a primary package. Those component
versions belong in the relevant environment, lock file, Dockerfile, or component
manifest. The inventory version describes the released image as a whole.

### Tags and aliases

Canonical tags use `<software-version>-r<packaging-revision>`:

```text
ghcr.io/klepac-ceraj-lab/metaphlan:4.2.2-r1
```

The image version and packaging revision together identify the build. For a
single-application image, the image version may match its application. For a
bundle such as `pipeline-utils`, it can instead be a toolbox release such as
`2026.08`. If a recipe changes without changing the image release, increment
`revision`. An image with `version: null` receives a draft tag such as `dev-r1`
and cannot declare release aliases.

Aliases are intentionally mutable convenience references. A complete alias set
for the currently recommended KneadData release could be:

```yaml
aliases: ["0.12.1", "0.12", "latest"]
```

These tags mean:

- `0.12.1`: newest packaging revision for KneadData 0.12.1.
- `0.12`: optional moving alias for the 0.12 release line.
- `latest`: recommended/default KneadData release.
- `stable`: optional alternative when a deliberately selected stable channel is useful.

Only one entry within a repository may own an alias such as `latest` or
`stable`. Neither is assigned automatically. The tag `release` is discouraged
because all canonical version tags represent releases and its moving meaning is
otherwise unclear. Major, minor, and patch aliases are optional conventions,
not assumptions made by the Makefile or validator.

### Building and publishing

Build every image or one inventory entry with:

```sh
make build
make metaphlan-4
```

Set `TAG` only for a local experimental build override. Canonical tags are used
by default:

```sh
make metaphlan-4 TAG=test
```

`make push` deliberately rejects `TAG` overrides and always pushes the canonical
inventory references. Before pushing, it verifies that every exact canonical
tag exists locally and reports the corresponding build target when one is
missing. Experimental tags therefore cannot be published accidentally through
the inventory workflow.

`make build` does not publish, and `make push` does not build. After building
and setting the registry credentials in your environment, choose whether to
publish only canonical tags or canonical tags plus aliases:

```sh
make build
make push          # canonical tags only
make push-aliases  # canonical tags, followed by configured aliases
```

`push-aliases` depends on `push`, then verifies each canonical image in the
configured registry and uses Docker Buildx to create aliases directly from that
remote manifest. It never pulls an image during promotion, so it cannot replace
a newly built local canonical tag with an older remote image. The dependency
guarantees that the current local canonical images are published before any
mutable tag changes. After remote promotion, the corresponding local aliases
are pointed at that already-verified local canonical image. It rejects `TAG`
overrides so experimental builds cannot accidentally be promoted. No `latest`
tag is produced unless it appears explicitly in the inventory.

Build Apptainer files from the canonical remote tags with:

```sh
make apptainer
make apptainer-metaphlan-4
```

The files are written under `CONTAINER_HOME` (default: `$HOME/containers`) and
retain their inventory IDs, such as `metaphlan-4.sif`.

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
