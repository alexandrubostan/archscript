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

ext4fs

pacstrap -K /mnt base linux linux-firmware vim sudo amd-ucode networkmanager
genfstab -U /mnt >> /mnt/etc/fstab

echo '%wheel      ALL=(ALL:ALL) NOPASSWD: ALL' | tee -a /mnt/etc/sudoers > /dev/null

sed -e '/en_US.UTF-8/s/^#*//' -i /mnt/etc/locale.gen
sed -e '/ro_RO.UTF-8/s/^#*//' -i /mnt/etc/locale.gen
sed -e '/ParallelDownloads/s/^#*//' -i /mnt/etc/pacman.conf

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

read -r -p "Enter hostname: " hostname
echo "$hostname" | tee /mnt/etc/hostname > /dev/null

ROOTUUID=$(blkid -s UUID -o value "$ROOT")
AMDGPUOC=$(printf 'amdgpu.ppfeaturemask=0x%x\n' "$(($(cat /sys/module/amdgpu/parameters/ppfeaturemask) | 0x4000))")
mkdir -p /mnt/etc/cmdline.d
echo "root=UUID=$ROOTUUID rw" | tee /mnt/etc/cmdline.d/root.conf > /dev/null
echo "$AMDGPUOC" | tee /mnt/etc/cmdline.d/amdgpuoc.conf > /dev/null

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

efistub () {
    mkdir -p /mnt/efi/EFI/Linux
    arch-chroot /mnt mkinitcpio -p linux
    
    efibootmgr --create --disk "$DRIVE" --part "$EFIPART" --label "Arch Linux" --loader 'EFI/Linux/arch-linux.efi' --unicode
}
systemd_boot () {
    arch-chroot /mnt bootctl install
    arch-chroot /mnt mkinitcpio -p linux
}

systemd_boot
#efistub

install_kde () {
    arch-chroot /mnt pacman -S --needed \
    breeze-gtk \
    drkonqi \
    kde-gtk-config \
    kdeplasma-addons \
    kgamma \
    kinfocenter \
    kscreen \
    ksshaskpass \
    kwallet-pam \
    kwrited \
    plasma-desktop \
    plasma-disks \
    plasma-nm \
    plasma-pa \
    plasma-systemmonitor \
    powerdevil \
    power-profiles-daemon \
    sddm-kcm \
    spectacle \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    konsole \
    dolphin \
    dolphin-plugins \
    firefox \
    chromium \
    filelight \
    ark \
    flatpak

    arch-chroot /mnt pacman -S --needed --asdeps \
    ffmpegthumbs \
    kdegraphics-thumbnailers \
    kio-admin \
    7zip
    
    systemctl enable sddm.service --root=/mnt
}

install_kde

systemctl enable fstrim.timer --root=/mnt
systemctl enable NetworkManager.service --root=/mnt

arch-chroot /mnt passwd
read -r -p "Enter username: " user
arch-chroot /mnt useradd -m -G wheel "$user"
arch-chroot /mnt passwd "$user"
