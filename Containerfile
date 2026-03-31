ARG BASE=quay.io/fedora-ostree-desktops/kinoite:44.20260330.0
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
# Install systemd-boot (will be replaced by the signed version later)
dnf install -y fsverity-utils systemd-boot-unsigned

# Remove rpm-ostree
dnf remove -y rpm-ostree

# Remove Discover's rpm-ostree backend
dnf remove -y plasma-discover-rpm-ostree

# Install latest bootc release
# https://bodhi.fedoraproject.org/updates/FEDORA-2026-cfa95147df
dnf upgrade -y --enablerepo=updates-testing --refresh --advisory=FEDORA-2026-cfa95147df

# Uninstall bootupd (no support for systemd-boot yet)
rpm -e bootupd
rm -vrf "/usr/lib/bootupd/updates"

# mkdir -p "/usr/lib/bootc/kargs.d"
cat > "/usr/lib/bootc/kargs.d/10-rootfs-kargs.toml" << 'EOF'
# Mount the root filesystem read-write
# Enable btrfs compression
kargs = ["rw", "rootflags=compress=zstd:1"]
EOF

# Default to btrfs
# mkdir -p "/usr/lib/bootc/install"
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

COPY /systemd-bootx64.efi /usr/lib/systemd/boot/efi/systemd-bootx64.efi

FROM rootfs as lint
RUN bootc container lint

# Use more layers (128)
# Ignore legacy ostree folders
FROM quay.io/coreos/chunkah AS chunkah
RUN --mount=from=rootfs,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build \
            --max-layers 128 \
            --prune /ostree \
            --prune /sysroot/ostree \
            > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive as rootfs-clean
LABEL containers.bootc 1
LABEL ostree.bootable 1
LABEL org.opencontainers.image.title="Fedora Kinoite UKI"
LABEL org.opencontainers.image.source="https://github.com/travier/fedora-kinoite"
LABEL org.opencontainers.image.licenses="MIT"
ENV container=oci
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

FROM rootfs as sealed-uki
RUN --mount=type=tmpfs,target=/run \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=bind,from=rootfs-clean,src=/,target=/run/target \
    --mount=type=secret,id=secureboot_key \
    --mount=type=secret,id=secureboot_cert <<EORUN
set -euo pipefail
set -x

# We don't want openh264
rm -f "/etc/yum.repos.d/fedora-cisco-openh264.repo"

# Install ukify & signing tools
dnf install -y systemd-ukify sbsigntools
dnf clean all

target="/run/target"
output="/boot/EFI/Linux"
secrets="/run/secrets"

mkdir -p /boot/EFI/Linux

# Find the kernel version (needed for output filename)
kver=$(bootc container inspect --rootfs "${target}" --json | jq -r '.kernel.version')
if [ -z "$kver" ] || [ "$kver" = "null" ]; then
  echo "Error: No kernel found" >&2
  exit 1
fi

# Baseline ukify options
ukifyargs=(--measure
           --json pretty
           --output "${output}/${kver}.efi")

# Signing options, we use sbsign by default
ukifyargs+=(--signtool sbsign
            --secureboot-private-key "${secrets}/secureboot_key"
            --secureboot-certificate "${secrets}/secureboot_cert")

# Baseline container ukify options
containerukifyargs=(--rootfs "${target}")

# Build the UKI using bootc container ukify
# This computes the composefs digest, reads kargs from kargs.d, and invokes ukify
bootc container ukify "${containerukifyargs[@]}" "${missing_verity[@]}" -- "${ukifyargs[@]}"
EORUN

FROM rootfs-clean as final
COPY --from=sealed-uki /boot/EFI/Linux /boot/EFI/Linux
