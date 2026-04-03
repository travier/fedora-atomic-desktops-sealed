#!/bin/bash

set -euo pipefail
# set -x

main() {
    if [[ "${#}" -ne 2 ]]; then
        echo "Missing arguments. Example usage: ${0} vm-name qemu-image.qcow2"
        exit 1
    fi

    local -r name="${1}"
    local -r image="${2}"

    if [[ -z ${name} ]]; then
        echo "Can not use an empty name!"
        exit 1
    fi
    if [[ ! -f ${image} ]]; then
        echo "${image} is not a file!"
        exit 1
    fi

    IMAGE="$(realpath "${image}")"

    VCPUS="4"
    RAM_MB="4096"
    DISK_GB="20"

    virt-install --connect="qemu:///system" \
        --name="${name}" \
        --vcpus="${VCPUS}" \
        --memory="${RAM_MB}" \
        --os-variant="fedora43" \
        --import \
        --disk="size=${DISK_GB},backing_store=${IMAGE}" \
        --network bridge=virbr0 \
        --machine q35 \
        --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
        --tpm none \
        --noautoconsole
}

main "${@}"
