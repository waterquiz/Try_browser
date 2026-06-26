#!/bin/bash
set -e

echo "=== Starting Browser Desktop ==="

# Create VNC password file
mkdir -p ~/.vnc
echo "$VNC_PASSWORD" | x11vnc -storepasswd ~/.vnc/passwd 2>/dev/null || true
chmod 600 ~/.vnc/passwd

# Start virtual display
echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 2

# Start DBus (needed by XFCE)
echo "Starting dbus..."
dbus-launch --exit-with-session &
sleep 1

# Start XFCE desktop
echo "Starting XFCE desktop..."
startxfce4 &
sleep 3

# Launch Chromium (lightweight, supports extensions)
echo "Launching Chromium..."
chromion --no-sandbox --disable-dev-shm-usage --disable-gpu --start-maximized --disable-software-rasterizer --window-size=1280,720 --disable-translate --disable-notifications --no-first-run --disable-default-apps about:blank &
sleep 2

# Start x11vnc (password-protected)
echo "Starting x11vnc..."
x11vnc -display $DISPLAY -rfbport 5900 -rfbauth ~/.vnc/passwd -forever -shared -nopw -bg -o /var/log/x11vnc.log 2>/dev/null || x11vnc -display $DISPLAY -rfbport 5900 -forever -shared -bg -o /var/log/x11vnc.log

sleep 1

# Start noVNC websockify bridge on $PORT
echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &

echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
echo "VNC Password: $VNC_PASSWORD"

# Keep container alive
wait
