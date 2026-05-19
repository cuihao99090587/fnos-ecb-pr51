#!/bin/bash
#==========================================================================
# rebuild-fnos.sh - based on ophub's rebuild method
# Build FNOS for Lenovo ECB-PR51 by modifying official NanoPi R5S image
#==========================================================================
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${1:-}"
OUTPUT="${SELF}/output"
SECTOR=512

STEPS="[\e[32mSTEPS\e[0m]"
INFO="[\e[93mINFO\e[0m]"
ERROR="[\e[31mERROR\e[0m]"

error_msg() { echo -e "${ERROR} $*" >&2; exit 1; }
process_msg() { echo -e "${STEPS} $(date +%T) | $*"; }

# Check root
[[ "$(id -u)" == 0 ]] || error_msg "Please run as root: ./rebuild-fnos.sh"

# Phase 1: Download base image
process_msg "(1/6) Download FNOS base image"
mkdir -p "${OUTPUT}"
if [[ -n "${BASE_URL}" ]]; then
    wget -q --show-progress "${BASE_URL}" -O "${OUTPUT}/fnos_base.img.gz"
    gunzip -f "${OUTPUT}/fnos_base.img.gz"
    BASE_IMG="${OUTPUT}/fnos_base.img"
else
    BASE_IMG="$(ls ${OUTPUT}/fnos_base.img 2>/dev/null || true)"
    [[ -z "${BASE_IMG}" ]] && error_msg "No base image found. Provide URL or place in output/"
fi

# Phase 2: Extract partitions
process_msg "(2/6) Extract partitions"
LOOP=$(losetup -f --show "${BASE_IMG}")
partprobe ${LOOP} 2>/dev/null || true

# Read partition offsets
P1_START=$(fdisk -l ${LOOP} | grep "${LOOP##*/}p1" | awk '{print $2}')
P1_END=$(fdisk -l ${LOOP} | grep "${LOOP##*/}p1" | awk '{print $3}')
P2_START=$(fdisk -l ${LOOP} | grep "${LOOP##*/}p2" | awk '{print $2}')

# Extract
dd if=${LOOP} of="${OUTPUT}/idbloader.img" bs=${SECTOR} count=16384 2>/dev/null
dd if=${LOOP} of="${OUTPUT}/uboot.img" bs=${SECTOR} skip=16384 count=16384 2>/dev/null
dd if=${LOOP} of="${OUTPUT}/boot.img" bs=${SECTOR} skip=${P1_START} count=$((P2_START - P1_START)) 2>/dev/null
dd if=${LOOP} of="${OUTPUT}/rootfs.img" bs=${SECTOR} skip=${P2_START} 2>/dev/null
losetup -d ${LOOP}

echo "  idbloader: $(du -h ${OUTPUT}/idbloader.img | cut -f1)"
echo "  uboot:     $(du -h ${OUTPUT}/uboot.img | cut -f1)"  
echo "  boot:      $(du -h ${OUTPUT}/boot.img | cut -f1)"
echo "  rootfs:    $(du -h ${OUTPUT}/rootfs.img | cut -f1)"

# Phase 3: Replace DTB in boot partition
process_msg "(3/6) Replace device tree"
DTB="${SELF}/fnos_leez_3568.dtb"
[[ -f "${DTB}" ]] || error_msg "DTB file not found: ${DTB}"

debugfs -w -R "rm /dtb/rockchip/rk3568-nanopi-r5s.dtb" "${OUTPUT}/boot.img" 2>/dev/null || true
debugfs -w -R "rm /dtb/rockchip/rk3568-nanopi-r5c.dtb" "${OUTPUT}/boot.img" 2>/dev/null || true
debugfs -w -R "write ${DTB} /dtb/rockchip/rk3568-nanopi-r5s.dtb" "${OUTPUT}/boot.img" 2>/dev/null
echo "  DTB replaced: fnos_leez_3568.dtb → rk3568-nanopi-r5s.dtb"

