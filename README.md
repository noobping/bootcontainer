![License](https://img.shields.io/badge/license-MIT-blue.svg)
[![Pipeline](https://github.com/noobping/infrastructure/actions/workflows/pipeline.yml/badge.svg)](https://github.com/noobping/infrastructure/actions/workflows/pipeline.yml)

# Infrastructure

Immutable Fedora CoreOS images and installers for workstations, storage nodes,
and VM guests. Just contains the build recipes; Pipeline connects them into
dependency graphs.

## Commands

```sh
pipeline check                 # whitespace and shell validation
PUBLISH=true pipeline online   # stable images and online media
PUBLISH=true pipeline next     # Fedora CoreOS next-stream images
pipeline offline               # all offline media, AMD64 and ARM64
pipeline offline-workstation   # Workstation offline media, both architectures
PUBLISH=true pipeline release  # stable build followed by GitHub publication
```

`pipeline online` builds the stable IPS base first, then builds Workstation,
Sway, NAS, the VM base, K3s, Minecraft, and Jellyfin in dependency order. It
builds AMD64 and ARM64 images, publishes their architecture tags and
multi-architecture `:latest` manifests, and creates the online NAS,
Workstation, and Sway media plus all Ignition configurations. The image and
media jobs run concurrently; the two architecture graphs and independent image
branches also run in parallel.

The Fedora CoreOS `next` stream is deliberately a separate pipeline, so CI can
allow it to fail without hiding failures in the stable graph. It builds and
publishes the next IPS, Workstation, and Sway images for both architectures
with `:next` manifests.

Pipeline's offline commands always build both architectures. For a smaller or
native-only offline build, call Just directly:

```sh
just offline [selection] [architecture]

# selection:    all (default), workstation
# architecture: native (default), both, amd64, arm64
just offline workstation amd64
just offline amd64
```

Offline builds start or reuse a local registry and embed the matching OCI image
inside each installer. Architecture graphs run sequentially while independent
branches within a graph run in parallel.

## Outputs

```text
dist/online/ign/*.ign
dist/online/iso/nas-{x86_64,aarch64}.iso
dist/online/iso/sway-{x86_64,aarch64}.iso
dist/online/iso/workstation-{x86_64,aarch64}.iso
dist/ign/*.ign
dist/iso/nas-offline-{x86_64,aarch64}.iso
dist/iso/sway-offline-{x86_64,aarch64}.iso
dist/iso/workstation-offline-{x86_64,aarch64}.iso
```

Every ISO has a matching `.sha256` file. Offline ISO names include `-offline`
and contain the image archive; online ISO names do not.

## Publishing and build environment

Online builds default to `IMAGE_NAMESPACE=ghcr.io/noobping`. Authenticate the
container tools with `REGISTRY_USER` and `REGISTRY_TOKEN`; in GitHub Actions the
token comes from `GITHUB_TOKEN`. Publishing to a non-local registry requires
`PUBLISH=true` and a clean checkout; `ALLOW_DIRTY=true` is available for an
intentional development build. Manifest signing uses Cosign's ambient keyless
credentials, including GitHub's OIDC identity. Set `SIGN_IMAGES=false` for an
unsigned test registry and `REGISTRY_TLS_VERIFY=false` for an insecure local
registry. `pipeline release` publishes the files in `dist/online/iso` to the
continuous GitHub release with `GH_TOKEN` or `GITHUB_TOKEN`; it uses an
installed GitHub CLI or its container image.

The installed command and the Workstation/NAS `pipeline` launcher run the same
configuration. The launcher copies Pipeline and its bundled Just binary from
`ghcr.io/noobping/pipeline:continuous` into a temporary directory, runs them on
the host, and removes them afterward. It therefore needs no permanent install
while still giving recipes access to host tools. Cached images are used by
default; set `PIPELINE_PULL=newer` to update or `PIPELINE_PULL=never` for a
strictly disconnected launch.

Image builds need host Podman and Buildah, plus Cosign when signing is enabled,
sufficient disk space, and QEMU/binfmt when building a non-native architecture.
Release uses an installed GitHub CLI or Podman. Build execution refreshes
upstream images, packages, and Fedora CoreOS media, so it requires network
access. “Offline” means the resulting installer can install without a network
connection. The ARM64 NAS image and installer are supported; its bundled
libvirt VM deployment remains x86_64-only.
