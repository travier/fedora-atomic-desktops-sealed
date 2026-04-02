default_variant:= "silverblue"
version := "44.20260330.0"

all:
    echo TODO

build variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    podman build \
        --build-arg=BASE=quay.io/fedora-ostree-desktops/{{variant}}:{{version}} \
        -t {{variant}}-sealed:{{version}} \
        --skip-unused-stages=false \
        -v $(pwd):/run/src \
        --security-opt=label=disable \
        --secret=id=secureboot_key,src=secureboot/db.key \
        --secret=id=secureboot_cert,src=secureboot/db.pem \
        .

qcow2 variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    ./bcvk to-disk \
        --filesystem=btrfs \
        --composefs-backend \
        --bootloader=systemd \
        --format qcow2 \
        --disk-size 20G \
        localhost/{{variant}}-sealed:{{version}} {{variant}}-{{version}}.qcow2

libvirt variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    DEST="${HOME}/.local/share/libvirt/images"
    mv {{variant}}-{{version}}.qcow2 "${DEST}"
    ./install-libvirt_eufi_nosb.sh fedora-{{variant}}-{{version}} "${DEST}/{{variant}}-{{version}}.qcow2"
