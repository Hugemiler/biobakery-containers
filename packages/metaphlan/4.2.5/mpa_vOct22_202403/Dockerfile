# The build-stage image:
FROM mambaorg/micromamba:2.9.0

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

ENV PATH="/opt/conda/bin:$PATH"

# Database commands
## Change to root to make changes on /
USER root
## Copy database tarball
COPY --from=databases \
    /metaphlan/mpa_vOct22_202403.tar.gz \
    /tmp/database.tar.gz
## Extract database tarball and change permissions, remove original after
RUN mkdir -p /Databases/metaphlan/mpa_vOct22_202403 \
 && tar -xzf /tmp/database.tar.gz -C /Databases/metaphlan/mpa_vOct22_202403 \
 && chmod -R a+rX /Databases/metaphlan/mpa_vOct22_202403 \
 && rm /tmp/database.tar.gz
## Restore the original runtime user
USER $MAMBA_USER

# Post-compilation commands
ENV PATH="/opt/conda/bin:$PATH"
