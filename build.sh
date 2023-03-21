#!/usr/bin/env bash

set -e
set -x
set -o pipefail

# Make sure to use project tooling
PATH="$(pwd)/tmp/bin:${PATH}"

for JSONNET_FILE in $(ls -1 *.jsonnet); do
    MANIFEST_PATH=manifests-"${JSONNET_FILE%%.*}"

    echo "Building ${JSONNET_FILE} on ${MANIFEST_PATH}"

    # Make sure to start with a clean 'manifests' dir
    rm -rf ${MANIFEST_PATH}
    mkdir -p ${MANIFEST_PATH}/setup

    # Calling gojsontoyaml is optional, but we would like to generate yaml, not json
    jsonnet -J vendor -m ${MANIFEST_PATH} "${JSONNET_FILE}" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}

    # Make sure to remove json files
    find ${MANIFEST_PATH} -type f ! -name '*.yaml' -delete
    cd ${MANIFEST_PATH}; kustomize init --autodetect --recursive; cd ..
done
