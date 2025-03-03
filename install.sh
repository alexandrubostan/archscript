#!/bin/bash

set -eo pipefail

EFI='/dev/nvme0n1p1'
ROOT='/dev/nvme0n1p2'
DRIVE='/dev/nvme0n1'
EFIPART=1

ext4fs () {
    mkfs.ext4 "$ROOT"
    mount "$ROOT" /mnt
    mount --mkdir "$EFI" /mnt/efi
}

ext4fs_luks () {
    cryptsetup luksFormat "$ROOT"
    cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open "$ROOT" root
    mkfs.ext4 /dev/mapper/root
    mount /dev/mapper/root /mnt
    mount --mkdir "$EFI" /mnt/efi
}

ext4fs
#ext4fs_luks

pacstrap -K /mnt base linux linux-firmware nano sudo amd-ucode networkmanager

sed -e '/en_US.UTF-8/s/^#*//' -i /mnt/etc/locale.gen
sed -e '/ro_RO.UTF-8/s/^#*//' -i /mnt/etc/locale.gen

arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
arch-chroot /mnt hwclock --systohc
arch-chroot /mnt locale-gen

echo 'LANG=en_US.UTF-8' | tee /mnt/etc/locale.conf > /dev/null
echo 'LC_TIME=ro_RO.UTF-8' | tee -a /mnt/etc/locale.conf > /dev/null
echo 'POWERDEVIL_NO_DDCUTIL=1' | tee -a /mnt/etc/environment > /dev/null

tee -a /mnt/etc/hosts > /dev/null << EOF
127.0.0.1        localhost
::1              localhost
EOF

echo 'archlelz' | tee /mnt/etc/hostname > /dev/null

AMDGPUOC=$(printf 'amdgpu.ppfeaturemask=0x%x\n' "$(($(cat /sys/module/amdgpu/parameters/ppfeaturemask) | 0x4000))")
echo "rw $AMDGPUOC" | tee /mnt/etc/kernel/cmdline > /dev/null

echo '/dev/gpt-auto-root  /  ext4  defaults,noatime  0  1' | tee /mnt/etc/fstab > /dev/null

tee /mnt/etc/mkinitcpio.d/linux.preset > /dev/null << EOF
# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

#default_config="/etc/mkinitcpio.conf"
#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"
#default_options=""
EOF

tee /mnt/etc/mkinitcpio.conf > /dev/null << EOF
MODULES=()
BINARIES=()
FILES=()
HOOKS=(systemd autodetect microcode modconf keyboard block filesystems fsck)

COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-v -5 --long)
EOF

efistub () {
    mkdir -p /mnt/efi/EFI/Linux
    arch-chroot /mnt mkinitcpio -p linux
    
    efibootmgr -c -d "$DRIVE" -p "$EFIPART" -l 'EFI/Linux/arch-linux.efi' -u
}

systemd_boot () {
    arch-chroot /mnt bootctl install
    arch-chroot /mnt mkinitcpio -p linux
}

systemd_boot
#efistub

arch-chroot /mnt pacman -S --needed plasma-desktop kwrited kwallet-pam sddm-kcm konsole dolphin dolphin-plugins \
                                    kscreen plasma-nm plasma-pa breeze-gtk kde-gtk-config spectacle xdg-desktop-portal-gtk xdg-desktop-portal-kde \
                                    plasma-systemmonitor plasma-disks kinfocenter firefox

systemctl enable sddm.service --root=/mnt
systemctl enable fstrim.timer --root=/mnt
systemctl enable NetworkManager.service --root=/mnt

arch-chroot /mnt passwd
arch-chroot /mnt useradd -m -G wheel alexb
arch-chroot /mnt passwd alexb
