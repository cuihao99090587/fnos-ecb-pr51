# FNOS for Lenovo ECB-PR51 (Leez SBC PR51 / RK3568)

基于官方 `fnos_Mainland-PE_arm_1.1.19_nanopi-r5s_602.img.gz` 修改 DTB 适配 ECB-PR51。

## 固件说明
- 基镜像: fnos_Mainland-PE_arm_1.1.19_nanopi-r5s_602.img.gz
- 修改: 替换设备树（DTB），配置以太网/WiFi/BT
- 原镜像支持: HDMI、USB
- 来源: BSP 工程师提供

## 文件清单

| 文件 | 说明 |
|------|------|
| `fnos_leez_3568.dtb` | ECB-PR51 设备树（替换原 DTB） |
| `brcm/BCM4345C5.hcd` | BT 固件 (55KB) |
| `brcm/brcmfmac43456-sdio.bin` | WiFi 固件 (485KB) |
| `brcm/brcmfmac43456-sdio.clm_blob` | 信道配置 (7KB) |
| `brcm/brcmfmac43456-sdio.txt` | NVRAM 板级配置 (2KB) |

## 制作线刷包

### 方法一：替换 DTB（推荐）
1. 下载官方镜像 `fnos_Mainland-PE_arm_1.1.19_nanopi-r5s_602.img.gz`
2. 解压得到 `.img` 文件
3. 挂载 rootfs 分区，替换 `/boot/dtb/rockchip/` 下的 DTB 为本目录的 `fnos_leez_3568.dtb`
4. 刷入 eMMC

### 方法二：rkdeveloptool 线刷
```bash
rkdeveloptool db idbloader.img
rkdeveloptool wl 0x4000 uboot.img
rkdeveloptool wl 0x8000 boot.img
rkdeveloptool wl 0x200000 rootfs.img
rkdeveloptool rd
```

## 刷后操作
```bash
# 复制 WiFi/BT 固件
cp /path/to/brcm/* /lib/firmware/brcm/
# 重启后 WiFi + BT 生效
```

## 默认信息
- IP: DHCP 自动获取
- 登录: 默认 FNOS 账号密码
