#!/bin/bash
set -e

echo "=== Starting Ubuntu Browser Desktop ==="

PASSWD=${VNC_PASSWORD:-debian}

echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 3

for i in 1 2 3 4 5; do
  if xdpyinfo -display $DISPLAY >/dev/null 2>&1; then
    echo "X display ready!"
    break
  fi
  echo "Waiting for X display... attempt $i"
  sleep 2
done

echo "Starting dbus..."
dbus-launch --exit-with-session &
sleep 1

echo "Starting XFCE desktop..."
startxfce4 &
sleep 3

echo "Launching Chromium with sports extension..."
chromium-browser \
  --no-sandbox --disable-dev-shm-usage \
  --start-maximized --disable-software-rasterizer \
  --disable-translate --disable-notifications \
  --no-first-run --disable-default-apps \
  https://www.espn.com &
sleep 2

echo "Starting x11vnc..."
x11vnc -display $DISPLAY -rfbport 5900 -passwd "$PASSWD" -forever -shared -bg -o /var/log/x11vnc.log
sleep 2

echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &

echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
echo "VNC Password: $PASSWD"

wait
