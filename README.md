
![License](https://img.shields.io/badge/license-MIT-blue.svg)
[![Pipeline](https://github.com/noobping/infrastructure/actions/workflows/pipeline.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/pipeline.yml)
[![Butane](https://github.com/noobping/infrastructure/actions/workflows/butane.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/butane.yml)
[![IPS](https://github.com/noobping/infrastructure/actions/workflows/ips.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/ips.yml)
[![Workstation](https://github.com/noobping/infrastructure/actions/workflows/workstation.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/workstation.yml)
[![Sway](https://github.com/noobping/infrastructure/actions/workflows/sway.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/sway.yml)
[![NAS](https://github.com/noobping/infrastructure/actions/workflows/nas.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/nas.yml)

# Infrastructure

Declarative infrastructure for workstations and servers.

This project delivers fully automated, immutable system images built on Fedora CoreOS (FCOS).
From GNOME and Sway-based workstations to headless servers and storage nodes, the entire stack is defined as code using Butane, bootable containers, and CI/CD pipelines.

Nodes automatically configure themselves at first boot and continuously maintain their desired state.

## Commands

```sh
pipeline check       # run whitespace and shell checks in parallel
just offline         # build everything for the host architecture
just offline both    # build everything for AMD64 and ARM64
```

The Workstation, Sway, and NAS images expose `pipeline` as a Podman-backed shell
alias. It pulls a newer `continuous` image when available, mounts the current
directory, and never installs Pipeline on the host.

`just offline` starts or reuses a local registry and builds IPS, Workstation,
Sway, NAS, the VM base, K3s, Minecraft, and Jellyfin for the host architecture.
Pass `both`, `amd64`, or `arm64` to select another build:

```sh
just offline both
just offline amd64
just offline arm64
```

Architecture graphs run sequentially so their shared artifacts and tags cannot
race; independent image branches within each graph build in parallel. Every
image is published with its `:amd64` or `:arm64` tag. A `both` build also
publishes `:latest` as a multi-architecture manifest. It renders all Ignition
configs and embeds the matching architecture image in each installer:

```text
dist/iso/nas-offline-{x86_64,aarch64}.iso
dist/iso/sway-offline-{x86_64,aarch64}.iso
dist/iso/workstation-offline-{x86_64,aarch64}.iso
```

Each ISO has a matching `.sha256`; generated Ignition files are in `dist/ign`.
Use `just offline-workstation [architecture]` for only the IPS and Workstation
path. These recipes require host Podman and Buildah and default to
`IMAGE_NAMESPACE=localhost:5000/noobping`. Building a non-native architecture
also requires working QEMU/binfmt container emulation on the host; the recipe
checks this before starting the image graph. Creating the media requires network
access: image builds refresh their upstream bases, and the recipe downloads a
Fedora CoreOS ISO when one is not already present. The ARM64 NAS image and ISO
are supported, but its bundled libvirt VM deployment remains x86_64-only.

## Container and GitHub

The `pipeline` alias is equivalent to:

```sh
podman run --rm --pull=newer \
  --userns=keep-id \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --volume "$PWD:/work:Z" \
  --workdir /work \
  ghcr.io/noobping/pipeline:continuous check
```

[The Pipeline workflow](.github/workflows/pipeline.yml) runs the same `check`
through the Pipeline GitHub Action.
