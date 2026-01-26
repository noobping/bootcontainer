
# Desktop ignition

Build the butane files:

```sh
yq ea '. as $item ireduce ({}; . *+ $item)' base.yml live.yml > live.bu
yq ea '. as $item ireduce ({}; . *+ $item)' base.yml desktop.yml > desktop.bu
```

Build ignition file:

```sh
butane --pretty --strict live.bu > live.ign
butane --pretty --strict desktop.bu > desktop.ign
```

Download FCOS live ISO

```sh
podman run --rm -it \
    --userns=keep-id \
    --user $(id -u):$(id -g) \
    -v $PWD:/work:Z -w /work \
    quay.io/coreos/coreos-installer:release \
    download -s stable -a $(uname -m) -p metal -f iso -C /work --decompress
```
