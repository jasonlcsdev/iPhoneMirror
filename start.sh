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
    kill $IPROXY_PID $WDA_PID 2>/dev/null || true
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

# 1. iproxy
echo "[1/3] Starting iproxy..."
iproxy -u "$DEVICE_UDID" $PORT $PORT 2>/dev/null &
IPROXY_PID=$!
sleep 2
kill -0 $IPROXY_PID 2>/dev/null && echo "  OK" || { echo "  FAILED"; exit 1; }

# 2. WDA
echo "[2/3] Starting WebDriverAgent..."
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
else
    echo "  WDA project not found at $WDA_DIR"
    echo "  Download: https://github.com/appium/WebDriverAgent"
fi

# 3. App
echo "[3/3] Launching iPhoneMirror..."
APP_PATH="$(cd "$(dirname "$0")" && pwd)/build/Build/Products/Release/iPhoneMirror.app"
if [ -d "$APP_PATH" ]; then
    open "$APP_PATH"
else
    echo "  App not found. Building..."
    xcodebuild -project "$(dirname "$0")/iPhoneMirror.xcodeproj" \
        -scheme iPhoneMirror -configuration Release build 2>&1 | tail -3
    open "$APP_PATH" 2>/dev/null || echo "  Build failed"
fi

echo ""
echo "=== Running ==="
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
    fi
done
