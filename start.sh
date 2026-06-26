
#!/bin/bash
set -e

echo "=== Starting Browser Desktop ==="

mkdir -p ~/.vnc
echo "$VNC_PASSWORD" | x11vnc -storepasswd ~/.vnc/passwd 2>/dev/null || true
chmod 600 ~/.vnc/passwd

echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 2

echo "Starting dbus..."
dbus-launch --exit-with-session &
sleep 1

echo "Starting XFCE desktop..."
startxfce4 &
sleep 3

echo "Launching Chromium..."
chromium \n    --no-sandbox \n    --disable-dev-shm-usage \n    --disable-gpu \n    --start-maximized \n    --disable-software-rasterizer \n    --window-size=1280,720 \n    --disable-translate \n    --disable-notifications \n    --no-first-run \n    --disable-default-apps \n    about:blank &
sleep 2

echo "Starting x11vnc..."
x11vnc \n    -display $DISPLAY \n    -rfbport 5900 \n    -rfbauth ~/.vnc/passwd \n    -forever \n    -shared \n    -nopw \n    -bg \n    -o /var/log/x11vnc.log 2>/dev/null || \nx11vnc \n    -display $DISPLAY \n    -rfbport 5900 \n    -forever \n    -shared \n    -bg \n    -o /var/log/x11vnc.log

sleep 1

echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &

echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
echo "VNC Password: $VNC_PASSWORD"

wait
