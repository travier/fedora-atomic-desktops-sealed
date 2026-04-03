# Sealed bootable container images for the Fedora Atomic Desktops

**Warning: Those are work in progress, unofficial development images for testing purposes.**

## Dependencies

- podman
- [bcvk](https://github.com/bootc-dev/bcvk) (only v0.10.0 tested as working right now)
  - See: <https://github.com/bootc-dev/bcvk/issues/234>
  - See: <https://github.com/bootc-dev/bcvk/issues/237>
- [virt-fw-vars](https://github.com/rhuefi/qemu-ovmf-secureboot) (`python3-virt-firmware` on Fedora)

## How to

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
