#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

set -euxo pipefail

# We can not ship openh264 in the image
rm -f "/etc/yum.repos.d/fedora-cisco-openh264.repo"

# Install fsverity utils to make it easier to check things
# Install systemd-boot (will be replaced by the signed version in a later stage)
dnf install -y fsverity-utils systemd-boot-unsigned

# Remove rpm-ostree and the backends in GNOME Software and Plasma Discover
dnf remove -y \
    rpm-ostree \
    rpm-ostree-libs \
    gnome-software-rpm-ostree \
    plasma-discover-rpm-ostree

# Install latest bootc release
dnf upgrade -y --enablerepo=updates-testing --refresh bootc

# Uninstall bootupd (no support for systemd-boot yet)
rpm -e bootupd
rm -vrf "/usr/lib/bootupd"
# Legacy ostree folder
rm -vrf "/usr/lib/ostree-boot"
# Remove GRUB2
rpm -e --nodeps grub2-common grub2-efi-ia32 grub2-efi-x64 grub2-pc \
    grub2-pc-modules grub2-tools grub2-tools-minimal

# Mount the root filesystem read-write
# Enable btrfs compression
cat > "/usr/lib/bootc/kargs.d/10-rootfs.toml" << 'EOF'
kargs = ["rw", "rootflags=compress=zstd:1"]
EOF

# Default to btrfs
cat > "/usr/lib/bootc/install/80-rootfs.toml" << 'EOF'
[install.filesystem.root]
type = "btrfs"
EOF

# Dracut will always fail to set security.selinux xattrs at build time
# https://github.com/dracut-ng/dracut-ng/issues/1561
cat > "/usr/lib/dracut/dracut.conf.d/20-bootc-base.conf" << 'EOF'
export DRACUT_NO_XATTR=1
EOF

# Enable composefs backend in dracut
cat > "/usr/lib/dracut/dracut.conf.d/20-bootc-composefs.conf" << 'EOF'
add_dracutmodules+=" bootc "
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
# We don't include kernel module keys in the initrd
omit_dracutmodules+=" modsign "
# NSS is not included in the initrd
omit_dracutmodules+=" nss-softokn "
EOF

# Prepare folders in /boot
mkdir -p /boot/EFI/Linux

###############################################################################
# Changes for development go here

# Enable sshd for bcvk
systemctl enable sshd.service

# Disable root password
passwd -d root

# Enable systemd debug shell for the initrd & final system
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
