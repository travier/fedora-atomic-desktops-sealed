#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

# The sections inside the if conditionals are intentionally not properly
# indented to make the heredoc blocks easier to read.

set -euxo pipefail

# We can not ship openh264 in the image
rm -f "/etc/yum.repos.d/fedora-cisco-openh264.repo"

# Install fsverity utils to make it easier to check things
dnf install -y fsverity-utils

# Remove rpm-ostree and the backends in GNOME Software and Plasma Discover
dnf remove -y \
    rpm-ostree \
    rpm-ostree-libs \
    gnome-software-rpm-ostree \
    plasma-discover-rpm-ostree


NAME="$(source /etc/os-release && echo "${NAME}")"
if [[ "${NAME}" == "Bazzite" ]]; then
    # Temporarily pull bootc from the rhcontainerbot copr to get the latest
    # fixes for Bazzite: https://copr.fedorainfracloud.org/coprs/rhcontainerbot/bootc/
    dnf install -y 'dnf5-command(copr)'
    dnf copr enable -y rhcontainerbot/bootc "fedora-$(source /etc/os-release && echo "$VERSION_ID")-x86_64"
    dnf upgrade -y --refresh bootc
else
    # Install latest bootc release
    dnf upgrade -y --enablerepo=updates-testing --refresh bootc
fi

# Uninstall bootupd (no support for systemd-boot yet)
rpm -e bootupd
rm -vrf "/usr/lib/bootupd"
# Legacy ostree folder
rm -vrf "/usr/lib/ostree-boot"
# Remove GRUB2
grub_packages=(
    "grub2-common"
    "grub2-efi-x64"
    "grub2-pc"
    "grub2-pc-modules"
    "grub2-tools"
    "grub2-tools-minimal"
)
if [[ "$(rpm -qa | grep -c grub2-efi-ia32)" -ne 0 ]]; then
    grub_packages+=("grub2-efi-ia32")
fi
rpm -e --nodeps "${grub_packages[@]}"

# Install unsigned systemd-boot to get the man pages
dnf install -y systemd-boot-unsigned
# Install signed systemd-boot from the Rawhide (non-production key)
# See: https://koji.fedoraproject.org/koji/buildinfo?buildID=3017451
dnf install -y "https://kojipkgs.fedoraproject.org//packages/systemd-boot/261~rc3/2.fc45/noarch/systemd-boot-x64-261~rc3-2.fc45.noarch.rpm"
# Replace the unsigned built with the signed one
cp -a /usr/lib/systemd/boot/efi/systemd-bootx64.efi{.signed,}

# prepare directory for image-builder configuration
mkdir -p "/usr/lib/image-builder/bootc"

# set up an argument for the root type UUID
GPT_ROOT_TYPE=""
if [[ "${TARGETARCH}" == "amd64" ]]; then
    GPT_ROOT_TYPE="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
elif [[ "${TARGETARCH}" == "arm64" ]]; then
    GPT_ROOT_TYPE="b0e01050-ee5f-4390-949a-9101b17104e9"
elif [[ "${TARGETARCH}" == "s390x" ]]; then
    GPT_ROOT_TYPE="5eead9a9-fe09-4a1e-a1d7-520d00531306"
elif [[ "${TARGETARCH}" == "ppc64le" ]]; then
    GPT_ROOT_TYPE="c31c45e6-3f39-412e-80fb-4809c4980599"
elif [[ "${TARGETARCH}" == "riscv64" ]]; then
    GPT_ROOT_TYPE="72ec70a6-cf74-40e6-bd49-4bda08e8f224"
else
    exit 1
fi

if rpm -q --quiet fedora-release-identity-basic; then

# bootc base iamges
cat > "/usr/lib/bootc/install/80-rootfs.toml" << 'EOF'
# Default to ext4
[install.filesystem.root]
type = "ext4"
EOF

# ext4 root for base
cat > "/usr/lib/image-builder/bootc/disk.yaml" << EOF
mount_configuration: "none"
partition_table:
  type: "gpt"
  partitions:
    - size: "2 GiB"
      type: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
      payload_type: "filesystem"
      payload:
        type: "vfat"
        # wrong mountpoint, but isn't actually used; works around a
        # bug in image-builder:
        mountpoint: "/boot/efi"
        label: "ESP"
    - size: "3 GiB"
      # type is architecture dependent, image-builder should auto-assign
      # based on the architecture but for now we append based on TARGETARCH
      type: "${GPT_ROOT_TYPE}"
      payload_type: "filesystem"
      payload:
        type: "ext4"
        label: "root"
        mountpoint: "/"
