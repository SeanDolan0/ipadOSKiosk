#!/bin/bash
set -e

# HA Smartboard — Build, Package & Deploy Script
# Target: iPad Mini 2, iPadOS 12.5.8, root@192.168.50.53

DEVICE_IP="192.168.50.53"
DEVICE_USER="root"
DEVICE_PASS="alpine"
HA_URL="http://192.168.50.150:8123"

echo "=== HA Smartboard Deploy ==="
echo "Device: ${DEVICE_USER}@${DEVICE_IP}"
echo ""

# Step 1: Clean build
echo "[1/7] Cleaning and building..."
make clean
make

# Step 2: Package as .deb
echo "[2/7] Packaging .deb..."
make package

# Step 3: Find the .deb file
DEB_FILE=$(ls -t packages/*.deb 2>/dev/null | head -1)
if [ -z "$DEB_FILE" ]; then
    echo "ERROR: No .deb file found in packages/"
    exit 1
fi
echo "Package: $DEB_FILE"

# Step 4: Transfer to device
echo "[3/7] Transferring to device..."
scp "$DEB_FILE" ${DEVICE_USER}@${DEVICE_IP}:/tmp/

# Step 5: Install on device
echo "[4/7] Installing package..."
ssh ${DEVICE_USER}@${DEVICE_IP} "dpkg -i /tmp/com.hasmartboard_*.deb"

# Step 6: Set permissions
echo "[5/7] Setting permissions..."
ssh ${DEVICE_USER}@${DEVICE_IP} "chmod 755 /Applications/HASmartboard.app/HASmartboard"
ssh ${DEVICE_USER}@${DEVICE_IP} "chmod 755 '/Library/Application Support/HASmartboard/kioskd'"

# Step 7: Load services
echo "[6/7] Loading launchd services..."
ssh ${DEVICE_USER}@${DEVICE_IP} "launchctl unload /Library/LaunchDaemons/com.hasmartboard.daemon.plist 2>/dev/null || true"
ssh ${DEVICE_USER}@${DEVICE_IP} "launchctl unload /Library/LaunchDaemons/com.hasmartboard.app.plist 2>/dev/null || true"
ssh ${DEVICE_USER}@${DEVICE_IP} "launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist"
ssh ${DEVICE_USER}@${DEVICE_IP} "launchctl load /Library/LaunchDaemons/com.hasmartboard.app.plist"

# Step 8: Verify
echo "[7/7] Verifying deployment..."
sleep 2
echo "Daemon status:"
ssh ${DEVICE_USER}@${DEVICE_IP} "ps aux | grep kioskd | grep -v grep" || echo "WARNING: kioskd not running"
echo ""
echo "App status:"
ssh ${DEVICE_USER}@${DEVICE_IP} "ps aux | grep HASmartboard | grep -v grep" || echo "WARNING: HASmartboard not running"
echo ""
echo "Health check:"
ssh ${DEVICE_USER}@${DEVICE_IP} "curl -s http://127.0.0.1:9090/health" || echo "WARNING: HTTP server not responding"
echo ""
echo ""
echo "=== Deploy complete ==="
echo "HA Dashboard: ${HA_URL}/lovelace/0"
echo "Daemon API: http://127.0.0.1:9090/telemetry"
echo "Logs: ssh ${DEVICE_USER}@${DEVICE_IP} 'tail -f /var/log/kioskd.log'"
