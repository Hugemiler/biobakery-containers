# Base image
FROM ubuntu:24.04

# Set working directory
# WORKDIR /app

# Switch to root user to install packages
USER root

# Install dependencies for SRA tools
RUN apt-get update && \
    apt-get install -y wget tar && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and install SRA tools
RUN wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-ubuntu64.tar.gz && \
    tar -xvzf sratoolkit.current-ubuntu64.tar.gz && \
    rm sratoolkit.current-ubuntu64.tar.gz && \
    mv sratoolkit.*/ /opt/sratools

# Add SRA tools to PATH
ENV PATH="/opt/sratools/bin:$PATH"

# Intentionally track the current SRA Toolkit release.
RUN /opt/sratools/bin/fasterq-dump --version