# Phase 4: Add firmware to rootfs
process_msg "(4/6) Copy WiFi/BT firmware"
FW_DIR="${SELF}/brcm"
[[ -d "${FW_DIR}" ]] || error_msg "Firmware directory not found: ${FW_DIR}"

mkdir -p /tmp/fnos_mnt
mount -o loop "${OUTPUT}/rootfs.img" /tmp/fnos_mnt
mkdir -p /tmp/fnos_mnt/lib/firmware/brcm
cp ${FW_DIR}/* /tmp/fnos_mnt/lib/firmware/brcm/
sync
umount /tmp/fnos_mnt
rmdir /tmp/fnos_mnt
echo "  Firmware copied: $(ls ${FW_DIR} | wc -l) files"

# Phase 5: Rebuild final image
process_msg "(5/6) Rebuild final image"
BOOT_SIZE=$(stat -c%s "${OUTPUT}/boot.img")
ROOTFS_SIZE=$(stat -c%s "${OUTPUT}/rootfs.img")
TOTAL_SIZE=$((P1_START * SECTOR + BOOT_SIZE + 32768 * SECTOR + ROOTFS_SIZE + 34 * SECTOR))

FINAL_IMG="${OUTPUT}/fnos-ecb-pr51-raw.img"
truncate -s ${TOTAL_SIZE} "${FINAL_IMG}"

# Part 1: header
dd if="${BASE_IMG}" of="${FINAL_IMG}" bs=${SECTOR} count=${P1_START} conv=notrunc 2>/dev/null
# Part 2: boot
dd if="${OUTPUT}/boot.img" of="${FINAL_IMG}" bs=${SECTOR} seek=${P1_START} conv=notrunc 2>/dev/null
# Part 3: gap
dd if="${BASE_IMG}" of="${FINAL_IMG}" bs=${SECTOR} skip=${P1_END} seek=${P1_END} count=$((P2_START - P1_END)) conv=notrunc 2>/dev/null
# Part 4: rootfs
dd if="${OUTPUT}/rootfs.img" of="${FINAL_IMG}" bs=${SECTOR} seek=${P2_START} conv=notrunc 2>/dev/null
# Part 5: rest
dd if="${BASE_IMG}" of="${FINAL_IMG}" bs=${SECTOR} skip=$((P2_START + ROOTFS_SIZE / SECTOR)) seek=$((P2_START + ROOTFS_SIZE / SECTOR)) conv=notrunc 2>/dev/null

echo "  Final image: $(du -h ${FINAL_IMG} | cut -f1)"

# Phase 6: Package
process_msg "(6/6) Create flash package"
mkdir -p "${OUTPUT}/flash-pkg"
cp "${OUTPUT}/idbloader.img" "${OUTPUT}/flash-pkg/"
cp "${OUTPUT}/uboot.img" "${OUTPUT}/flash-pkg/"
cp "${OUTPUT}/boot.img" "${OUTPUT}/flash-pkg/"
cp "${OUTPUT}/rootfs.img" "${OUTPUT}/flash-pkg/"
cp "${FINAL_IMG}" "${OUTPUT}/flash-pkg/"

cat > "${OUTPUT}/flash-pkg/README.txt" << 'PKGEOF'
=== FNOS flash package for Lenovo ECB-PR51 ===

rkdeveloptool flashing:
  rkdeveloptool db idbloader.img
  rkdeveloptool wl 0x4000 uboot.img
  rkdeveloptool wl 0x10000 boot.img
  rkdeveloptool wl 0xba800 rootfs.img
  rkdeveloptool rd

Or dd:
  dd if=fnos-ecb-pr51-raw.img of=/dev/mmcblk1 bs=4M status=progress

WiFi/BT firmware already included in rootfs.
PKGEOF

echo ""
echo "=== Build complete! ==="
echo "Flash package: ${OUTPUT}/flash-pkg/"
ls -lh "${OUTPUT}/flash-pkg/" | grep -v "^total"
