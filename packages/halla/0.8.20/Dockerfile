FROM mambaorg/micromamba:2.9.0

COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml

RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean --all --yes

RUN micromamba run -n base python -m pip install \
    --no-cache-dir --no-deps halla

RUN micromamba run -n base Rscript -e \
    "install.packages(c('eva','XICOR'), repos='https://cloud.r-project.org')"

# Make the completed conda environment available directly at runtime
ENV PATH="/opt/conda/bin:${PATH}"
ENV R_HOME="/opt/conda/lib/R"

WORKDIR /work

ENTRYPOINT ["/opt/conda/bin/halla"]
CMD ["--help"]