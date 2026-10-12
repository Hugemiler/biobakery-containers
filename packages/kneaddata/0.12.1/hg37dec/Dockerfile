# The build-stage image:
FROM mambaorg/micromamba:2.9.0

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

ARG BUILD_LOCAL_DATABASE_SOURCE
COPY ${BUILD_LOCAL_DATABASE_SOURCE}/kneaddata/hg37dec.tar.gz /tmp/database.tar.gz
RUN mkdir -p /Databases/kneaddata \
 && tar -xzf /tmp/database.tar.gz -C /Databases/kneaddata/ \
 && rm /tmp/database.tar.gz

RUN ln -f /opt/conda/share/trimmomatic/trimmomatic.jar /opt/conda/bin/trimmomatic

ENV PATH="/opt/conda/bin:$PATH"
