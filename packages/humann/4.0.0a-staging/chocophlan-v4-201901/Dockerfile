# The build-stage image:
FROM mambaorg/micromamba:2.9.0

# Micromaba install core
## Add env.yaml to build
COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
## Run micromaba install
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

# Database commands
## Change to root to make changes on /
USER root
## Copy database tarball
COPY --from=databases \
    /humann/chocophlan-v4-201901.tar.gz \
    /tmp/database.tar.gz
## Extract database tarball and change permissions, remove original after
RUN mkdir -p /Databases/humann \
 && tar -xzf /tmp/database.tar.gz -C /Databases/humann \
 && chmod -R a+rX /Databases/humann \
 && rm /tmp/database.tar.gz
## Restore the original runtime user
USER $MAMBA_USER

# Post-compilation commands
ENV PATH="/opt/conda/bin:$PATH"