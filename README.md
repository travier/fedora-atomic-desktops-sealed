# Sealed bootable container images for the Fedora Atomic Desktops

**Warning: Those are work in progress, unofficial development images for testing purposes.**

## How to test the pre-built disk images

- Download the pre-built disk image:

```
cd ~/.local/share/libvirt/images
oras pull quay.io/fedora-atomic-desktops-sealed/silverblue:44.20260330.0.qcow2
oras pull quay.io/fedora-atomic-desktops-sealed/kinoite:44.20260330.0.qcow2
```

- Boot the QCOW2 image with libvirt:

```
cd fedora-atomic-desktops-sealed
just libvirt silverblue
just libvirt kinoite
```

## How to build your own

### Dependencies for building

- podman
- [bcvk](https://github.com/bootc-dev/bcvk) (only v0.10.0 tested as working right now)
  - See: <https://github.com/bootc-dev/bcvk/issues/234>
- [virt-fw-vars](https://github.com/rhuefi/qemu-ovmf-secureboot) (`python3-virt-firmware` on Fedora)

We will be able to use `bcvk` more once <https://github.com/bootc-dev/bcvk/issues/237> is fixed.

### Steps

- Generate keys for signing with Secure Boot (using [sbctl](https://github.com/foxboron/sbctl)):

```
just generate-secure-boot-keys
```

- Sign systemd-boot with the Secure Boot key:

```
just sign-secure-boot
```

- Build the container image with the tools to build and sign UKIs

```
just build-tools
```

- Build a sealed container image derived from the Fedora Silverblue or Kinoite unofficial bootable container image:

```
just build silverblue
just build kinoite
```

- Install the container image to a QCOW2 disk image:

```
just qcow2 silverblue
just qcow2 kinoite
```

- Move the QCOW2 image to libvirt image store:

```
just move-qcow2-libvirt-images silverblue
just move-qcow2-libvirt-images kinoite
```

- Generate an OVMF variable file for EDK2 with the Secure Boot keys included:

```
just generate-ovmf-vars
```

- Boot the QCOW2 image with libvirt:

```
just libvirt silverblue
just libvirt kinoite
```

## Licenses

See [LICENSES](LICENSES).
