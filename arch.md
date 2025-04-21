# Arch Linux: Установка с LUKS + Btrfs

---

## 1. Подготовка

### Выбор диска

```bash
lsblk
```

Допустим, диск — `/dev/sda`

> ⚠️ Уничтожит все данные на диске

```bash
wipefs -a /dev/sda
```

---

## 2. Разметка диска (GPT)

```bash
gdisk /dev/sda
```

Создай:

- `EFI` — 512M (тип `ef00`)
- `LUKS` — всё остальное (тип `8300`)

---

## 3. Шифрование LUKS + маппинг

```bash
cryptsetup luksFormat /dev/sda2
cryptsetup open /dev/sda2 cryptroot
```

---

## 4. Создание Btrfs

```bash
mkfs.btrfs -L ArchLinux /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
```

### Создание subvolume'ов (в т.ч. для log, tmp, opt, swap, pkg)

```bash
btrfs subvolume create /mnt/@              # корневая система
btrfs subvolume create /mnt/@home          # домашняя директория
btrfs subvolume create /mnt/@snapshots     # для Snapper
btrfs subvolume create /mnt/@log           # логи системы
btrfs subvolume create /mnt/@pkg           # кэш пакетов pacman
btrfs subvolume create /mnt/@swap          # под файл подкачки
btrfs subvolume create /mnt/@tmp           # временные файлы (переживают перезагрузку)
btrfs subvolume create /mnt/@opt           # сторонние приложения
umount /mnt
```


### Пример монтирования subvolume'ов Btrfs

| Subvolume   | Точка монтирования      | Параметры монтирования                                                | Комментарий                                        |
|-------------|-------------------------|-----------------------------------------------------------------------|----------------------------------------------------|
| `@`         | `/`                     | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@`           | Корень системы                                     |
| `@home`     | `/home`                 | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@home`       | Домашние каталоги                                  |
| `@snapshots`| `/.snapshots`           | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@snapshots`  | Для snapper / Timeshift                            |
| `@log`      | `/var/log`              | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@log`        | Системные логи, можно отключить сжатие при желании |
| `@tmp`      | `/var/tmp`              | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@tmp`        | Временные файлы, сжатие по желанию                 |
| `@opt`      | `/opt`                  | `defaults,noatime,ssd,discard=async,compress=zstd,subvol=@opt`        | Сторонние программы                                |
| `@pkg`      | `/var/cache/pacman/pkg` | `defaults,noatime,ssd,discard=async,nodatacow,subvol=@pkg`            | Кэш pacman, уже сжат — CoW и сжатие не нужны       |
| `@swap`     | `/swap`                 | `defaults,noatime,ssd,discard=async,nodatacow,subvol=@swap`           | Для swapfile, обязательно без CoW и без сжатия     |

> 💡 Параметры `noatime, ssd, discard=async` можно применять ко всем subvolume'ам для улучшения производительности.

### Перемонтирование с параметрами сжатия и nodatacow для нужных точек

```bash
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache/pacman/pkg,var/tmp,opt,swap}

mount -o compress=zstd,subvol=@home      /dev/mapper/cryptroot /mnt/home
mount -o compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o compress=zstd,subvol=@log       /dev/mapper/cryptroot /mnt/var/log
mount -o compress=zstd,subvol=@tmp       /dev/mapper/cryptroot /mnt/var/tmp
mount -o compress=zstd,subvol=@opt       /dev/mapper/cryptroot /mnt/opt
mount -o subvol=@pkg,nodatacow /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o subvol=@swap,nodatacow /dev/mapper/cryptroot /mnt/swap
```

> ⚠️ `nodatacow` отключает Copy-on-Write, рекомендуется для `pkg` и `swap` ради производительности и стабильности.

### Создание файла подкачки

```bash
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile  # отключаем CoW
btrfs property set /mnt/swap/swapfile compression none
fallocate -l 4G /mnt/swap/swapfile  # или нужный размер
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile
```

### EFI раздел

```bash
mkfs.fat -F32 /dev/sda1
mount /dev/sda1 /mnt/boot
```

### Генерация fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Проверь файл:

```bash
nvim /mnt/etc/fstab
```

Если записи для `swapfile` нет, добавь вручную:

```fstab
/swap/swapfile none swap defaults 0 0
```

---

## 5. Установка базовой системы

```bash
pacstrap -K /mnt base linux linux-firmware mkinitcpio btrfs-progs sudo neovim systemd systemd-boot networkmanager reflector
```

---

## 6. Настройка системы

```bash
arch-chroot /mnt
```

### Timezone и локали

```bash
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# /etc/locale.gen:
ru_RU.UTF-8 UTF-8
en_US.UTF-8 UTF-8
locale-gen

# /etc/locale.conf:
LANG=ru_RU.UTF-8
```

### Консоль

```bash
echo KEYMAP=ru > /etc/vconsole.conf
```

### Хостнейм

```bash
echo myarch > /etc/hostname

# /etc/hosts:
127.0.0.1   localhost
::1         localhost
127.0.1.1   myarch.localdomain myarch
```

---

## 7. Обновление зеркал через Reflector

```bash
reflector --country Russia --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
```

---

## 8. mkinitcpio

### /etc/mkinitcpio.conf

```ini
HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)
```

```bash
mkinitcpio -P
```

---

## 9. Установка загрузчика

```bash
bootctl install
```

### /boot/loader/loader.conf

```ini
default arch
timeout 3
console-mode max
editor no
```

### /boot/loader/entries/arch.conf

```ini
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options rd.luks.name=<UUID>=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
```

> UUID диска можно получить через:

```bash
blkid /dev/sda2
```

---

## 10. Сеть и пользователь

```bash
passwd
useradd -mG wheel myuser
passwd myuser
EDITOR=nvim visudo  # Разкомментировать %wheel ALL=(ALL) ALL
systemctl enable NetworkManager
```

---

## 11. Установка paru (AUR helper)

```bash
pacman -S --needed base-devel git
cd /home/myuser
sudo chown -R myuser:myuser .
su - myuser
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
```

> После этого можно использовать `paru` вместо `pacman`, в том числе для установки AUR пакетов.

---

## 12. Выход и перезагрузка

```bash
exit
umount -R /mnt
reboot
```

---

Если хочешь, добавлю разделы про `snapper`, `bspwm`, `Hyprland`, `XDG`, `fonts`, `paru`, `wayland-utils`, и т.д.

