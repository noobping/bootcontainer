
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

## Pipeline

Portable checks and the local-only offline installer build use
[Pipeline](https://github.com/noobping/pipeline) and ordinary Just recipes:

```sh
pipeline check
pipeline offline
```

`check` runs its independent jobs in parallel. `offline` builds the x86_64
Workstation ISO with its bootc image embedded and requires host Podman and
Buildah. It defaults to `localhost:5000/noobping`; override `IMAGE_NAMESPACE`,
`REGISTRY_TLS_VERIFY`, `LOCAL_REGISTRY_CONTAINER`, or `LOCAL_REGISTRY_VOLUME`
when needed.

The portable checks can also run without a host Pipeline installation:

```sh
podman run --rm --userns=keep-id \
  --env HOME=/tmp \
  --volume "$PWD:/work:Z" \
  --workdir /work \
  ghcr.io/noobping/pipeline:continuous check
```

The offline recipe intentionally runs on the host because it builds and embeds
other container images.
