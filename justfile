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

# Build every stable image and all offline installer artifacts for this host.
offline: (_offline "all")

# Build only the Workstation offline installer.
offline-workstation: (_offline "workstation")

[private]
_offline target:
    #!/usr/bin/env bash
    set -euo pipefail

    repo='{{ justfile_directory() }}'
    target='{{ target }}'
    namespace="${IMAGE_NAMESPACE:-localhost:5000/noobping}"
    tls_verify="${REGISTRY_TLS_VERIFY:-false}"
    isolation="${BUILDAH_ISOLATION:-chroot}"
    tmpdir="${TMPDIR:-/tmp}"
    source_url="$(git -C "$repo" config --get remote.origin.url || printf '%s' "$repo")"

    case "$target" in
        all|workstation) ;;
        *)
            echo "unsupported offline target: $target" >&2
            exit 2
            ;;
    esac

    case "$(uname -m)" in
        x86_64)
            image_arch=amd64
            coreos_arch=x86_64
            ;;
        aarch64|arm64)
            image_arch=arm64
            coreos_arch=aarch64
            ;;
        *)
            echo "offline does not support $(uname -m)" >&2
            exit 1
            ;;
    esac

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
            echo "podman is required to build offline artifacts" >&2
            exit 1
        fi
    }

    run_buildah() {
        if command -v buildah >/dev/null 2>&1; then
            TMPDIR="$tmpdir" buildah "$@"
        elif command -v flatpak-spawn >/dev/null 2>&1; then
            flatpak-spawn --host env TMPDIR="$tmpdir" buildah "$@"
        else
            echo "buildah is required to build offline artifacts" >&2
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
        local bootc_image="$3"

        sed \
            -e "s#__IMAGE_NAMESPACE__#${namespace}#g" \
            -e "s#__BOOTC_IMAGE__#${bootc_image}#g" \
            "$input" > "$output"
    }

    build_image() {
        local context="$1"
        local name="$2"
        local arch_image="${namespace}/${name}:${image_arch}"
        local latest_image="${namespace}/${name}:latest"
        shift 2

        printf '\n==> Building %s\n' "$arch_image"
        run_buildah bud \
            --layers \
            --pull=always \
            --arch "$image_arch" \
            --isolation="$isolation" \
            -t "$arch_image" \
            --label "org.opencontainers.image.source=${source_url}" \
            "$@" \
            "$context"

        run_buildah push --tls-verify="$tls_verify" \
            "$arch_image" "docker://$arch_image"
        run_buildah rmi "$latest_image" >/dev/null 2>&1 || true
        run_buildah tag "$arch_image" "$latest_image"
        run_buildah push --tls-verify="$tls_verify" \
            "$latest_image" "docker://$latest_image"
    }

    build_ips() {
        build_image images/ips ips --build-arg FCOS_STREAM=stable
    }

    build_workstation() {
        build_image images/workstation workstation \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_nas() {
        build_image images/nas nas \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}"
    }

    build_vm() {
        build_image vms/vm vm \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_sway() {
        build_image images/sway sway \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_k3s() {
        build_image vms/k3s k3s \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_minecraft() {
        build_image vms/minecraft minecraft \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_jellyfin() {
        build_image vms/jellyfin jellyfin \
            --tls-verify="$tls_verify" \
            --build-arg "IMAGE_NAMESPACE=${namespace}" \
            --build-arg "TAG=${image_arch}"
    }

    build_workstation_branch() {
        build_workstation
        build_sway
    }

    build_vm_branch() {
        build_vm
        run_parallel build_k3s build_minecraft build_jellyfin
    }

    run_parallel() {
        local task index failed=0
        local -a tasks=("$@")
        local -a pids=()

        for task in "${tasks[@]}"; do
            "$task" &
            pids+=("$!")
        done

        for index in "${!pids[@]}"; do
            if ! wait "${pids[$index]}"; then
                printf 'offline task failed: %s\n' "${tasks[$index]}" >&2
                failed=1
            fi
        done

        (( failed == 0 ))
    }

    build_ignition() {
        local input="$1"
        local output="$2"

        run_podman run --rm \
            -v "$repo:/work:Z" -w /work \
            quay.io/coreos/butane:release \
            --pretty --strict --files-dir . "$input" \
            > "$output"

        run_podman run --rm -i \
            quay.io/coreos/ignition-validate:release \
            - < "$output"
    }

    render_profile() {
        local profile="$1"
        local source_profile="$2"

        run_yq ea '. as $item ireduce ({}; . *+ $item)' \
            butane/base.yml \
            butane/updates.yml \
            "butane/${source_profile}.yml" \
            > "dist/butane/${profile}.bu"
        render_butane \
            "dist/butane/${profile}.bu" \
            "dist/butane/${profile}.rendered.bu" \
            "$profile"
        build_ignition \
            "dist/butane/${profile}.rendered.bu" \
            "dist/ign/${profile}.ign"
    }

    render_guest() {
        local guest="$1"

        run_yq ea '. as $item ireduce ({}; . *+ $item)' \
            butane/base.yml \
            butane/updates.yml \
            butane/vm.yml \
            "butane/${guest}.yml" \
            > "dist/butane/${guest}.bu"
        render_butane \
            "dist/butane/${guest}.bu" \
            "dist/butane/${guest}.rendered.bu" \
            "$guest"
        build_ignition \
            "dist/butane/${guest}.rendered.bu" \
            "dist/ign/${guest}.ign"
    }

    build_installer() {
        local profile="$1"
        local profile_dir="$work_dir/$profile"
        local archive_dir="$profile_dir/bootc"
        local archive_dir_container="/work-tmp/${profile}/bootc"
        local archive="$archive_dir/${profile}.ociarchive"
        local custom_iso="$profile_dir/custom.iso"
        local custom_iso_container="/work-tmp/${profile}/custom.iso"
        local out_iso="dist/iso/${profile}-offline-${coreos_arch}.iso"
        local out_iso_container="/work/${out_iso}"

        printf '\n==> Building %s\n' "$out_iso"
        mkdir -p "$archive_dir"
        rm -f "$out_iso" "${out_iso}.sha256"

        run_podman pull --tls-verify="$tls_verify" \
            "${namespace}/${profile}:latest"
        run_podman save --format oci-archive -o "$archive" \
            "${namespace}/${profile}:latest"
        (
            cd "$archive_dir"
            sha256sum "${profile}.ociarchive" \
                > "${profile}.ociarchive.sha256"
        )

        run_podman run --rm \
            --userns=keep-id \
            --user "$(id -u):$(id -g)" \
            -v "$repo:/work:Z" -w /work \
            -v "$work_dir:/work-tmp:Z" \
            quay.io/coreos/coreos-installer:release \
            iso customize \
                --live-ignition dist/ign/setup.ign \
                --dest-ignition "dist/ign/${profile}.ign" \
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

        (
            cd dist/iso
            sha256sum "${profile}-offline-${coreos_arch}.iso" \
                > "${profile}-offline-${coreos_arch}.iso.sha256"
        )
        rm -rf -- "$profile_dir"
    }

    ensure_registry

    cd "$repo"
    mkdir -p dist/butane dist/ign dist/iso

    build_ips

    if [[ "$target" == all ]]; then
        run_parallel build_workstation_branch build_nas build_vm_branch
        profiles=(nas workstation sway)
    else
        build_workstation
        profiles=(workstation)
    fi

    # Keep the staging directory under the checkout so host-side Podman can see
    # it even when Just is running inside a Flatpak sandbox with a private /tmp.
    work_dir="$(mktemp -d "$repo/dist/.pipeline-offline.XXXXXX")"
    trap 'rm -rf -- "$work_dir"' EXIT

    run_yq ea '. as $item ireduce ({}; . *+ $item)' \
        butane/base.yml \
        butane/setup.yml \
        > dist/butane/setup.bu
    render_butane \
        dist/butane/setup.bu \
        dist/butane/setup.rendered.bu \
        workstation
    build_ignition dist/butane/setup.rendered.bu dist/ign/setup.ign

    for profile in "${profiles[@]}"; do
        if [[ "$profile" == sway ]]; then
            render_profile sway workstation
        else
            render_profile "$profile" "$profile"
        fi
    done

    if [[ "$target" == all ]]; then
        for guest in k3s minecraft jellyfin; do
            render_guest "$guest"
        done
    fi

    if ! ls -1 fedora-coreos-*-live-iso."${coreos_arch}".iso >/dev/null 2>&1; then
        run_podman run --rm \
            --userns=keep-id \
            --user "$(id -u):$(id -g)" \
            -v "$repo:/work:Z" -w /work \
            quay.io/coreos/coreos-installer:release \
            download -s stable -a "$coreos_arch" -p metal -f iso -C /work --decompress
    fi

    base_iso="$(ls -1t fedora-coreos-*-live-iso."${coreos_arch}".iso | sed -n '1p')"
    for profile in "${profiles[@]}"; do
        build_installer "$profile"
    done

    printf '\nBuilt %s images in %s and installer artifacts in %s/dist.\n' \
        "$target" "$namespace" "$repo"
