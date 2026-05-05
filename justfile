# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

# Variants and the container registry location to get them
# Just doesn't have a native dict type, but quoted bash dictionary works fine
variant_repos := '(
    [silverblue]="quay.io/fedora-ostree-desktops/silverblue"
    [kinoite]="quay.io/fedora-ostree-desktops/kinoite"
)'

# Container registry where the images will be pushed
dest_registry := "quay.io/fedora-atomic-desktops-sealed"

# Version of the container image to use as base
version := "44.20260504.0"

# Major Fedora version used
release := "44"

# Container image with systemd-boot signed
# Defaults to locally built container image. Uncomment to use pre-signed binary.
# systemd_boot_container := "quay.io/fedora-atomic-desktops-sealed/systemd-boot:" + release
systemd_boot_container := "localhost/systemd-boot:" + release

# Container image with the tools for signing UKIs
# Defaults to pre-built image. Uncomment to use locally built container image.
# signing_tools_container := "localhost/tools:" + release
signing_tools_container := "quay.io/fedora-atomic-desktops-sealed/tools:" + release

# How to connect to libvirt (either system or session)
libvirt_uri := "qemu:///system"

all:
    echo "Please read README.md"

# Builds a container with sbctl and generates Secure Boot keys
generate-secure-boot-keys:
    #!/bin/bash
    set -euo pipefail
    podman build --tag sbctl --file Containerfile.sbctl
    podman run --rm -ti --security-opt=label=disable \
        --volume $(pwd):/run/src --workdir /run/src \
        localhost/sbctl:latest create-keys --config sbctl.conf

# Sign systemd-boot with the Secure Boot key
sign-systemd-boot:
    #!/bin/bash
    set -euo pipefail
    podman build \
        --tag systemd-boot:{{release}} \
        --build-arg=RELEASE={{release}} \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        --file Containerfile.systemd-boot

# Build the container image with the tools to build and sign UKIs
build-tools:
    #!/bin/bash
    set -euo pipefail
    podman build \
        --tag tools:{{release}} \
        --build-arg=RELEASE={{release}} \
        --file Containerfile.tools

# Build a generic sealed container image derived from the Fedora Silverblue or
# Kinoite unofficial bootable container image
[arg('variant', pattern='silverblue|kinoite')]
build variant:
    #!/bin/bash
    set -euo pipefail
    declare -A variant_repos={{variant_repos}}
    podman build \
        --build-arg=BASE=${variant_repos["{{variant}}"]}:{{version}} \
        --build-arg=SYSTEMDBOOT={{systemd_boot_container}} \
        --build-arg=TOOLS={{signing_tools_container}} \
        --tag {{dest_registry}}/{{variant}}:{{version}} \
        --tag {{dest_registry}}/{{variant}}:{{release}} \
        --skip-unused-stages=false \
        --volume $(pwd):/run/src \
        --security-opt=label=disable \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        .

# Extract the kernel from an image and remove the initrd to build a rechunked
# base image with generic configuration
[arg('variant', pattern='silverblue|kinoite')]
build-base variant:
    #!/bin/bash
    set -euo pipefail
    declare -A variant_repos={{variant_repos}}

    podman build \
        --file Containerfile.kernel \
        --build-arg=BASE=${variant_repos["{{variant}}"]}:{{version}} \
        --tag {{dest_registry}}/{{variant}}-kernel:{{version}} \
        .
    podman build \
        --file Containerfile.base \
        --build-arg=BASE=${variant_repos["{{variant}}"]}:{{version}} \
        --build-arg=SYSTEMDBOOT={{systemd_boot_container}} \
        --tag {{dest_registry}}/{{variant}}-base:{{version}} \
        --skip-unused-stages=false \
        --volume $(pwd):/run/src \
        --security-opt=label=disable \
        .

# Build a sealed image with support for all GPU or only a specific GPU family
[arg('variant', pattern='silverblue|kinoite'), arg('gpu', pattern='generic|amd|intel|nvidia')]
build-uki variant gpu="generic":
    #!/bin/bash
    set -euo pipefail

    if [[ "{{gpu}}" == "generic" ]]; then
        repo="{{variant}}"
    else
        repo="{{variant}}-{{gpu}}"
    fi

    podman build \
        --file Containerfile.uki \
        --build-arg=BASE={{dest_registry}}/{{variant}}-base:{{version}} \
        --build-arg=KERNEL={{dest_registry}}/{{variant}}-kernel:{{version}} \
        --build-arg=GPU_FAMILY={{gpu}} \
        --build-arg=TOOLS={{signing_tools_container}} \
        --tag {{dest_registry}}/${repo}:{{version}} \
        --tag {{dest_registry}}/${repo}:{{release}} \
        --volume $(pwd):/run/src \
        --security-opt=label=disable \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        .

