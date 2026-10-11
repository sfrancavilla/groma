# If the laptop will not boot

Written before the Limine migration (`setup-limine-snapshots.sh`), so it exists
before it is needed. Read it once now; keep the Arch USB stick nearby until the
new boot entry has been proven.

## First, the easy way: the old entry

Until the migration's last step retires it, the old loader is still on the disk.

1. Power on and press **F12** repeatedly (Framework's boot menu).
2. Pick **Arch Linux (Limine)** - the old entry.

It boots the kernel and initramfs that were current when the backup was taken.
If that works, nothing is lost: log in and put `/boot` back as below, from the
running system.

## If nothing on the disk boots: from the Arch USB

1. Plug in the Arch ISO stick, power on, **F12**, pick the USB.
2. At the root prompt:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot          # your disk password
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount /dev/nvme0n1p1 /mnt/boot
ls /mnt/home/stefano/boot-backup-*                  # pick the newest
```

3. Put the boot partition back exactly as it was:

```bash
B=/mnt/home/stefano/boot-backup-YYYYMMDD-HHMM       # the one listed above
rm -rf /mnt/boot/*
tar -C /mnt/boot -xpf "$B/boot.tar"
cp "$B/mkinitcpio.conf" /mnt/etc/mkinitcpio.conf
```

4. Make the old entry first in the firmware again. `efibootmgr.txt` in the
   backup shows the order as it was; the old entry was `0005`:

```bash
efibootmgr -o 0005,2001,2002,2003
umount -R /mnt; reboot
```

## What is in a backup folder

| File | What |
|---|---|
| `boot.tar` | the whole boot partition: loader, menu, kernel, initramfs |
| `efibootmgr.txt` | the firmware's boot entries and order (`efibootmgr -v`) |
| `mkinitcpio.conf` | the initramfs settings before the overlay hook was added |
| `cmdline` | the kernel command line the machine booted with |
