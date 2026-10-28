# The build-stage image:
FROM mambaorg/micromamba:2.9.0

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

# Activate the base environment for build commands and expose it at runtime.
ARG MAMBA_DOCKERFILE_ACTIVATE=1
ENV PATH="/opt/conda/bin:$PATH"

# Git pull stage:
ENV HUMANN_COMMIT="9cb1a82"

RUN git clone https://github.com/biobakery/humann.git /tmp/humann \
 && cd /tmp/humann \
 && git checkout "$HUMANN_COMMIT" \
 && python -m pip install --no-deps --force-reinstall . \
 && rm -rf /tmp/humann

# Database commands
## Change to root to make changes on /
USER root
## Copy database tarball
COPY --from=databases \
    /humann/chocophlan-v4-201901.tar.gz \
    /tmp/database.tar.gz
## Extract database tarball and change permissions, remove original after
RUN mkdir -p /Databases/humann/chocophlan-v4-201901 \
 && tar -xzf /tmp/database.tar.gz -C /Databases/humann/chocophlan-v4-201901 \
 && chmod -R a+rX /Databases/humann/chocophlan-v4-201901 \
 && rm /tmp/database.tar.gz
## Restore the original runtime user
USER $MAMBA_USER
