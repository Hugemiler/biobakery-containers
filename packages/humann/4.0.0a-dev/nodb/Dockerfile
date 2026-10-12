# The build-stage image:
FROM mambaorg/micromamba:2.9.0

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

ENV PATH="/opt/conda/bin:$PATH"

ENV HUMANN_COMMIT="9cb1a82"

RUN git clone https://github.com/biobakery/humann.git /tmp/humann \
 && cd /tmp/humann \
 && git checkout "$HUMANN_COMMIT" \
 && pip install --no-deps --force-reinstall . \
 && rm -rf /tmp/humann