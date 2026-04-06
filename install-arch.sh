#!/bin/bash
# Arch Linux 完整安装脚本（Zen + UKI + AMD GPU 完整驱动）
# CPU: Intel E5-2697v4
# GPU: AMD RX5500XT
# 磁盘: NVMe /dev/nvme0n1
# Swapfile: /swap/.swapfile
# 桌面: GNOME
# 引导: systemd-boot

set -e

DISK="/dev/nvme0n1"
BOOT_SIZE="+512M"
ROOT_SUBVOL="@"
HOME_SUBVOL="@home"
SWAP_SIZE="32G"

echo "==> 清空磁盘"
sgdisk -Z $DISK

echo "==> 创建分区"
sgdisk -n1:1M:$BOOT_SIZE -t1:ef00 -c1:"EFI System" $DISK
sgdisk -n2:0:0 -t2:8300 -c2:"Linux Root" $DISK

echo "==> 格式化分区"
mkfs.fat -F32 ${DISK}p1
mkfs.btrfs -f ${DISK}p2

echo "==> 挂载 Btrfs 并创建子卷"
mount ${DISK}p2 /mnt
btrfs su cr /mnt/$ROOT_SUBVOL
btrfs su cr /mnt/$HOME_SUBVOL
umount /mnt

mount -o noatime,compress=zstd,ssd,space_cache=v2,subvol=$ROOT_SUBVOL ${DISK}p2 /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,ssd,space_cache=v2,subvol=$HOME_SUBVOL ${DISK}p2 /mnt/home
mkdir /mnt/boot
mount ${DISK}p1 /mnt/boot

echo "==> 安装基础系统和 GNOME + AMD GPU 驱动"
pacstrap /mnt base base-devel linux-zen linux-zen-headers intel-ucode btrfs-progs \
networkmanager sudo vim git htop neovim gnome gdm xorg mesa lib32-mesa \
vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver \
libvdpau-va-gl lib32-libvdpau-va-gl opencl-mesa pipewire pipewire-pulse wireplumber

echo "==> 生成 fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> 配置系统"
arch-chroot /mnt /bin/bash <<'EOF'
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
echo "arch-zen-gnome" > /etc/hostname

# 配置语言
sed -i '/en_US.UTF-8 UTF-8/s/^#//; /zh_CN.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=zh_CN.UTF-8" > /etc/locale.conf

# 用户和密码
echo "root:root" | chpasswd
useradd -m -G wheel user
echo "user:user" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# 启用网络和 GDM
systemctl enable NetworkManager
systemctl enable gdm
EOF

echo "==> 创建 swapfile 在 /swap/.swapfile"
arch-chroot /mnt /bin/bash <<'EOF'
mkdir -p /swap
chattr +C /swap
fallocate -l 32G /swap/.swapfile
chmod 600 /swap/.swapfile
mkswap /swap/.swapfile
swapon /swap/.swapfile
echo "/swap/.swapfile none swap defaults 0 0" >> /etc/fstab
EOF

echo "==> 安装 systemd-boot"
arch-chroot /mnt bootctl --path=/boot install

echo "==> 生成 UKI 镜像"
arch-chroot /mnt /bin/bash <<'EOF'
UKI_FILE="/boot/vmlinuz-linux-zen-uki"
dracut --uefi --kver $(uname -r) --force $UKI_FILE
EOF

echo "==> 自动获取根分区 UUID"
ROOT_UUID=$(blkid -s UUID -o value ${DISK}p2)

echo "==> 配置 systemd-boot loader"
cat <<EOF > /mnt/boot/loader/loader.conf
default arch
timeout 3
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title   Arch Linux Zen UKI
linux   /vmlinuz-linux-zen-uki
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw quiet splash
EOF

echo "==> 安装完成，重启即可进入 GNOME + AMD GPU 驱动"