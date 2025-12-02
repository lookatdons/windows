#!/bin/bash

# Windows Server 2022 Auto-Installer Script
# WARNING: This will WIPE your entire disk and install Windows
# Make sure you have backups before proceeding!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_URL="https://eu2.vpssh.xyz/Windows_Server_2022_VirtIO_Intel.gz"
RDP_PASSWORD="${1:-Administrator}"  # Can be passed as argument

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Windows Server 2022 Installer${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Please run as root (use sudo)${NC}"
    exit 1
fi

# Display warning
echo -e "${RED}⚠️  WARNING ⚠️${NC}"
echo -e "${YELLOW}This script will:${NC}"
echo -e "${YELLOW}- COMPLETELY WIPE your current Ubuntu system${NC}"
echo -e "${YELLOW}- Install Windows Server 2022${NC}"
echo -e "${YELLOW}- All current data will be PERMANENTLY DELETED${NC}"
echo ""
echo -e "Press ${GREEN}CTRL+C${NC} within 15 seconds to cancel..."
echo ""

for i in {15..1}; do
    echo -ne "\r${YELLOW}Starting in $i seconds... ${NC}"
    sleep 1
done
echo ""

echo ""
echo -e "${GREEN}[1/5] Detecting system configuration...${NC}"

# Detect network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
IPADDR=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
NETMASK=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f2 | head -n1)

# Get DNS servers
DNS1=$(grep nameserver /etc/resolv.conf | head -n1 | awk '{print $2}')
DNS2=$(grep nameserver /etc/resolv.conf | sed -n '2p' | awk '{print $2}')
[ -z "$DNS2" ] && DNS2="8.8.8.8"

echo "  ✓ Network Interface: $INTERFACE"
echo "  ✓ IP Address: $IPADDR/$NETMASK"
echo "  ✓ Gateway: $GATEWAY"
echo "  ✓ DNS: $DNS1, $DNS2"

echo ""
echo -e "${GREEN}[2/5] Installing required packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null 2>&1
apt-get install -y wget curl gzip coreutils > /dev/null 2>&1
echo "  ✓ Packages installed"

echo ""
echo -e "${GREEN}[3/5] Detecting target disk...${NC}"

# Detect primary disk
DISK=$(lsblk -ndo NAME,TYPE | grep disk | head -n1 | awk '{print $1}')
DISK_PATH="/dev/$DISK"
DISK_SIZE=$(lsblk -ndo SIZE $DISK_PATH)

echo "  ✓ Target disk: $DISK_PATH"
echo "  ✓ Disk size: $DISK_SIZE"

# Confirm disk
echo ""
echo -e "${YELLOW}About to write to $DISK_PATH - This will destroy all data!${NC}"
echo -e "${YELLOW}Press CTRL+C within 5 seconds to cancel...${NC}"
sleep 5

echo ""
echo -e "${GREEN}[4/5] Downloading and writing Windows Server 2022 image...${NC}"
echo -e "${BLUE}This will take 10-30 minutes depending on connection speed${NC}"
echo -e "${BLUE}Image source: ${IMAGE_URL}${NC}"
echo ""

# Download and write image directly to disk
echo "  → Downloading and writing image..."
if wget --no-check-certificate --progress=bar:force -O- "$IMAGE_URL" 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered -oP '\d+%' | while read -r percent; do
    echo -ne "\r  Progress: $percent"
done | gunzip | dd of=$DISK_PATH bs=4M status=progress oflag=direct; then
    echo ""
    echo "  ✓ Image written successfully"
else
    echo ""
    echo -e "${RED}  ✗ Failed to download or write image${NC}"
    exit 1
fi

# Sync to ensure all data is written
sync
echo "  ✓ Syncing disk..."

echo ""
echo -e "${GREEN}[5/5] Installation complete!${NC}"

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}✓ Windows Server 2022 Installed${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}Connection Information:${NC}"
echo "  • IP Address: ${GREEN}$IPADDR${NC}"
echo "  • RDP Port: ${GREEN}3389${NC}"
echo "  • Username: ${GREEN}Administrator${NC}"
echo "  • Password: ${GREEN}(Check image documentation)${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. System will reboot in 10 seconds"
echo "  2. Wait 3-5 minutes for Windows to boot"
echo "  3. Connect via RDP to: $IPADDR:3389"
echo "  4. Login with Administrator credentials"
echo ""
echo -e "${RED}IMPORTANT NOTES:${NC}"
echo "  • This is a pre-configured image - credentials may vary"
echo "  • Change Administrator password immediately after login"
echo "  • Check image provider documentation for default credentials"
echo "  • Network settings should be automatically configured"
echo ""

# Countdown to reboot
echo -e "${YELLOW}Rebooting to Windows...${NC}"
for i in {10..1}; do
    echo -ne "\r  Rebooting in $i seconds... "
    sleep 1
done

echo ""
echo -e "${GREEN}Rebooting now...${NC}"
reboot
