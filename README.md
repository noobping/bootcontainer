
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
pipeline check            # run whitespace and shell checks in parallel
just offline-workstation  # build the x86_64 offline Workstation installer
```

The Workstation, Sway, and NAS images expose `pipeline` as a Podman-backed shell
alias. It pulls a newer `continuous` image when available, mounts the current
directory, and never installs Pipeline on the host.

`offline-workstation` starts or reuses a local registry, builds the IPS and
Workstation images, customizes the Fedora CoreOS ISO, and writes:

```text
dist/iso/workstation-offline-x86_64.iso
dist/iso/workstation-offline-x86_64.iso.sha256
```

It runs directly through Just because the build requires host Podman and
Buildah. It defaults to `IMAGE_NAMESPACE=localhost:5000/noobping`.

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
