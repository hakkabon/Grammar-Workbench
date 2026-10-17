#!/bin/bash
set -euo pipefail

SOURCE_DIR="${1:?usage: install-workbench-resources.sh SOURCE_DIRECTORY DESTINATION_DIRECTORY}"
DESTINATION_DIR="${2:?usage: install-workbench-resources.sh SOURCE_DIRECTORY DESTINATION_DIRECTORY}"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Workbench resource source directory does not exist: $SOURCE_DIR" >&2
    exit 2
fi
mkdir -p "$DESTINATION_DIR"

FOUND=0
for NAME in \
    GrammarWorkbench_GrammarWorkbenchCore.resources \
    GrammarWorkbench_GrammarWorkbenchCore.bundle \
    GrammarWorkbench_GrammarWorkbench.resources \
    GrammarWorkbench_GrammarWorkbench.bundle
do
    if [ -d "$SOURCE_DIR/$NAME" ]; then
        cp -R "$SOURCE_DIR/$NAME" "$DESTINATION_DIR/"
        FOUND=1
    fi
done

if [ "$FOUND" != "1" ]; then
    echo "No Grammar Workbench runtime resource directory was found in $SOURCE_DIR" >&2
    exit 1
fi
