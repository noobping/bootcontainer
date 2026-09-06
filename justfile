check-whitespace:
    #!/usr/bin/env bash
    set -euo pipefail
    git diff --check
    git diff --cached --check
    git log -1 --check --format=

check-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue
        first_line=
        IFS= read -r first_line < "$file" || true
        if [[ "$first_line" == '#!'*bash* || "$first_line" == '#!'*'/sh'* ]]; then
            if ! bash -n "$file"; then
                failed=1
            fi
        fi
    done < <(git ls-files -z)
    exit "$failed"

# Build an x86_64 Workstation installer with its bootc image embedded.
offline-workstation:
    #!/usr/bin/env bash
    set -euo pipefail

    repo='{{justfile_directory()}}'
    namespace="${IMAGE_NAMESPACE:-localhost:5000/noobping}"
    tls_verify="${REGISTRY_TLS_VERIFY:-false}"
    isolation="${BUILDAH_ISOLATION:-chroot}"
    tmpdir="${TMPDIR:-/tmp}"
    source_url="$(git -C "$repo" config --get remote.origin.url || printf '%s' "$repo")"
    image_arch=amd64
    coreos_arch=x86_64

    registry="${namespace%%/*}"
    case "$registry" in
        localhost:*|127.0.0.1:*) ;;
        *)
            echo "offline requires a local IMAGE_NAMESPACE; got $namespace" >&2
            exit 1
            ;;
    esac

    registry_host="${registry%:*}"
    registry_port="${registry##*:}"
    registry_container="${LOCAL_REGISTRY_CONTAINER:-pipeline-registry}"
    registry_volume="${LOCAL_REGISTRY_VOLUME:-pipeline-registry}"

    run_podman() {
        if command -v podman >/dev/null 2>&1; then
            podman "$@"
        elif command -v flatpak-spawn >/dev/null 2>&1; then
            flatpak-spawn --host podman "$@"
        else
            echo "podman is required to build the offline image" >&2
            exit 1
        fi
    }

    run_buildah() {
        if command -v buildah >/dev/null 2>&1; then
            TMPDIR="$tmpdir" buildah "$@"
        elif command -v flatpak-spawn >/dev/null 2>&1; then
            flatpak-spawn --host env TMPDIR="$tmpdir" buildah "$@"
        else
            echo "buildah is required to build the offline image" >&2
            exit 1
        fi
    }

    run_yq() {
        if command -v yq >/dev/null 2>&1; then
            yq "$@"
        elif command -v flatpak-spawn >/dev/null 2>&1 \
            && flatpak-spawn --host sh -lc 'command -v yq >/dev/null 2>&1'; then
            flatpak-spawn --host yq "$@"
        else
            run_podman run --rm \
                -v "$repo:/work:Z" -w /work \
                docker.io/mikefarah/yq:4.45.1 "$@"
        fi
    }

    write_iso_with_archive() {
        local input_host="$1"
        local output_host="$2"
        local archive_host="$3"
        local input_container="$4"
        local output_container="$5"
        local archive_container="$6"

        if command -v xorriso >/dev/null 2>&1; then
            xorriso \
                -indev "$input_host" \
                -outdev "$output_host" \
                -boot_image any replay \
                -map "$archive_host" /bootc
        elif command -v flatpak-spawn >/dev/null 2>&1 \
            && flatpak-spawn --host sh -lc 'command -v xorriso >/dev/null 2>&1'; then
            flatpak-spawn --host xorriso \
                -indev "$input_host" \
                -outdev "$output_host" \
                -boot_image any replay \
                -map "$archive_host" /bootc
        else
            run_podman run --rm \
                -v "$repo:/work:Z" -w /work \
                -v "$work_dir:/work-tmp:Z" \
                registry.fedoraproject.org/fedora:latest \
                sh -lc 'dnf -y -q install xorriso >/dev/null; exec xorriso "$@"' \
                sh \
                -indev "$input_container" \
                -outdev "$output_container" \
                -boot_image any replay \
                -map "$archive_container" /bootc
        fi
    }

    registry_ready() {
        if command -v curl >/dev/null 2>&1; then
            curl -fsS "http://${registry}/v2/" >/dev/null 2>&1
            return $?
        fi
        if command -v wget >/dev/null 2>&1; then
            wget -q -O /dev/null "http://${registry}/v2/" >/dev/null 2>&1
            return $?
        fi
        (echo >/dev/tcp/"$registry_host"/"$registry_port") >/dev/null 2>&1
    }

    ensure_registry() {
        if registry_ready; then
            printf 'Local registry already running at %s\n' "$registry"
            return 0
        fi

        if run_podman container exists "$registry_container"; then
            run_podman start "$registry_container" >/dev/null
        else
            run_podman volume exists "$registry_volume" >/dev/null 2>&1 \
                || run_podman volume create "$registry_volume" >/dev/null
            run_podman run -d \
                --name "$registry_container" \
                -p "127.0.0.1:${registry_port}:5000" \
                -v "${registry_volume}:/var/lib/registry:Z" \
                docker.io/library/registry:2 >/dev/null
        fi

        for _ in {1..30}; do
            if registry_ready; then
                printf 'Local registry running at %s\n' "$registry"
                return 0
            fi
            sleep 1
        done

        echo "local registry did not become ready at $registry" >&2
        run_podman logs "$registry_container" >&2 || true
        exit 1
    }

    render_butane() {
        local input="$1"
        local output="$2"
        local bootc_image="${3:-workstation}"

        sed \
            -e "s#__IMAGE_NAMESPACE__#${namespace}#g" \
            -e "s#__BOOTC_IMAGE__#${bootc_image}#g" \
            -e "s#ghcr.io/noobping#${namespace}#g" \
            "$input" > "$output"
    }

    build_image() {
        local context="$1"
        local image="$2"
        shift 2

        run_buildah bud \
            --pull=always \
            --arch "$image_arch" \
            --isolation="$isolation" \
            -t "$image" \
            --label "org.opencontainers.image.source=${source_url}" \
            "$@" \
            "$context"

        run_buildah push --tls-verify="$tls_verify" "$image" "docker://$image"
        run_buildah rmi "$image" >/dev/null 2>&1 || true
        run_buildah prune -f >/dev/null 2>&1 || true
    }

    ensure_registry

    cd "$repo"
    mkdir -p dist/butane dist/ign dist/iso

    build_image images/ips "${namespace}/ips:${image_arch}"
    build_image images/workstation "${namespace}/workstation:${image_arch}" \
        --tls-verify="$tls_verify" \
        --build-arg "IMAGE_NAMESPACE=${namespace}" \
        --build-arg "TAG=${image_arch}"

    run_podman pull --tls-verify="$tls_verify" "${namespace}/workstation:${image_arch}"
    run_podman tag "${namespace}/workstation:${image_arch}" "${namespace}/workstation:latest"
    run_podman push --tls-verify="$tls_verify" \
        "${namespace}/workstation:latest" \
        "docker://${namespace}/workstation:latest"

    # Keep the staging directory under the checkout so host-side Podman can see
    # it even when Just is running inside a Flatpak sandbox with a private /tmp.
    work_dir="$(mktemp -d "$repo/dist/.pipeline-offline.XXXXXX")"
    trap 'rm -rf -- "$work_dir"' EXIT

    archive_dir="$work_dir/bootc"
    archive_dir_container=/work-tmp/bootc
    mkdir -p "$archive_dir"
    archive="$archive_dir/workstation.ociarchive"

    run_podman save --format oci-archive -o "$archive" \
        "${namespace}/workstation:latest"
    sha256sum "$archive" | tee "${archive}.sha256"

    run_yq ea '. as $item ireduce ({}; . *+ $item)' \
        butane/base.yml \
        butane/setup.yml \
        > dist/butane/setup.bu
    render_butane dist/butane/setup.bu dist/butane/setup.rendered.bu

    run_podman run --rm \
        -v "$repo:/work:Z" -w /work \
        quay.io/coreos/butane:release \
        --pretty --strict --files-dir . dist/butane/setup.rendered.bu \
        > dist/ign/setup.ign

    run_yq ea '. as $item ireduce ({}; . *+ $item)' \
        butane/base.yml \
        butane/updates.yml \
        butane/workstation.yml \
        > dist/butane/workstation.bu
    render_butane \
        dist/butane/workstation.bu \
        dist/butane/workstation.rendered.bu

    run_podman run --rm \
        -v "$repo:/work:Z" -w /work \
        quay.io/coreos/butane:release \
        --pretty --strict --files-dir . dist/butane/workstation.rendered.bu \
        > dist/ign/workstation.ign

    if ! ls -1 fedora-coreos-*-live-iso."${coreos_arch}".iso >/dev/null 2>&1; then
        run_podman run --rm \
            --userns=keep-id \
            --user "$(id -u):$(id -g)" \
            -v "$repo:/work:Z" -w /work \
            quay.io/coreos/coreos-installer:release \
            download -s stable -a "$coreos_arch" -p metal -f iso -C /work --decompress
    fi

    base_iso="$(ls -1 fedora-coreos-*-live-iso."${coreos_arch}".iso | tail -n1)"
    out_iso="dist/iso/workstation-offline-${coreos_arch}.iso"
    out_iso_container="/work/${out_iso}"
    custom_iso="${work_dir}/workstation-custom.iso"
    custom_iso_container=/work-tmp/workstation-custom.iso
    rm -f "$out_iso" "${out_iso}.sha256"

    run_podman run --rm \
        --userns=keep-id \
        --user "$(id -u):$(id -g)" \
        -v "$repo:/work:Z" -w /work \
        -v "$work_dir:/work-tmp:Z" \
        quay.io/coreos/coreos-installer:release \
        iso customize \
            --live-ignition dist/ign/setup.ign \
            --dest-ignition dist/ign/workstation.ign \
            --pre-install butane/bin/detect-device \
            -o "$custom_iso_container" \
            "$base_iso"

    write_iso_with_archive \
        "$custom_iso" \
        "$out_iso" \
        "$archive_dir" \
        "$custom_iso_container" \
        "$out_iso_container" \
        "$archive_dir_container"

    sha256sum "$out_iso" | tee "${out_iso}.sha256"
