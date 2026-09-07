#!/usr/bin/env bash

# Run Pipeline on the host without installing it. The image supplies matching
# Pipeline and Just binaries; the host supplies the tools used by build recipes.
unalias pipeline 2>/dev/null || :
pipeline() (
    set -eu

    if ! command -v podman >/dev/null 2>&1; then
        echo "pipeline: podman is required" >&2
        exit 127
    fi

    pipeline_image=${PIPELINE_IMAGE:-ghcr.io/noobping/pipeline:continuous}
    pipeline_pull=${PIPELINE_PULL:-missing}
    pipeline_runtime=$(mktemp -d "${TMPDIR:-/tmp}/pipeline.XXXXXXXXXX")
    pipeline_container=

    pipeline_cleanup() {
        if [[ -n "${pipeline_container:-}" ]]; then
            command podman rm --force "$pipeline_container" >/dev/null 2>&1 || :
        fi
        command rm -rf -- "$pipeline_runtime"
    }
    trap pipeline_cleanup EXIT

    mkdir "$pipeline_runtime/just-bin"
    pipeline_container=$(
        command podman create \
            --pull="$pipeline_pull" \
            --entrypoint /bin/true \
            "$pipeline_image"
    )
    command podman cp \
        "$pipeline_container:/usr/local/bin/pipeline" \
        "$pipeline_runtime/pipeline"
    command podman cp \
        "$pipeline_container:/usr/local/bin/just" \
        "$pipeline_runtime/just-bin/just"
    command podman rm "$pipeline_container" >/dev/null
    pipeline_container=
    chmod 0700 "$pipeline_runtime/pipeline" "$pipeline_runtime/just-bin/just"

    case "${1:-}" in
        add|install)
            "$pipeline_runtime/pipeline" "$@"
            ;;
        *)
            PATH="$pipeline_runtime/just-bin:$PATH" \
                "$pipeline_runtime/pipeline" "$@"
            ;;
    esac
)
