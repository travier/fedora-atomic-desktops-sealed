# Sealed bootable container images for the Fedora Atomic Desktops

**Warning: Those are work in progress, unofficial development images for
testing purposes.**

## Dependencies

- podman
- [bcvk](https://github.com/bootc-dev/bcvk) (only v0.10.0 tested right now)

## How to

1. Generate keys for signing with Secure Boot (using [sbctl](https://github.com/foxboron/sbctl)):

```
just keys
```

2. Sign systemd-boot with your Secure Boot key:

```
just sign-secure-boot
```

3. Build a sealed container image from the Fedora Silverblue unofficial bootable container image:

```
just build silverblue
```

4. Install the container image to a QCOW2 disk image:

```
just qcow2 silverblue
```

5. Boot the QCOW2 image with libvirt:

```
just libvirt silverblue
```

## Licenses

See [LICENSES](LICENSES).
