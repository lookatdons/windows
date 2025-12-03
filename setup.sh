#!/bin/bash

# Windows Server Auto-Installer Script
# Usage: bash setup.sh [2022|2025]
#   2022 = Windows Server 2022 (default)
#   2025 = Windows Server 2025
# WARNING: This will WIPE your entire disk and install Windows

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Choose Windows version
WIN_VERSION="${1:-2022}"

if [ "$WIN_VERSION" = "2022" ]; then
    IMAGE_URL="https://trading.dons.ovh/Windows_Server_2022_VirtIO_Intel.gz"
    IMAGE_NAME="Windows Server 2022 VirtIO"
    IMAGE_SIZE="~4-5 GB"
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="(Check documentation or try common defaults)"
elif [ "$WIN_VERSION" = "2025" ]; then
    IMAGE_URL="https://trading.dons.ovh/Windows_Server_2025_VirtIO_Intel.gz"
    IMAGE_NAME="Windows Server 2025 VirtIO"
    IMAGE_SIZE="~4-5 GB"
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="(Check documentation or try common defaults)"
else
    printf "${RED}Invalid Windows version. Usage:${NC}\n"
    printf "  bash $0 2022  ${GREEN}# Install Windows Server 2022 (default)${NC}\n"
    printf "  bash $0 2025  ${GREEN}# Install Windows Server 2025${NC}\n"
    exit 1
fi

IMAGE_TYPE="gz"

printf "${BLUE}════════════════════════════════${NC}\n"
printf "${BLUE}  Windows Server Installer${NC}\n"
printf "${BLUE}════════════════════════════════${NC}\n"
printf "${GREEN}Version: %s${NC}\n" "$IMAGE_NAME"
printf "${GREEN}Size: %s${NC}\n" "$IMAGE_SIZE"
printf "${GREEN}Source: trading.dons.ovh${NC}\n"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    printf "${RED}ERROR: Please run as root (use sudo)${NC}\n"
    exit 1
fi

# Display warning
printf "${RED}⚠️  WARNING ⚠️${NC}\n"
printf "${YELLOW}This script will:${NC}\n"
printf "${YELLOW}- COMPLETELY WIPE your current system${NC}\n"
printf "${YELLOW}- Install %s${NC}\n" "$IMAGE_NAME"
printf "${YELLOW}- ALL data will be PERMANENTLY DELETED${NC}\n"
echo ""
printf "Press ${GREEN}CTRL+C${NC} within 15 seconds to cancel...\n"
echo ""

for i in {15..1}; do
    printf "\r${YELLOW}Starting in %d seconds... ${NC}" "$i"
    sleep 1
done
printf "\n\n"

printf "${GREEN}[1/7] Checking boot mode compatibility...${NC}\n"

# Detect boot mode (UEFI or Legacy BIOS)
if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
    echo "  ✓ Boot mode: UEFI"
    echo "  ℹ VirtIO image supports both UEFI and Legacy BIOS"
else
    BOOT_MODE="Legacy BIOS"
    echo "  ✓ Boot mode: Legacy BIOS"
    echo "  ℹ VirtIO image supports both UEFI and Legacy BIOS"
fi

printf "\n${GREEN}[2/7] Detecting system configuration...${NC}\n"

# Detect network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
IPADDR=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
NETMASK=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f2 | head -n1)

echo "  ✓ Network Interface: $INTERFACE"
echo "  ✓ IP Address: $IPADDR/$NETMASK"
echo "  ✓ Gateway: $GATEWAY"

printf "\n${GREEN}[3/7] Installing required packages...${NC}\n"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null 2>&1
apt-get install -y wget curl gzip > /dev/null 2>&1
echo "  ✓ Packages installed (wget, curl, gzip)"

printf "\n${GREEN}[4/7] Detecting target disk...${NC}\n"

# Detect primary disk
DISK=$(lsblk -ndo NAME,TYPE | grep disk | head -n1 | awk '{print $1}')
DISK_PATH="/dev/$DISK"
DISK_SIZE=$(lsblk -ndo SIZE $DISK_PATH)

echo "  ✓ Target disk: $DISK_PATH"
echo "  ✓ Disk size: $DISK_SIZE"

printf "\n${YELLOW}About to write to %s - This will destroy all data!${NC}\n" "$DISK_PATH"
printf "${YELLOW}Press CTRL+C within 5 seconds to cancel...${NC}\n"
sleep 5

printf "\n${GREEN}[5/7] Testing image URL...${NC}\n"
echo "  → Checking: $IMAGE_URL"