# Install the container image to a QCOW2 disk image
[arg('variant', pattern='silverblue|kinoite')]
qcow2 variant:
    #!/bin/bash
    set -euo pipefail
    ./bcvk to-disk \
        --filesystem=btrfs \
        --composefs-backend \
        --bootloader=systemd \
        --format qcow2 \
        --disk-size 20G \
        {{dest_registry}}/{{variant}}:{{release}} \
        {{variant}}-{{version}}.qcow2

# Move the QCOW2 image to libvirt image store
[arg('variant', pattern='silverblue|kinoite')]
move-qcow2-libvirt-images variant:
    #!/bin/bash
    set -euo pipefail
    DEST="${HOME}/.local/share/libvirt/images"
    mv -i {{variant}}-{{version}}.qcow2 "${DEST}"

# Generate an OVMF variable file for EDK2 with the Secure Boot keys included
generate-ovmf-vars:
    #!/bin/bash
    set -euo pipefail
    if [[ ! -d "keys" ]]; then
        echo "Missing Secure Boot keys"
        exit 1
    fi
    GUID=$(cat keys/GUID)
    virt-fw-vars \
        --input "/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2" \
        --secure-boot \
        --set-pk  $GUID "keys/PK/PK.pem" \
        --add-kek $GUID "keys/KEK/KEK.pem" \
        --add-db  $GUID "keys/db/db.pem" \
        -o "OVMF_VARS_CUSTOM.qcow2"

# Boot the QCOW2 image with libvirt
[arg('variant', pattern='silverblue|kinoite')]
libvirt variant:
    #!/bin/bash
    set -euo pipefail

    DEST="${HOME}/.local/share/libvirt/images"

    name="fedora-{{variant}}-{{version}}"
    image="${DEST}/{{variant}}-{{version}}.qcow2"
    ovmf_vars="${DEST}/{{variant}}-{{version}}_ovmf_vars.qcow2"

    cp "OVMF_VARS_CUSTOM.qcow2" "${ovmf_vars}"

    VCPUS="4"
    RAM_MB="4096"
    DISK_GB="20"

    OVMF_CODE="/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2"
    OVMF_VARS_TEMPLATE="/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2"

    loader="loader=${OVMF_CODE},loader.readonly=yes,loader.type=pflash,loader_secure=yes"
    nvram="nvram=${ovmf_vars},nvram.template=${OVMF_VARS_TEMPLATE}"
    features="firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes"
    uefi_arg+=("uefi,${loader},${nvram},${features}")

    virt-install --connect="{{libvirt_uri}}" \
        --name="${name}" \
        --vcpus="${VCPUS}" \
        --memory="${RAM_MB}" \
        --os-variant="fedora43" \
        --import \
        --disk="size=${DISK_GB},backing_store=${image}" \
        --network bridge=virbr0 \
        --machine q35 \
        --boot "${uefi_arg}" \
        --tpm "backend.type=emulator,backend.version=2.0,model=tpm-tis" \
        --noautoconsole

# Build and sign a UKI addon
uki-addon name commandline:
    #!/bin/bash
    set -euo pipefail
    podman run --rm -ti --security-opt=label=disable \
        --volume $(pwd):/run/src --workdir /run/src \
        --secret=id=secureboot_key,src=keys/db/db.key \
        --secret=id=secureboot_crt,src=keys/db/db.pem \
        {{signing_tools_container}} \
        ukify build \
            --cmdline "{{commandline}}" \
            --signtool sbsign \
            --secureboot-private-key /run/secrets/secureboot_key \
            --secureboot-certificate /run/secrets/secureboot_crt \
            --output "/run/src/{{name}}.addon.efi"

# Inspect a UKI or UKI addon
inspect uki:
    #!/bin/bash
    set -euo pipefail
    podman run --rm -ti --security-opt=label=disable \
        --volume $(pwd):/run/src --workdir /run/src \
        {{signing_tools_container}} \
        ukify inspect "/run/src/{{uki}}"
