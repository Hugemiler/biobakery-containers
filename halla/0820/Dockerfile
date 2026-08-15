# The build-stage image:
FROM mambaorg/micromamba:1.4.3

# Put files in as the micromamba user to avoid perms issues
COPY --chown=$MAMBA_USER:$MAMBA_USER environment.yaml /tmp/env.yaml

# Create everything in the *base* env for simplicity
RUN micromamba install -y -n base -f /tmp/env.yaml && \
    micromamba clean -a -y

# (Optional) be explicit about R_HOME; conda's r-base provides R in PATH anyway
ENV R_HOME=/opt/conda/lib/R
# Some HAllA installs poke the old sklearn shim; this keeps things happy just in case
ENV SKLEARN_ALLOW_DEPRECATED_SKLEARN_PACKAGE_INSTALL=True

# Upgrade pip and install HAllA without re-resolving deps we installed with conda
RUN micromamba run -n base python -m pip install --no-cache-dir --upgrade pip && \
    micromamba run -n base python -m pip install --no-cache-dir --no-deps HAllA

# Install required R packages that HAllA calls internally
RUN micromamba run -n base Rscript -e "install.packages(c('eva','XICOR'), repos='https://cloud.r-project.org')"

ENV PATH="/opt/conda/bin:$PATH"

# Default working dir and entrypoint
WORKDIR /work
ENTRYPOINT ["micromamba", "run", "-n", "base", "halla"]
CMD ["--help"]