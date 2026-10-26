# If the machine will not boot, or an update broke it

For machines set up with `setup-limine-snapshots.sh`: Limine lists snapper
snapshots in its boot menu, so the first way out is always the same - boot the
system as it was before. Keep this note somewhere off the machine it is meant
to recover; it is in the repository for that reason:
https://github.com/sfrancavilla/groma/blob/main/system/BOOT-RECOVERY.md

## 1. Boot a snapshot from the menu

Every pacman transaction makes a pre and a post snapshot, and each one with a
matching kernel gets a boot entry.

1. Power on. When Limine's menu appears, press an arrow key to stop the
   3-second countdown.
2. Under **Arch Linux**, open **Snapshots** with Enter.
3. Pick the newest snapshot from **before** the change that broke things -
   a `pre` snapshot is labelled with the pacman command that followed it -
   then **linux**, and Enter.
4. Unlock the disk as usual.

The snapshot boots read-only with a throwaway writable layer on top
(`findmnt /` says `overlay`). Nothing you do in it is kept. It is for
checking that this is the version you want, and for step 2.

## 2. Make that snapshot the system again

Still booted into the snapshot, in a terminal:

```bash
sudo limine-snapper-restore
```

It asks which snapshot to restore, replaces the `@` subvolume with it
(`RESTORE_METHOD=replace` in `/etc/limine-snapper-sync.conf`), and adds a
**backup** entry to the boot menu holding the system you just replaced - so a
restore can itself be undone. Reboot normally afterwards.

Only `/` is restored. `/home`, `/var/log` and the package cache are separate
subvolumes and are not touched.

## 3. If the menu itself does not appear

The firmware boots `\EFI\limine\limine_x64.efi` (entry **Limine**). If that
entry is ever lost, the same loader is also installed as the firmware's
fallback, `\EFI\BOOT\BOOTX64.EFI`: press **F12** at power-on and pick the
disk itself rather than a named entry.

## 4. If nothing on the disk boots: from the Arch USB

The boot partition can always be regenerated from the installed system.

1. Plug in the Arch ISO stick, power on, **F12**, pick the USB.
2. Find your partitions with `lsblk -f`: the boot partition is the small
   `vfat` one, the system the `crypto_LUKS` one (or `btrfs`, if the disk is not
   encrypted). The names below are an NVMe laptop's; yours may differ.
3. At the root prompt:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot          # the crypto_LUKS partition; your disk password
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount /dev/nvme0n1p1 /mnt/boot                      # the vfat partition
arch-chroot /mnt
limine-update                                       # kernels, initramfs, limine.conf
limine-snapper-sync                                 # the snapshot entries
exit
umount -R /mnt; reboot
```

If `@` itself is the problem, mount a snapshot instead of `@` in the second
line - `-o subvol=@snapshots/<N>/snapshot` - to look around, and use
`limine-snapper-restore` from a snapshot boot (step 2) to make it permanent.

## The backup from the migration

`setup-limine-snapshots.sh` copies the boot partition to `~/boot-backup-<date>/`
before it changes anything. Keep it until the new menu has booted both normally
and into a snapshot; after that it is for reference, not for restoring - its
kernel goes out of date with the first kernel update.
