
# Extensions

Install Nick's favorite GNOME extensions:

```sh
podman run --rm -v "$(pwd)/workstation/skel:/out:Z" ghcr.io/noobping/gnome-extensions
```

Or build the installer locally:

```sh
podman build -t ghcr.io/noobping/gnome-extensions extensions
```
