default_variant:= "silverblue"
version := "44.20260330.0"
release := "44"

all:
    echo "TODO"

generate-secure-boot-keys:
    #!/bin/bash
    set -euo pipefail
    podman build -t sbctl -f Containerfile.sbctl
    podman run --rm -ti --security-opt=label=disable \
        --volume $(pwd):/run/src --workdir /run/src \
        localhost/sbctl:latest create-keys --config sbctl.conf

generate-ovmf-vars:
    #!/bin/bash
    set -euo pipefail
    if [[ ! -d "keys" ]]; then
        echo "Missing Secure Boot keys"
        exit 1
    fi
    # See: https://github.com/rhuefi/qemu-ovmf-secureboot
    # $ dnf install -y python3-virt-firmware
    GUID=$(cat keys/GUID)
    virt-fw-vars \
        --input "/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2" \
        --secure-boot \
        --set-pk  $GUID "keys/PK/PK.pem" \
        --add-kek $GUID "keys/KEK/KEK.pem" \
        --add-db  $GUID "keys/db/db.pem" \
        -o "OVMF_VARS_CUSTOM.qcow2"

build variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    podman build \
        --build-arg=BASE=quay.io/fedora-ostree-desktops/{{variant}}:{{version}} \
        -t {{variant}}-sealed:{{version}} \
        --skip-unused-stages=false \
        -v $(pwd):/run/src \
        --security-opt=label=disable \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        .

build-tools:
    #!/bin/bash
    set -euo pipefail
    podman build \
        -t tools:{{release}} \
        -f Containerfile.tools

sign-systemd-boot:
    #!/bin/bash
    set -euo pipefail
    podman build \
        -t systemd-boot:{{release}} \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        -f Containerfile.systemd-boot

qcow2 variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    ./bcvk to-disk \
        --filesystem=btrfs \
        --composefs-backend \
        --bootloader=systemd \
        --format qcow2 \
        --disk-size 20G \
        localhost/{{variant}}-sealed:{{version}} \
        {{variant}}-{{version}}.qcow2

libvirt variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    DEST="${HOME}/.local/share/libvirt/images"
    mv {{variant}}-{{version}}.qcow2 "${DEST}"
    cp "OVMF_VARS_CUSTOM.qcow2" "${DEST}/{{variant}}-{{version}}_ovmf_vars.qcow2"

    ./install-libvirt_eufi_sb.sh \
        fedora-{{variant}}-{{version}} \
        "${DEST}/{{variant}}-{{version}}.qcow2" \
        "OVMF_VARS_CUSTOM.qcow2"

    name="fedora-{{variant}}-{{version}}"
    image="${DEST}/{{variant}}-{{version}}.qcow2"
    ovmf_vars="${DEST}/{{variant}}-{{version}}_ovmf_vars.qcow2"

    VCPUS="4"
    RAM_MB="4096"
    DISK_GB="20"

    OVMF_CODE="/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2"
    OVMF_VARS_TEMPLATE="/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2"
    OVMF_VARS="${HOME}/.local/share/libvirt/images/OVMF_VARS_CUSTOM_${name}.qcow2"

    loader="loader=${OVMF_CODE},loader.readonly=yes,loader.type=pflash,loader_secure=yes"
    nvram="nvram=${OVMF_VARS},nvram.template=${OVMF_VARS_TEMPLATE}"
    features="firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes"
    uefi_arg+=("uefi,${loader},${nvram},${features}")

    virt-install --connect="qemu:///system" \
        --name="${name}" \
        --vcpus="${VCPUS}" \
        --memory="${RAM_MB}" \
        --os-variant="fedora43" \
        --import \
        --disk="size=${DISK_GB},backing_store=${IMAGE}" \
        --network bridge=virbr0 \
        --machine q35 \
        --boot "${uefi_arg}" \
        --tpm "backend.type=emulator,backend.version=2.0,model=tpm-tis" \
        "${args[@]}" \
        --noautoconsole