EOF

else

# All Atomic Desktops
cat > "/usr/lib/bootc/kargs.d/10-rootfs.toml" << 'EOF'
# Mount the root filesystem read-write
# Enable btrfs compression
# Automatically mount the root subvolume
kargs = ["rw", "rootflags=compress=zstd:1,subvol=root"]
EOF

cat > "/usr/lib/bootc/install/80-rootfs.toml" << 'EOF'
# Default to btrfs
[install.filesystem.root]
type = "btrfs"
EOF

# btrfs root for atomic desktops
cat > "/usr/lib/image-builder/bootc/disk.yaml" << EOF
mount_configuration: "none"
partition_table:
  type: "gpt"
  partitions:
    - size: "2 GiB"
      type: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
      payload_type: "filesystem"
      payload:
        type: "vfat"
        # wrong mountpoint, but isn't actually used; works around a
        # bug in `image-builder`:
        mountpoint: "/boot/efi"
        label: "ESP"
    - size: "3 GiB"
      # type is architecture dependent, `image-builder` should auto-assign
      # based on the architecture but for now we append based on TARGETARCH
      type: "${GPT_ROOT_TYPE}"
      payload_type: "btrfs"
      payload:
        subvolumes:
          - name: "root"
            mountpoint: "/"
EOF

fi

cat > "/usr/lib/bootc/install/90-install.toml" << 'EOF'
# Need systemd as the bootloader
[install]
bootloader = "systemd"
EOF

cat > "/usr/lib/dracut/dracut.conf.d/20-bootc-base.conf" << 'EOF'
# Dracut will always fail to set security.selinux xattrs at build time
# https://github.com/dracut-ng/dracut-ng/issues/1561
export DRACUT_NO_XATTR=1

# Enable composefs backend in dracut
add_dracutmodules+=" bootc "
EOF

cat > "/usr/lib/dracut/dracut.conf.d/59-altfiles.conf" << 'EOF'
# https://issues.redhat.com/browse/RHEL-49590
# On image mode systems we use nss-altfiles for passwd and group,
# this makes sure dracut uses them which also fixes kdump writing to NFS.
install_items+=" /usr/lib/passwd /usr/lib/group "
EOF

# Remove more dracut modules to reduce the size of the initramfs
cat > "/usr/lib/dracut/dracut.conf.d/20-omit-modules.conf" << 'EOF'
# FIPS is not supported on Fedora and you need to do your own build anyway
omit_dracutmodules+=" fips fips-crypto-policies "

# Do not include support from booting from a LUN SAS devices
omit_dracutmodules+=" lunmask "

# No LVM support for now
omit_dracutmodules+=" lvm "

# memstrack is for debug and development
omit_dracutmodules+=" memstrack "

# We don't include kernel module keys in the initramfs
omit_dracutmodules+=" modsign "

# NSS is not included in the initramfs
omit_dracutmodules+=" nss-softokn "
EOF

# Include systemd's hwdb
# See: https://github.com/systemd/systemd/issues/40159
# See: https://github.com/systemd/systemd/issues/40485
# cat > "/usr/lib/dracut/dracut.conf.d/20-bootc-composefs.conf" << 'EOF'
# install_items+=" /etc/udev/hwdb.bin "
# EOF

# Prepare folders in /boot
mkdir -p /boot/EFI/Linux


###############################################################################
# Changes for development go here

# secureblue: Remove mask
systemctl unmask sshd.service
# Enable sshd for bcvk
systemctl enable sshd.service

# Disable root password
passwd -d root

# Enable systemd debug shell for the initramfs & final system
cat > "/usr/lib/bootc/kargs.d/10-debug.toml" << 'EOF'
kargs = ["rd.systemd.debug_shell", "systemd.debug_shell"]
EOF

# Mask some systemd units that currently do not work well with some TPMs
# See: https://github.com/systemd/systemd/issues/40159
# See: https://github.com/systemd/systemd/issues/40485
cat > "/usr/lib/bootc/kargs.d/10-tpm2-workaround.toml" << 'EOF'
kargs = [
  "rd.systemd.mask=systemd-tpm2-setup-early.service",
  "systemd.mask=systemd-tpm2-setup-early.service",
  "systemd.mask=systemd-tpm2-setup.service",
  "systemd.mask=systemd-pcrphase.service",
  "systemd.mask=systemd-pcrproduct.service",
]
EOF
###############################################################################
