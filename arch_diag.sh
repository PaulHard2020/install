#!/bin/bash
# Диагностика не загружающейся системы Arch Linux (в chroot)

echo "==> Проверка UUID раздела (должен совпадать с тем, что в bootloader)"
lsblk -f | grep cryptroot
echo

echo "==> Проверка /etc/fstab"
cat /etc/fstab
echo

echo "==> Проверка /boot/loader/entries/arch.conf"
cat /boot/loader/entries/arch.conf
echo

echo "==> Проверка mkinitcpio.conf на правильность HOOKS"
grep "^HOOKS=" /etc/mkinitcpio.conf
echo

echo "==> Проверка crypttab (может отсутствовать при sd-encrypt — это ок)"
[[ -f /etc/crypttab ]] && cat /etc/crypttab || echo "crypttab не найден — это нормально при sd-encrypt"
echo

echo "==> Проверка initramfs наличия"
ls -lh /boot/initramfs-linux.img
echo

echo "==> Проверка наличия загрузчика"
bootctl status
echo

echo "==> Проверка journalctl последних сообщений (если доступен журнал)"
journalctl -xb -n 50 || echo "journalctl недоступен"
