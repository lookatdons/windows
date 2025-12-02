#!/bin/bash

# Windows Server 2022 Auto-Installer Script
# Usage: bash setup.sh [1|2]
#   1 = TeddyVPS (5.1 GB, default)
#   2 = Lamp.sh (3.1 GB, faster)
# WARNING: This will WIPE your entire disk and install Windows

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Choose your image source
USE_SOURCE="${1:-1}"  # Pass 1 or 2 as argument, default is 1

if [ "$USE_SOURCE" = "1" ]; then
    IMAGE_URL="https://fr1.teddyvps.com/iso/en-us_win2022.gz"
    IMAGE_TYPE="gz"
    IMAGE_NAME="TeddyVPS Windows Server 2022"
    IMAGE_SIZE="5.1 GB"
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="Teddysun.com"
elif [ "$USE_SOURCE" = "2" ]; then
    IMAGE_URL="https://dl.lamp.sh/vhd/en-us_win2022_uefi.xz"
    IMAGE_TYPE="xz"
    IMAGE_NAME="Lamp.sh Windows Server 2022 UEFI"
    IMAGE_SIZE="3.1 GB"
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="Teddysun.com"
else
    printf "${RED}Invalid source. Usage:${NC}\n"
    printf "  bash $0 1  ${GREEN}# TeddyVPS (5.1 GB)${NC}\n"
    printf "  bash $0 2  ${GREEN}# Lamp.sh (3.1 GB, faster)${NC}\n"
    exit 1
fi

printf "${BLUE}================================${NC}\n"
printf "${BLUE}Windows Server 2022 Installer${NC}\n"
printf "${BLUE}================================${NC}\n"
printf "${GREEN}Selected: %s${NC}\n" "$IMAGE_NAME"
printf "${GREEN}Size: %s${NC}\n" "$IMAGE_SIZE"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    printf "${RED}ERROR: Please run as root (use sudo)${NC}\n"
    exit 1
fi

# Display warning
printf "${RED}⚠️  WARNING ⚠️${NC}\n"
printf "${YELLOW}This script will:${NC}\n"
printf "${YELLOW}- COMPLETELY WIPE your current Ubuntu system${NC}\n"
printf "${YELLOW}- Install Windows Server 2022${NC}\n"
printf "${YELLOW}- All current data will be PERMANENTLY DELETED${NC}\n"
echo ""
printf "Press ${GREEN}CTRL+C${NC} within 15 seconds to cancel...\n"
echo ""

for i in {15..1}; do
    printf "\r${YELLOW}Starting in %d seconds... ${NC}" "$i"
    sleep 1
done
printf "\n\n"

printf "${GREEN}[1/6] Detecting system configuration...${NC}\n"

# Detect network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
IPADDR=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
NETMASK=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f2 | head -n1)

echo "  ✓ Network Interface: $INTERFACE"
echo "  ✓ IP Address: $IPADDR/$NETMASK"
echo "  ✓ Gateway: $GATEWAY"

printf "\n${GREEN}[2/6] Installing required packages...${NC}\n"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null 2>&1

if [ "$IMAGE_TYPE" = "xz" ]; then
    apt-get install -y wget curl xz-utils pv > /dev/null 2>&1
    echo "  ✓ Packages installed (wget, curl, xz-utils, pv)"
else
    apt-get install -y wget curl gzip pv > /dev/null 2>&1
    echo "  ✓ Packages installed (wget, curl, gzip, pv)"
fi

printf "\n${GREEN}[3/6] Detecting target disk...${NC}\n"

# Detect primary disk
DISK=$(lsblk -ndo NAME,TYPE | grep disk | head -n1 | awk '{print $1}')
DISK_PATH="/dev/$DISK"
DISK_SIZE=$(lsblk -ndo SIZE $DISK_PATH)

echo "  ✓ Target disk: $DISK_PATH"
echo "  ✓ Disk size: $DISK_SIZE"

printf "\n${YELLOW}About to write to %s - This will destroy all data!${NC}\n" "$DISK_PATH"
printf "${YELLOW}Press CTRL+C within 5 seconds to cancel...${NC}\n"
sleep 5

