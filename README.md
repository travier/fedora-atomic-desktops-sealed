# Sealed bootable container images for the Fedora Atomic Desktops

**Warning: Those are work in progress, unofficial development images for testing purposes.**

Container images are available both on `quay.io` and `ghcr.io`:

- <https://quay.io/organization/fedora-atomic-desktops-sealed>
- <https://github.com/travier?tab=packages&repo_name=fedora-atomic-desktops-sealed>

## Why are there `-amd`, `-intel` and `-nvidia` images?

For those images, the initramfs (part of the UKI) only includes the kernel modules and firmwares for the corresponding GPU vendor, thus reducing its size.
The size of the UKI has an important impact on the boot time.
See [issue #23](https://github.com/travier/fedora-atomic-desktops-sealed/issues/23).

Note that this only impacts what is included in the initramfs.
The system content is the same for all images with all kernel modules and firmwares included.

The container images without a suffix include a UKI with all the kernel modules and firmwares for all hardware devices supported on Fedora.
Use those if you don't know what your GPU vendor is or if you need support for multiple GPUs in the initrd.

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

### Manual installation

Until we get support ready in Anaconda, we will use using `systemd-repart` to partition the system and `boot install to-filesystem` to install the sealed image.

To get full Secure Boot support, we will manually install shim.
This will be done via bootupd in the future.

First, make sure that you have enough free space to pull the container image.
If not, and if you have enough RAM, mount a tmpfs:

```console
mount -t tmpfs -o size=10240M containers /var/lib/containers/storage/
chcon "system_u:object_r:container_var_lib_t:s0" /var/lib/containers/storage
```

Then partition the disk using the systemd-repart configuration from this repo:

```console
podman pull quay.io/fedora-atomic-desktops-sealed/kinoite:44

systemd-repart --empty=force --definitions=repart.d /dev/nvme0n1 --dry-run=no --discard=no
```

Then mount the partitions to the expected location:

```console
cryptsetup open /dev/nvme0n1p2 root
# Empty passphrase
mount /dev/mapper/root /mnt/
mkdir /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot/
```

Then pull the container image and use it to install the system:

```console
podman pull quay.io/fedora-atomic-desktops-sealed/kinoite-intel:44

podman run --rm --privileged --pid=host --ipc=host \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers:/var/lib/containers -v /dev:/dev \
  -v /:/run/host \
  quay.io/fedora-atomic-desktops-sealed/kinoite-intel:44 \
  bootc install to-filesystem \
    --source-imgref=containers-storage:quay.io/fedora-atomic-desktops-sealed/kinoite-intel:44 \
    --bootloader=systemd --composefs-backend --skip-finalize \
    /run/host/mnt/
```

Then manually fix the installation to setup shim:

```console
# Copies shim and related files from the Live ISO
cp /usr/lib/efi/shim/16.1-5/EFI/BOOT/* /mnt/boot/EFI/BOOT/
cp -r /usr/lib/efi/shim/16.1-5/EFI/fedora /mnt/boot/EFI/
cp /usr/lib/efi/shim/16.1-5/EFI/fedora/mmx64.efi /mnt/boot/EFI/BOOT/
mv /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/fedora/grubx64.efi
rmdir /mnt/boot/EFI/systemd
```

Then enable the boot menu timeout in systemd-boot config:

```console
sed -i 's/#timeout 3/timeout 3/' /mnt/boot/loader/loader.conf
```

And finally, enroll the signing key from this repo using mokutil:

```console
openssl x509 -in keys/db/db.pem -inform PEM -out db.der -outform DER
mokutil --import db.der
# Enter a short password, QWERTY compatible, you'll need to type it once on reboot
mokutil --list-new
```

Then unmount the partitions and reboot:

```console
sync
umount /mnt/boot/
umount /mnt
cryptsetup close root
reboot
```

On reboot you will get a full screen dialog asking you to setup a new EFI boot entry.
Let it do it.

Then you will be asked to enroll a key using MOK (password input likely in QWERTY).

Finally, once booted, you can setup automatic LUKS unlocking bound to TPM PCRs:

```console
systemd-cryptenroll --tpm2-device list
systemd-cryptenroll --tpm2-device=/dev/tpmrm0 --tpm2-pcrs=7:sha256 /dev/nvme0n1p2
```

Reboot to give it a try.

## How to build your own

### Containers

Start with building a sealed container.

#### Steps

- Generate keys for signing with Secure Boot (using [sbctl](https://github.com/foxboron/sbctl)):

```
just generate-secure-boot-keys
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

### Disk Images

After you have the container built you can continue with turning it into a disk image. We recommend using [image-builder](https://github.com/osbuild/image-builder) as it supports many output formats but you can also use [bcvk](.

There are a few ways to build disk images, either through [image-builder](https://github.com/osbuild/image-builder) or alternatively through [bcvk](https://github.com/bootc-dev/bcvk).

#### `image-builder`

##### Dependencies

- podman
- `image-builder`, either as a package; or as its container.
- [virt-fw-vars](https://github.com/rhuefi/qemu-ovmf-secureboot) (`python3-virt-firmware` on Fedora)

##### Steps

Have your container built and available either locally or on a registry, then run `image-builder`:

```
sudo image-builder build --bootc-ref quay.io/fedora-atomic-desktops-sealed/bootc-rawhide:latest qcow2
```

Various output formats are available; amongst them `qcow2`, `ami`, `ova`, `raw` etc.

Note that blueprint customizations are generally disabled for sealed container images at the moment; there is tight coupling between filesystem contents, partition layout, and the kernel arguments in the UKI. We might enable a subset of customizations [in the future](https://github.com/osbuild/image-builder/issues/2560).

#### `bcvk`

Using the bootc virtualization toolkit.

#### Dependencies

- podman
- [bcvk](https://github.com/bootc-dev/bcvk) (only v0.10.0 tested as working right now)
  - See: <https://github.com/bootc-dev/bcvk/issues/234>
- [virt-fw-vars](https://github.com/rhuefi/qemu-ovmf-secureboot) (`python3-virt-firmware` on Fedora)

We will be able to use `bcvk` more once <https://github.com/bootc-dev/bcvk/issues/237> is fixed.

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

#### UKI Addons

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
