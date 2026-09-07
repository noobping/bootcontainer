# NAS

Cockpit is at `https://nas.vm/` on port 443. The existing libvirt configuration
and services are unchanged.

## NFS

The NAS serves NFSv4 and NFSv3 for Nautilus. `nfs/exports` limits every export
to its matching VM and uses synchronous writes. K3s application paths use
`no_root_squash`; shared-document and standalone-VM paths remain root-squashed,
and Jellyfin media is read-only. Build artifacts at
`nas.vm:/var/srv/ssd/artifacts` are publicly readable. VM clients use hard NFS
4.2 mounts with `fsc`.

```sh
systemctl is-active nfs-server.service
sudo exportfs -v
ssh nick@k3s.vm 'findmnt -t nfs,nfs4 && systemctl is-active cachefilesd.service'
```

## Pipeline

Interactive shells expose `pipeline` as a Podman-backed alias. It pulls a newer
`ghcr.io/noobping/pipeline:continuous` image when available; no Pipeline binary,
update service, or timer is installed on the host.

Install self-contained hooks in a normal or bare repository with:

```sh
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
install -d "$common_dir/pipeline"
cat > "$common_dir/pipeline/config.yml" <<'EOF'
version: 1
hooks:
  incoming: trusted
  trusted-ref: HEAD
EOF
pipeline add --copy
```

The container copies Pipeline and Just into the repository, so hooks do not
depend on the shell alias or a running container. Install them after a bare
repository's default branch exists. The trusted policy keeps hook definitions on
the current default branch instead of accepting replacements from the push being
checked.

## Backups

`btrfs-backup.timer` runs weekly and retains three snapshots by default under
`/var/srv/hdd/backups/ssd`.

```sh
systemctl list-timers btrfs-backup.timer
sudo systemctl start --wait btrfs-backup.service
sudo journalctl -u btrfs-backup.service
```

The timer is crash-consistent: it does not quiesce guests or snapshot all
subvolumes atomically. Use the [VM backup order](../../vms/README.md#safety-and-backups)
when logical database dumps are required. The Caddy backup contains the local
CA private key; keep backups restricted.
