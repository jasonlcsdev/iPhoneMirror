#!/bin/bash
set -e

PORT=8100
WDA_DIR="$(cd "$(dirname "$0")/.." && pwd)/WebDriverAgent"

echo "=== iPhone Mirror - Startup ==="
echo ""

# Cleanup
cleanup() {
    echo ""
    echo "Shutting down..."
    kill $IPROXY_PID $WDA_PID $FORWARD_PID 2>/dev/null || true
    echo "Stopped."
    exit 0
}
trap cleanup INT TERM

# Kill existing
pkill iproxy 2>/dev/null || true
pkill xcodebuild 2>/dev/null || true
pkill iPhoneMirror 2>/dev/null || true
sleep 2

# Detect device
echo "Detecting iOS device..."
DEVICES=$(idevice_id -l 2>/dev/null || true)
if [ -z "$DEVICES" ]; then
    echo "[ERROR] No iOS device found. Connect via USB and trust."
    exit 1
fi
DEVICE_UDID=$(echo "$DEVICES" | head -n1 | tr -d '[:space:]')
NAME=$(ideviceinfo -u "$DEVICE_UDID" -k DeviceName 2>/dev/null || echo "Unknown")
echo "[OK] Device: $NAME ($DEVICE_UDID)"

# Get WiFi IP
WIFI_IP=""
if command -v ifconfig &>/dev/null; then
    WIFI_IP=$(ifconfig en0 2>/dev/null | grep "inet " | awk '{print $2}')
fi
if [ -z "$WIFI_IP" ]; then
    WIFI_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "")
fi

echo ""
echo "========================================="
echo "  Mode: USB (default)"
echo "  WiFi IP: ${WIFI_IP:-not connected}"
echo "  WDA will be accessible at localhost:$PORT"
echo "========================================="
echo ""

# 1. iproxy
echo "[1/3] Starting iproxy..."
iproxy -u "$DEVICE_UDID" $PORT $PORT 2>/dev/null &
IPROXY_PID=$!
sleep 2
kill -0 $IPROXY_PID 2>/dev/null && echo "  OK" || { echo "  FAILED"; exit 1; }

# 2. WDA
echo "[2/3] Starting WebDriverAgent..."
FORWARD_PID=""
if [ -d "$WDA_DIR/WebDriverAgent.xcodeproj" ]; then
    nohup xcodebuild test \
        -project "$WDA_DIR/WebDriverAgent.xcodeproj" \
        -scheme WebDriverAgentRunner \
        -destination "id=$DEVICE_UDID" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        -test-timeouts-enabled NO \
        > /tmp/wda.log 2>&1 &
    WDA_PID=$!

    echo "  Waiting for WDA..."
    for i in $(seq 1 40); do
        sleep 2
        if curl -s -m 2 "http://localhost:$PORT/status" 2>/dev/null | grep -q '"ready"'; then
            echo "  OK (WDA PID: $WDA_PID)"
            break
        fi
        if [ $i -eq 40 ]; then
            echo "  WDA failed to start!"
        fi
    done

    # WiFi forward with pymobiledevice3 (if available)
    if [ -n "$WIFI_IP" ] && command -v pymobiledevice3 &>/dev/null; then
        echo ""
        echo "  [WiFi] Forwarding WDA port via pymobiledevice3..."
        pymobiledevice3 usbmux forward $PORT $PORT --udid "$DEVICE_UDID" &
        FORWARD_PID=$!
        sleep 2
        if kill -0 $FORWARD_PID 2>/dev/null; then
            echo "  [WiFi] Forward OK → iPhone accessible at $WIFI_IP:$PORT"
        else
            echo "  [WiFi] Forward failed"
            FORWARD_PID=""
        fi
    elif [ -n "$WIFI_IP" ]; then
        echo ""
        echo "  [WiFi] Install pymobiledevice3 for WiFi touch support:"
        echo "         brew install pymobiledevice3"
    fi
else
    echo "  WDA project not found at $WDA_DIR"
    echo "  Download: https://github.com/appium/WebDriverAgent"
fi

# 3. App
echo "[3/3] Launching iPhoneMirror..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/build/Build/Products/Release/iPhoneMirror.app"
if [ ! -d "$APP_PATH" ]; then
    echo "  Building..."
    xcodebuild -project "$SCRIPT_DIR/iPhoneMirror.xcodeproj" \
        -scheme iPhoneMirror -configuration Release \
        -derivedDataPath "$SCRIPT_DIR/build" build 2>&1 | tail -3
fi
if [ -d "$APP_PATH" ]; then
    open "$APP_PATH"
else
    echo "  Build failed"
fi

echo ""
echo "=== Running ==="
echo "  USB:  localhost:$PORT"
[ -n "$WIFI_IP" ] && echo "  WiFi: $WIFI_IP:$PORT"
echo "  Logs: tail -f /tmp/wda.log"
echo "  Press Ctrl+C to stop"
echo ""

# Keep alive
while true; do
    sleep 5
    if ! kill -0 $WDA_PID 2>/dev/null; then
        echo "[WARN] WDA died, restarting..."
        nohup xcodebuild test \
            -project "$WDA_DIR/WebDriverAgent.xcodeproj" \
            -scheme WebDriverAgentRunner \
            -destination "id=$DEVICE_UDID" \
            -allowProvisioningUpdates \
            CODE_SIGN_STYLE=Automatic \
            -test-timeouts-enabled NO \
            > /tmp/wda.log 2>&1 &
        WDA_PID=$!
        sleep 15
        curl -s -m 2 "http://localhost:$PORT/status" 2>/dev/null | grep -q '"ready"' && echo "  WDA restarted OK" || echo "  WDA restart failed"

        # Restart WiFi forward
        if [ -n "$FORWARD_PID" ] && ! kill -0 $FORWARD_PID 2>/dev/null; then
            pymobiledevice3 usbmux forward $PORT $PORT --udid "$DEVICE_UDID" &
            FORWARD_PID=$!
        fi
    fi
done