printf "\n${GREEN}[4/6] Testing image URL...${NC}\n"
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
    exit 1
fi

printf "\n${GREEN}[5/6] Downloading and writing Windows image...${NC}\n"
printf "${BLUE}Download size: %s${NC}\n" "$IMAGE_SIZE"
printf "${BLUE}Estimated time: 10-40 minutes (depends on connection)${NC}\n"
printf "${BLUE}Source: %s${NC}\n\n" "$IMAGE_URL"

# Create a temporary fifo for progress monitoring
FIFO="/tmp/download_progress_$$"
mkfifo "$FIFO" || true

# Download and write with visible progress
echo "  → Starting download and disk write..."
echo ""

if [ "$IMAGE_TYPE" = "xz" ]; then
    # For .xz compressed images
    printf "${YELLOW}  [DOWNLOAD] Fetching image...${NC}\n"
    wget --no-check-certificate \
         --progress=bar:force:noscroll \
         --show-progress \
         -O- "$IMAGE_URL" 2>&1 | \
         tee >(
             # Show download progress
             stdbuf -oL grep --line-buffered -oP '\d+%|\d+[KMG]' | \
             while read line; do
                 printf "\r  ${BLUE}Download Progress: %s${NC}" "$line"
             done
         ) | \
         xz -d | \
         pv -s 25G -N "Writing to disk" | \
         dd of="$DISK_PATH" bs=4M oflag=direct status=none
    
    if [ $? -eq 0 ]; then
        printf "\n\n  ${GREEN}✓ Image downloaded and written successfully${NC}\n"
    else
        printf "\n\n  ${RED}✗ Download/write failed${NC}\n"
        rm -f "$FIFO"
        exit 1
    fi
else
    # For .gz compressed images
    printf "${YELLOW}  [DOWNLOAD] Fetching image...${NC}\n"
    wget --no-check-certificate \
         --progress=bar:force:noscroll \
         --show-progress \
         -O- "$IMAGE_URL" 2>&1 | \
         tee >(
             # Show download progress
             stdbuf -oL grep --line-buffered -oP '\d+%|\d+[KMG]' | \
             while read line; do
                 printf "\r  ${BLUE}Download Progress: %s${NC}" "$line"
             done
         ) | \
         gunzip | \
         pv -s 25G -N "Writing to disk" | \
         dd of="$DISK_PATH" bs=4M oflag=direct status=none
    
    if [ $? -eq 0 ]; then
        printf "\n\n  ${GREEN}✓ Image downloaded and written successfully${NC}\n"
    else
        printf "\n\n  ${RED}✗ Download/write failed${NC}\n"
        rm -f "$FIFO"
        exit 1
    fi
fi

# Cleanup
rm -f "$FIFO"

# Sync to ensure all data is written
printf "\n${GREEN}[6/6] Finalizing installation...${NC}\n"
echo "  → Syncing disk buffers (this may take a minute)..."
sync
sleep 3
echo "  ✓ Disk sync complete"
echo "  → Flushing system cache..."
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
sleep 2
echo "  ✓ Installation complete!"

echo ""
printf "${BLUE}================================${NC}\n"
printf "${GREEN}✓ Windows Server 2022 Installed${NC}\n"
printf "${BLUE}================================${NC}\n"
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
echo "  5. Login with credentials above"
echo ""
printf "${RED}═══════════════════════════════${NC}\n"
printf "${RED}  CRITICAL SECURITY WARNING${NC}\n"
printf "${RED}═══════════════════════════════${NC}\n"
printf "  ${RED}• CHANGE PASSWORD IMMEDIATELY!${NC}\n"
printf "  ${RED}• Default password is PUBLIC${NC}\n"
printf "  ${RED}• Your server WILL BE HACKED${NC}\n"
printf "  ${RED}  if you don't change it!${NC}\n"
printf "${RED}═══════════════════════════════${NC}\n"
echo ""
printf "${YELLOW}Troubleshooting:${NC}\n"
echo "  • Can't connect after 10 mins?"
echo "    → Check Upcloud VNC console"
echo "    → Test: nmap -p 3389 $IPADDR"
echo "    → Wait longer (first boot takes time)"
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
sync
reboot -f
