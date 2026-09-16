#!/bin/bash
# Wrapper for MetaPhlAn 3

# Set default container directory if CONTAINER_HOME is not defined
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/containers}"
DATABASE_HOME="${DATABASE_HOME:-$HOME/Databases}"

exec apptainer exec --bind "$DATABASE_HOME":/databases "$CONTAINER_HOME/metaphlan-3.sif" "$@"