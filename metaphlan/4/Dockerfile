# The build-stage image:
FROM mambaorg/micromamba:1.4.3

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

ENV PATH="/opt/conda/bin:$PATH"