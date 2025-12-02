#!/bin/bash

# Windows Server 2022 Auto-Installer Script
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
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="Teddysun.com"
elif [ "$USE_SOURCE" = "2" ]; then
    IMAGE_URL="https://dl.lamp.sh/vhd/en-us_win2022_uefi.xz"
    IMAGE_TYPE="xz"
    IMAGE_NAME="Lamp.sh Windows Server 2022 UEFI"
    DEFAULT_USER="Administrator"
    DEFAULT_PASS="Teddysun.com"
else
    printf "${RED}Invalid source. Use: $0 1 (TeddyVPS) or $0 2 (Lamp.sh)${NC}\n"
    exit 1
fi

printf "${BLUE}================================${NC}\n"
printf "${BLUE}Windows Server 2022 Installer${NC}\n"
printf "${BLUE}================================${NC}\n"
printf "${GREEN}Image: %s${NC}\n" "$IMAGE_NAME"
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
    apt-get install -y wget curl xz-utils > /dev/null 2>&1
    echo "  ✓ Packages installed (wget, curl, xz-utils)"
else
    apt-get install -y wget curl gzip > /dev/null 2>&1
    echo "  ✓ Packages installed (wget, curl, gzip)"
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
if curl -sI "$IMAGE_URL" | grep -q "200"; then
    echo "  ✓ Image URL is accessible"
else
    printf "${RED}  ✗ Cannot access image URL${NC}\n"
    exit 1
fi

printf "\n${GREEN}[5/6] Downloading and writing Windows image...${NC}\n"
printf "${BLUE}This will take 10-40 minutes depending on connection${NC}\n"
printf "${BLUE}Source: %s${NC}\n" "$IMAGE_URL"
echo ""

# Download and write directly to disk
echo "  → Downloading and writing to $DISK_PATH..."

if [ "$IMAGE_TYPE" = "xz" ]; then
    # For .xz compressed images
    if wget --no-check-certificate --show-progress -O- "$IMAGE_URL" 2>&1 | \
       tee >(grep --line-buffered -oP '\d+%' >&2) | \
       xz -d | dd of="$DISK_PATH" bs=4M status=none oflag=direct; then
        printf "\n  ✓ Image written successfully\n"
    else
        printf "\n${RED}  ✗ Download/write failed${NC}\n"
        exit 1
    fi
else
    # For .gz compressed images
    if wget --no-check-certificate --show-progress -O- "$IMAGE_URL" 2>&1 | \
       tee >(grep --line-buffered -oP '\d+%' >&2) | \
       gunzip | dd of="$DISK_PATH" bs=4M status=none oflag=direct; then
        printf "\n  ✓ Image written successfully\n"
    else
        printf "\n${RED}  ✗ Download/write failed${NC}\n"
        exit 1
    fi
fi

# Sync to ensure all data is written
printf "\n${GREEN}[6/6] Finalizing installation...${NC}\n"
sync
echo "  ✓ Syncing disk buffers..."
sleep 2
echo "  ✓ Flushing cache..."
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
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
echo "  2. SSH connection will be lost"
echo "  3. Wait 5-10 minutes for Windows first boot"
echo "  4. Connect via RDP client to: $IPADDR:3389"
echo "  5. Login with credentials above"
echo ""
printf "${RED}IMPORTANT SECURITY:${NC}\n"
printf "  ${RED}• CHANGE PASSWORD IMMEDIATELY after first login!${NC}\n"
printf "  ${RED}• Default password is publicly known${NC}\n"
printf "  ${RED}• Update Windows and enable firewall${NC}\n"
echo ""
printf "${YELLOW}Troubleshooting:${NC}\n"
echo "  • If RDP doesn't work after 10 minutes:"
echo "    - Check Upcloud console/VNC to see boot status"
echo "    - Verify port 3389 is open: nmap -p 3389 $IPADDR"
echo "    - Windows might need more time for first boot"
echo ""

# Countdown to reboot
printf "${YELLOW}Rebooting to Windows...${NC}\n"
for i in {10..1}; do
    printf "\r  Rebooting in %d seconds... (CTRL+C to cancel) " "$i"
    sleep 1
done

echo ""
printf "${GREEN}Initiating reboot...${NC}\n"
sleep 1

# Force reboot
sync
reboot -f
