# Sealed bootable container images for the Fedora Atomic Desktops

**Warning: Those are work in progress, unofficial development images for testing purposes.**

Container images are available both on `quay.io` and `ghcr.io`:

- <https://quay.io/organization/fedora-atomic-desktops-sealed>
- <https://github.com/travier?tab=packages&repo_name=fedora-atomic-desktops-sealed>

## How to test the pre-built disk images

- Download the pre-built disk image:

```
cd ~/.local/share/libvirt/images
# Update as needed by looking at the versions available in the registry
VERSION=44.20260416.0
oras pull "quay.io/fedora-atomic-desktops-sealed/silverblue:${VERSION}.qcow2"
oras pull "quay.io/fedora-atomic-desktops-sealed/kinoite:${VERSION}.qcow2"
```

- Boot the QCOW2 image with libvirt:

```
cd fedora-atomic-desktops-sealed
just libvirt silverblue
just libvirt kinoite
```

## Testing on real hardware

There is currently no installation ISO available for those images.
If you want to test them on real hardware, you will have to use `bootc install` from another live environment to install them.
You can use the Fedora CoreOS live ISO for example.
Notice: bootc 1.14.1 or later is required.

If you want to enroll your Secure Boot keys in your firmware, take a look at [sbctl](https://github.com/foxboron/sbctl).
Make sure to read the [Option ROM section](https://github.com/Foxboron/sbctl/wiki/FAQ#option-rom) to avoid "soft bricking" your hardware.

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

### UKI Addons

The kernel command line is part of the UKI and can not be changed as it is signed.
You can build a UKI addon to add kernel command line arguments without having to rebuild the UKI.
This is useful to set the keyboard layout for example: `vconsole.keymap=fr`.
Be careful with what you sign with your Secure Boot key as we currently have no mecanism in place to revoke them.

```
just uki-addon keymap-fr "vconsole.keymap=fr foo bar"
```

You can then install your addon in the ESP, either:

- globally for all UKIs: `/boot/loader/addons/keymap-fr.addon.efi`
- or only for a single UKI: `/boot/EFI/Linux/bootc/bootc_composefs-<hash>.efi.extra.d/keymap-fr.addon.efi`

See [systemd-stub's man page](https://www.freedesktop.org/software/systemd/man/latest/systemd-stub.html) for examples.
In the future, we will likely [teach bootc how to manage UKI addons](https://github.com/travier/fedora-atomic-desktops-sealed/issues/13).

## Licenses

See [LICENSES](LICENSES).
