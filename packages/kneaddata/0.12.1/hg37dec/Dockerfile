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
    /kneaddata/hg37dec.tar.gz \
    /tmp/database.tar.gz
## Extract database tarball and change permissions, remove original after
RUN mkdir -p /Databases/kneaddata \
 && tar -xzf /tmp/database.tar.gz -C /Databases/kneaddata \
 && chmod -R a+rX /Databases/kneaddata \
 && rm /tmp/database.tar.gz
## Restore the original runtime user
USER $MAMBA_USER

# Post-compilation commands
RUN ln -f /opt/conda/share/trimmomatic/trimmomatic.jar /opt/conda/bin/trimmomatic
ENV PATH="/opt/conda/bin:$PATH"
