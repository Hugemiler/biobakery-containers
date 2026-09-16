#!/bin/bash
# Wrapper for MetaPhlAn 4

# Set default container directory if CONTAINER_HOME is not defined
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/containers}"
DATABASE_HOME="${DATABASE_HOME:-$HOME/Databases}"
PROCESSING_HOME="${PROCESSING_HOME:-$HOME/Processing}"

exec apptainer run --bind "$DATABASE_HOME":/databases --bind "$PROCESSING_HOME":/Processing "$CONTAINER_HOME/metaphlan-4.sif" "$@"