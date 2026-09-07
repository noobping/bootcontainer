
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
pipeline check  # run whitespace and shell checks in parallel
just offline    # build every stable image and offline installer
```

The Workstation, Sway, and NAS images expose `pipeline` as a Podman-backed shell
alias. It pulls a newer `continuous` image when available, mounts the current
directory, and never installs Pipeline on the host.

`just offline` starts or reuses a local registry and builds the native
architecture of IPS, Workstation, Sway, NAS, the VM base, K3s, Minecraft, and
Jellyfin. Independent image branches build in parallel. It then renders all
Ignition configs and embeds each host image in its installer (`ARCH` is
`x86_64` or `aarch64`):

```text
dist/iso/nas-offline-ARCH.iso
dist/iso/sway-offline-ARCH.iso
dist/iso/workstation-offline-ARCH.iso
```

Each ISO has a matching `.sha256`; generated Ignition files are in `dist/ign`.
Use `just offline-workstation` for only the IPS and Workstation path. These
recipes require host Podman and Buildah and default to
`IMAGE_NAMESPACE=localhost:5000/noobping`. Creating the media requires network
access: image builds refresh their upstream bases, and the recipe downloads a
Fedora CoreOS ISO when one is not already present.

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
