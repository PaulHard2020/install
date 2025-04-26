#!/bin/bash
# arch_clean_install.sh
# Чистая установка Arch Linux с LUKS2, BTRFS и NVIDIA драйверами

set -e

# Проверка UEFI
[ ! -d /sys/firmware/efi ] && { echo "Требуется UEFI!"; exit 1; }

# Ввод параметров
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter password for root: " ROOT_PASSWORD
echo
read -sp "Enter password for $USERNAME: " PASSWORD
echo

# Выбор диска
DISKS=$(lsblk -d -p -n -l -o NAME,SIZE)
echo -e "\nAvailable disks:"
echo "$DISKS"
read -p "Select disk (example, /dev/nvme0n1): " DISK

LOCALE_EN="en_US.UTF-8"
LOCALE_RU="ru_RU.UTF-8"
TIMEZONE="Europe/Moscow"

# Подтверждение
echo -e "\nAll data on $DISK will deleted!"
read -p "Continue? (y/N): " confirm
[[ "$confirm" != "y" ]] && exit 1

# Разметка диска
sgdisk -Z $DISK
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:ROOT $DISK

# Шифрование и файловые системы
cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --iter-time 5000 ${DISK}2
cryptsetup open --allow-discards ${DISK}2 cryptroot
mkfs.btrfs -L "ArchRoot" /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

# Создание subvolume'ов
echo "Create subvolumes"
subvols=("@" "@home" "@snapshots" "@log" "@pkg" "@swap" "@tmp" "@opt")
for vol in ${subvols[@]}; do
    btrfs subvolume create "/mnt/${vol}"
done
echo "Subvolumes were created"
umount /mnt

# Монтирование с параметрами
echo "mount with parameters"
mount_opts="defaults,noatime,ssd,discard=async,compress=zstd"
mount -o $mount_opts,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,var/tmp,opt,.swap,.snapshots}

mount -o $mount_opts,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o $mount_opts,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o $mount_opts,subvol=@log /dev/mapper/cryptroot /mnt/var/log
mount -o $mount_opts,subvol=@tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o $mount_opts,subvol=@opt /dev/mapper/cryptroot /mnt/opt

mount -o defaults,noatime,ssd,discard=async,nodatacow,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o defaults,noatime,ssd,discard=async,nodatacow,subvol=@swap /dev/mapper/cryptroot /mnt/.swap

# Файл подкачки
echo "make swap"
swapfile="/mnt/.swap/swapfile"
truncate -s 0 "$swapfile"
sleep 5
chattr +C "$swapfile"
sleep 5
btrfs property set "$swapfile" compression none
sleep 5
fallocate -l 4G "$swapfile"
sleep 5
chmod 600 "$swapfile"
sleep 5
mkswap "$swapfile"
sleep 5
swapon "$swapfile"

# EFI раздел
echo "EFI"
mkfs.fat -F32 -n "EFI" ${DISK}1
mount ${DISK}1 /mnt/boot

# Установка базовой системы
echo "Install base system"
pacstrap -K /mnt base linux linux-firmware mkinitcpio btrfs-progs sudo neovim \
          systemd systemd-boot networkmanager nvidia nvidia-utils nvidia-settings

# Настройка fstab
echo "fstab"
genfstab -U /mnt >> /mnt/etc/fstab

UUID=$(blkid -s UUID -o value ${DISK}2)

arch-chroot /mnt /bin/bash <<EOF
# Настройка локали и времени
echo "locale"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "$LOCALE_EN UTF-8" > /etc/locale.gen
echo "$LOCALE_RU UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE_EN" > /etc/locale.conf
echo "KEYMAP=en" > /etc/vconsole.conf

# Настройка хоста
echo "Host"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Пароли
echo "passwords"
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,storage,power,audio,video "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Initramfs
echo "HOOKS"
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Настройка загрузчика
echo "bootloader"
bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
console-mode max
editor no
LOADER

#UUID=\$(blkid -s UUID -o value ${DISK}2)
cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options rd.luks.name=\$UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard rw nvidia-drm.modeset=1
ENTRY

# Дополнительные настройки
systemctl enable NetworkManager
#btrfs filesystem defragment -r -czstd /
EOF

# Завершение
umount -R /mnt
cryptsetup close cryptroot
echo -e "\n✅ Installation complete! To apply the changes:"
echo -e "1. reboot"
echo -e "2. After logging in, do: sudo pacman -Syu"

