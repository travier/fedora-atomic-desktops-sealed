# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

ARG BASE=overridden
ARG SYSTEMDBOOT=overridden
ARG TOOLS=overridden

FROM $SYSTEMDBOOT as systemd-boot

FROM $BASE as rootfs

RUN --mount=type=tmpfs,target=/run \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var \
    <<EORUN
set -euo pipefail
set -x

# We don't want openh264
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
rm -vrf "/usr/lib/bootupd/updates"

# Mount the root filesystem read-write
# Enable btrfs compression
cat > "/usr/lib/bootc/kargs.d/10-rootfs-kargs.toml" << 'EOF'
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

# Rebuild the initramfs to get bootc-initramfs-setup
kver=$(cd "/usr/lib/modules" && echo *)
dracut -vf --install "/etc/passwd /etc/group" "/usr/lib/modules/$kver/initramfs.img" "$kver"

# Enable sshd for bcvk
systemctl enable sshd.service

# Disable root password for development
passwd -d root

# Prepare folders in /boot
mkdir -p /boot/EFI/Linux
EORUN

# Replace Fedora's systemd-boot with our signed one
COPY --from=systemd-boot /systemd-bootx64.efi /usr/lib/systemd/boot/efi/systemd-bootx64.efi

FROM rootfs as lint
RUN bootc container lint

# Rechunk container image to ensure that we compute the correct composefs hash
# - Use more layers (128)
# - Ignore legacy ostree folders
FROM quay.io/coreos/chunkah AS chunkah
RUN --mount=from=rootfs,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build \
            --max-layers 128 \
            --prune /ostree \
            --prune /sysroot/ostree \
            > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive as rootfs-chunked
LABEL containers.bootc 1
LABEL org.opencontainers.image.title="Fedora Atomic Desktop Sealed"
LABEL org.opencontainers.image.source="https://github.com/travier/fedora-atomic-desktops-sealed"
LABEL org.opencontainers.image.licenses="MIT"
LABEL quay.expires-after="4w"
ENV container=oci
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

FROM $TOOLS as sealed-uki
RUN --mount=type=tmpfs,target=/run \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=secret,id=secureboot_key \
    --mount=type=secret,id=secureboot_crt \
    --mount=type=bind,from=rootfs-chunked,src=/,target=/run/target \
    <<EORUN
set -euo pipefail
set -x

target="/run/target"
output="/boot/EFI/Linux"
secrets="/run/secrets"

# Find the kernel version (needed for output filename)
kver=$(bootc container inspect --rootfs "${target}" --json | jq -r '.kernel.version')
if [ -z "$kver" ] || [ "$kver" = "null" ]; then
  echo "Error: No kernel found" >&2
  exit 1
fi

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
bootc container ukify "${containerukifyargs[@]}" "${missing_verity[@]}" -- "${ukifyargs[@]}"
EORUN

# Copy UKI to our final image
FROM rootfs-chunked as final
COPY --from=sealed-uki /boot/EFI/Linux /boot/EFI/Linux
