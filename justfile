# name := "fedora-silverblue-uki"
name := "fedora-kinoite-uki"
image := name + ":latest"

all:
    echo TODO

build:
    #!/bin/bash
    set -euo pipefail
    podman build \
        -t {{image}} \
        --skip-unused-stages=false \
        -v $(pwd):/run/src \
        --security-opt=label=disable \
        --secret=id=secureboot_key,src=secureboot/db.key \
        --secret=id=secureboot_cert,src=secureboot/db.pem \
        .

qcow2:
    #!/bin/bash
    set -euo pipefail
    ./bcvk to-disk \
        --filesystem=btrfs \
        --composefs-backend \
        --bootloader=systemd \
        --format qcow2 \
        --disk-size 20G \
        {{image}} {{name}}.qcow2

libvirt:
    #!/bin/bash
    set -euo pipefail
    DEST="${HOME}/.local/share/libvirt/images"
    mv {{name}}.qcow2 "${DEST}"
    ./install-libvirt_eufi_nosb.sh {{name}} "${DEST}/{{name}}.qcow2"
