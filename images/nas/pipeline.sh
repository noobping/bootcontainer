alias pipeline='podman run --rm \
    --pull=newer \
    --userns=keep-id \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    -v "$PWD:/work:Z" \
    -w /work \
    ghcr.io/noobping/pipeline:continuous'
