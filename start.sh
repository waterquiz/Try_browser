#!/bin/bash
set -e

echo "=== Starting Browser Desktop ==="

# Create VNC password file
mkdir -p ~/.vnc
if [ -n "$VNC_PASSWORD" ]; then
  echo "$VNC_PASSWORD" | x11vnc -storepasswd /dev/stdin ~/.vnc/passwd 2>/dev/null || \
  printf "$VNC_PASSWORD\n$VNC_PASSWORD\n" | x11vnc -storepasswd ~/.vnc/passwd 2>/dev/null || \
  echo -n "$VNC_PASSWORD" > ~/.vnc/passwd
  chmod 600 ~/.vnc/passwd
fi

# Start virtual display and wait for it to be ready
echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 3

# Verify X display is responding before starting VNC
echo "Checking X display..."
for i in 1 2 3 4 5; do
  if xdpyinfo -display $DISPLAY >/dev/null 2>&1; then
    echo "X display ready!"
    break
  fi
  echo "Waiting for X display... attempt $i"
  sleep 2
done

# Start DBus (needed by XFCE)
echo "Starting dbus..."
dbus-launch --exit-with-session &
sleep 1

# Start XFCE desktop
echo "Starting XFCE desktop..."
startxfce4 &
sleep 3

# Launch Chromium
echo "Launching Chromium..."
chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --start-maximized --disable-software-rasterizer --window-size=1280,720 --disable-translate --disable-notifications --no-first-run --disable-default-apps about:blank &
sleep 2

# Start x11vnc
echo "Starting x11vnc..."
if [ -f ~/.vnc/passwd ]; then
  x11vnc -display $DISPLAY -rfbport 5900 -rfbauth ~/.vnc/passwd -forever -shared -nopw -bg -o /var/log/x11vnc.log 2>/dev/null || \
  x11vnc -display $DISPLAY -rfbport 5900 -rfbauth ~/.vnc/passwd -forever -shared -bg -o /var/log/x11vnc.log
else
  x11vnc -display $DISPLAY -rfbport 5900 -forever -shared -nopw -bg -o /var/log/x11vnc.log
fi

sleep 2

# Start noVNC websockify bridge on $PORT
echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &

echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
echo "VNC Password: $VNC_PASSWORD"

# Keep container alive
wait
