#!/bin/bash
# Build FNOS flash package for ECB-PR51
# Usage: ./build-flash-pkg.sh /path/to/fnos_Mainland-PE_arm_1.1.19_nanopi-r5s_602.img

set -e

BASE_IMG="$1"
if [ -z "$BASE_IMG" ]; then
    echo "Usage: $0 /path/to/fnos_Mainland-PE_arm_1.1.19_nanopi-r5s_602.img"
    exit 1
fi

echo "=== Building FNOS flash package for ECB-PR51 ==="
echo "Base image: $BASE_IMG"

# Decompress if needed
if [[ "$BASE_IMG" == *.gz ]]; then
    gunzip -kf "$BASE_IMG"
    BASE_IMG="${BASE_IMG%.gz}"
fi

mkdir -p output

# Set up loop device
LOOP=$(sudo losetup -f --show "$BASE_IMG")
sudo partprobe $LOOP 2>/dev/null || true
sudo fdisk -l $LOOP > output/partition-table.txt

# Extract partitions
sudo dd if=$LOOP of=output/idbloader.img bs=512 count=16384 2>/dev/null
sudo dd if=$LOOP of=output/uboot.img bs=512 skip=16384 count=16384 2>/dev/null

P1=$(sudo fdisk -l $LOOP | grep "${LOOP##*/}p1" | awk '{print $2}')
P2=$(sudo fdisk -l $LOOP | grep "${LOOP##*/}p2" | awk '{print $2}')
P2S=$(sudo fdisk -l $LOOP | grep "${LOOP##*/}p2" | awk '{print $4}')

if [ -n "$P1" ] && [ -n "$P2" ]; then
    BOOT_SIZE=$((P2 - P1))
    sudo dd if=$LOOP of=output/boot.img bs=512 skip=$P1 count=$BOOT_SIZE 2>/dev/null
fi
if [ -n "$P2" ] && [ -n "$P2S" ]; then
    sudo dd if=$LOOP of=output/rootfs.img bs=512 skip=$P2 count=$P2S 2>/dev/null
fi

sudo losetup -d $LOOP

# Replace DTB in rootfs
mkdir -p mnt
sudo mount -o loop,offset=$((P2 * 512)) output/rootfs.img mnt
if [ -f fnos_leez_3568.dtb ]; then
    sudo cp fnos_leez_3568.dtb mnt/boot/dtb/rockchip/ 2>/dev/null || \
        sudo cp fnos_leez_3568.dtb mnt/boot/dtb/ 2>/dev/null || \
        echo "WARNING: Could not find DTB directory in rootfs"
    echo "DTB replaced"
fi
# Copy firmware
sudo mkdir -p mnt/lib/firmware/brcm
sudo cp brcm/* mnt/lib/firmware/brcm/ 2>/dev/null || true
echo "Firmware copied"
sudo umount mnt

# Create complete raw image
cp "$BASE_IMG" output/fnos-ecb-pr51-raw.img

echo ""
echo "=== Flash package ready ==="
ls -lh output/
echo ""
echo "To flash:"
echo "  rkdeveloptool db output/idbloader.img"
echo "  rkdeveloptool wl 0x4000 output/uboot.img"
echo "  rkdeveloptool wl 0x8000 output/boot.img"
echo "  rkdeveloptool wl 0x200000 output/rootfs.img"
echo "  rkdeveloptool rd"
