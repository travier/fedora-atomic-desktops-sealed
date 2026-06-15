# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

ARG BASE=overridden
ARG TOOLS=overridden

# Capture scripts from the git repo
FROM scratch as scripts
COPY scripts /

FROM $BASE as rootfs-base

ARG TARGETARCH

# General changes done to the base image
RUN --mount=type=tmpfs,target=/run \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var \
    --mount=type=bind,from=scripts,src=/,target=/run/scripts \
    /run/scripts/prepare-rootfs.sh

# Make sure we pass the lints
FROM rootfs-base as lint
RUN --mount=type=bind,from=scripts,src=/,target=/run/scripts \
    /run/scripts/bootc-container-lint.sh

# Rebuild the initramfs and move kernel to the root
FROM rootfs-base as initrd
RUN --mount=type=bind,from=scripts,src=/,target=/run/scripts \
    /run/scripts/rebuild-initrd.sh
RUN mv /usr/lib/modules/*/vmlinuz /vmlinuz

# Remove the kernel and initramfs from the base image
FROM rootfs-base as rootfs
RUN --mount=type=bind,from=scripts,src=/,target=/run/scripts \
    /run/scripts/remove-kernel-initrd.sh

# Rechunk container image to ensure that we compute the correct composefs hash
# - Use more layers (128)
# - Ignore legacy ostree folders
FROM quay.io/coreos/chunkah AS chunkah
RUN --mount=from=rootfs,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build \
            --max-layers 256 \
            --prune /ostree \
            --prune /sysroot/ostree \
            --output oci:/run/src/out

# Create the final base image from the rechunked oci output
FROM oci:out as rootfs-chunked
LABEL containers.bootc 1
LABEL org.opencontainers.image.title="Fedora Atomic Desktop Sealed"
LABEL org.opencontainers.image.source="https://github.com/travier/fedora-atomic-desktops-sealed"
LABEL org.opencontainers.image.licenses="MIT"
LABEL quay.expires-after="4w"
ENV container=oci
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

# Build and sign UKI
FROM $TOOLS as sealed-uki
# Copy kernel & initramfs from earlier stage
COPY --from=initrd /vmlinuz /vmlinuz
COPY --from=initrd /initramfs /initramfs
RUN --mount=type=tmpfs,target=/run \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=secret,id=secureboot_key \
    --mount=type=secret,id=secureboot_crt \
    --mount=type=bind,from=rootfs-chunked,src=/,target=/run/target,ro \
    --mount=type=bind,from=scripts,src=/,target=/run/scripts \
    /run/scripts/uki.sh

# Copy UKI to our final image
FROM rootfs-chunked as final
COPY --from=sealed-uki /boot/EFI/Linux /boot/EFI/Linux