if curl -sI "$IMAGE_URL" | grep -q "200"; then
    FILE_SIZE=$(curl -sI "$IMAGE_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
    if [ -n "$FILE_SIZE" ]; then
        FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
        echo "  ✓ Image URL is accessible"
        echo "  ✓ File size: ${FILE_SIZE_MB} MB"
    else
        echo "  ✓ Image URL is accessible"
    fi
else
    printf "${RED}  ✗ Cannot access image URL${NC}\n"
    printf "${RED}  Please check your internet connection or try again later${NC}\n"
    exit 1
fi

printf "\n${GREEN}[6/7] Downloading and writing Windows image...${NC}\n"
printf "${BLUE}Download size: %s${NC}\n" "$IMAGE_SIZE"
printf "${BLUE}Estimated time: 10-40 minutes (depends on connection)${NC}\n"
printf "${BLUE}Source: %s${NC}\n\n" "$IMAGE_URL"

# Download and write with visible progress
echo "  → Starting download and disk write..."
echo ""

printf "${YELLOW}  Downloading (gzip compressed)...${NC}\n\n"

# Get file size for progress bar
CONTENT_LENGTH=$(curl -sI "$IMAGE_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')

if [ -n "$CONTENT_LENGTH" ]; then
    # Show download progress in background
    wget --no-check-certificate \
         --progress=bar:force \
         -O- "$IMAGE_URL" 2>&1 | \
         stdbuf -oL tr '\r' '\n' | \
         stdbuf -oL grep --line-buffered '%' | \
         stdbuf -oL tail -n 1 | \
         while IFS= read -r line; do
             printf "\r  ${BLUE}Progress: %s${NC}" "$line"
         done &
    
    # Actual download and write
    wget --no-check-certificate -q -O- "$IMAGE_URL" | gunzip | dd of="$DISK_PATH" bs=4M iflag=fullblock status=progress oflag=direct
    
    RESULT=$?
    wait
    printf "\n"
else
    # Fallback without size
    wget --no-check-certificate -q -O- "$IMAGE_URL" | gunzip | dd of="$DISK_PATH" bs=4M iflag=fullblock status=progress oflag=direct
    RESULT=$?
fi

if [ $RESULT -eq 0 ]; then
    printf "\n  ${GREEN}✓ Image downloaded and written successfully${NC}\n"
else
    printf "\n  ${RED}✗ Download/write failed${NC}\n"
    exit 1
fi

# Sync to ensure all data is written
printf "\n${GREEN}[7/7] Finalizing installation...${NC}\n"
echo "  → Syncing disk buffers (this may take a minute)..."

# Try to sync, but don't fail if it errors (system might be transitioning)
if command -v sync &> /dev/null; then
    sync 2>/dev/null || echo "  ⚠ Sync command unavailable (this is OK)"
fi

sleep 3
echo "  ✓ Disk operations complete"

# Try to flush cache
if [ -w /proc/sys/vm/drop_caches ]; then
    echo "  → Flushing system cache..."
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
fi

sleep 2
echo "  ✓ Installation complete!"

echo ""
printf "${BLUE}════════════════════════════════${NC}\n"
printf "${GREEN}✓ %s Installed${NC}\n" "$IMAGE_NAME"
printf "${BLUE}════════════════════════════════${NC}\n"
echo ""
printf "${YELLOW}Connection Information:${NC}\n"
printf "  • IP Address: ${GREEN}%s${NC}\n" "$IPADDR"
printf "  • RDP Port: ${GREEN}%s${NC}\n" "3389"
printf "  • Username: ${GREEN}%s${NC}\n" "$DEFAULT_USER"
printf "  • Password: ${GREEN}%s${NC}\n" "$DEFAULT_PASS"
echo ""
printf "${YELLOW}Next Steps:${NC}\n"
echo "  1. System will reboot in 10 seconds"
echo "  2. SSH connection will be LOST"
echo "  3. Wait 5-10 minutes for Windows first boot"
echo "  4. Connect via RDP client:"
printf "     ${GREEN}mstsc /v:%s${NC} (Windows)\n" "$IPADDR"
printf "     ${GREEN}xfreerdp /v:%s /u:%s${NC} (Linux)\n" "$IPADDR" "$DEFAULT_USER"
echo "  5. Login with Administrator credentials"
echo ""
printf "${RED}═══════════════════════════════${NC}\n"
printf "${RED}  CRITICAL SECURITY WARNING${NC}\n"
printf "${RED}═══════════════════════════════${NC}\n"
printf "  ${RED}• CHANGE PASSWORD IMMEDIATELY!${NC}\n"
printf "  ${RED}• Default passwords may be PUBLIC${NC}\n"
printf "  ${RED}• Your server WILL BE HACKED${NC}\n"
printf "  ${RED}  if you don't change it!${NC}\n"
printf "${RED}═══════════════════════════════${NC}\n"
echo ""
printf "${YELLOW}Troubleshooting:${NC}\n"
echo "  • Can't connect after 10 mins?"
echo "    → Check console via Upcloud VNC"
echo "    → Test port: nmap -p 3389 $IPADDR"
echo "    → Wait longer (first boot takes time)"
echo "  • VirtIO drivers included for KVM/QEMU"
echo ""

# Countdown to reboot
printf "${YELLOW}Rebooting to Windows in:${NC}\n"
for i in {10..1}; do
    printf "\r  ${RED}%d${NC} seconds (CTRL+C to cancel)... " "$i"
    sleep 1
done

echo ""
printf "${GREEN}Initiating system reboot...${NC}\n"
sleep 2

# Force reboot
sync 2>/dev/null || true
reboot -f
