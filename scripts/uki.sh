#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

set -euxo pipefail

target="/run/target"
output="/boot/EFI/Linux"
secrets="/run/secrets"

# Find the kernel version (needed for output filename)
kver=$(cd "${target}/usr/lib/modules" && echo *)

# Baseline ukify options
ukifyargs=(
    --measure
    --json pretty
    --output "${output}/${kver}.efi"
)

# Signing options, we use sbsign by default
ukifyargs+=(
    --signtool sbsign
    --secureboot-private-key "${secrets}/secureboot_key"
    --secureboot-certificate "${secrets}/secureboot_crt"
)

# Baseline container ukify options
containerukifyargs=(--rootfs "${target}")

# Build the UKI using bootc container ukify
# This computes the composefs digest, reads kargs from kargs.d, and invokes ukify
# FIXME: Disabled until we get support for passing the kernel & initrd as parameters
# FIXME: Manual flow below
# bootc container ukify "${containerukifyargs[@]}" -- "${ukifyargs[@]}"

# Compute the composefs digest from the mounted rootfs
digest="$(bootc container compute-composefs-digest "${target}")"

# Create command line
{
# composefs digest and rw to default to a writable system
printf "composefs=${digest} rw"
# Enable btrfs compression for the root mount point
printf " rootflags=compress=zstd:1"
# Suppress console output and enable Plymouth
printf " quiet rhgb"
# Debug shell enabled in the initrd and final system
printf " rd.systemd.debug_shell systemd.debug_shell"
# Workarounds for TPM2 issue in systemd with some older TPM chips
printf " rd.systemd.mask=systemd-tpm2-setup-early.service"
printf " systemd.mask=systemd-tpm2-setup-early.service"
printf " systemd.mask=systemd-tpm2-setup.service"
printf " systemd.mask=systemd-pcrphase.service"
printf " systemd.mask=systemd-pcrproduct.service"
printf "\n"
} > /etc/kernel/cmdline

# Generate and sign the UKI with the digest embedded
ukify build \
  --linux "/vmlinuz" \
  --initrd "/initramfs" \
  --uname="${kver}" \
  --cmdline "@/etc/kernel/cmdline" \
  --os-release "@${target}/usr/lib/os-release" \
  "${ukifyargs[@]}"
