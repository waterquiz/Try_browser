# Cloud Browser — Terminal Access via noVNC + Chrome on Railway

**NOT a desktop.** There is no Windows, no Ubuntu GUI, no XFCE, no RDP.  
This project gives you **terminal access** to a cloud container that runs Google Chrome — streamed to your browser via noVNC.

You open a URL → you see a **terminal** where Chrome runs. That's it. No GUI, no OS desktop.

---

## File Structure

```
cloud-browser/
├── Dockerfile          # Builds the container (Ubuntu minimal + Chrome + noVNC)
├── start.sh            # Startup: Xvfb → Chrome → x11vnc → websockify
├── railway.json        # Railway deploy config (auto-detect Dockerfile)
├── .dockerignore       # Excludes git, md from Docker build context
├── .gitignore          # Excludes logs, OS files from git
└── README.md           # This file
```

---

## What This Project Actually Does

This is **not** a Windows remote desktop or an Ubuntu VNC desktop.  
It is a **browser-in-a-terminal** setup:

- A **virtual display** (Xvfb) acts as the "screen"
- **Google Chrome** renders web pages on that virtual screen
- **x11vnc** captures that screen and streams it
- **noVNC** lets you view the stream in your browser
- You interact with Chrome through the noVNC viewer

Everything runs in a **terminal/container environment** on Railway — no GUI operating system.

---

## Architecture — How It All Connects

```
YOUR BROWSER (any device: phone, laptop, tablet)
        │
        │  HTTPS → https://your-project.up.railway.app/vnc.html
        ▼
┌──────────────────────────────────────────────────┐
│                  RAILWAY SERVER                   │
│  ┌────────────────────────────────────────────┐  │
│  │         DOCKER CONTAINER (Terminal)        │  │
│  │                                            │  │
│  │  ┌──────────┐    ┌──────────┐   ┌───────┐ │  │
│  │  │ noVNC    │◄──►│ websock  │◄─►│ x11vnc│ │  │
│  │  │ (web UI) │    │ -ify     │   │(VNC)  │ │  │
│  │  │ :6080    │    │ :6080    │   │:5900  │ │  │
│  │  └──────────┘    └──────────┘   └───┬───┘ │  │
│  │                                     │     │  │
│  │                              ┌──────▼──┐  │  │
│  │                              │  Xvfb   │  │  │
│  │                              │(virtual │  │  │
│  │                              │ display)│  │  │
│  │                              └──────┬──┘  │  │
│  │                                     │     │  │
│  │                              ┌──────▼──┐  │  │
│  │                              │  Chrome │  │  │
│  │                              │(browser)│  │  │
│  │                              └─────────┘  │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

**This is a terminal/CLI environment.** The container has no desktop, no taskbar, no start menu. Just Chrome running on a virtual display.

---

## Pipeline — Step by Step (A to Z)

### Phase 1: Xvfb — Create a Virtual Display

Xvfb (X Virtual Framebuffer) creates a fake screen in memory. There is no physical monitor, no GPU, no display connected. It's just a block of memory that acts like a screen.

```
Xvfb :0 -screen 0 1280x720x24 &
```

- `:0` = display number
- `1280x720x24` = width × height × color depth

### Phase 2: Wait for Display Readiness

The script polls `xdpyinfo` to confirm Xvfb is fully initialized before launching Chrome. Without this, Chrome would crash.

### Phase 3: Parse Resolution

```
RESOLUTION=1280x720x24  →  W=1280, H=720
```

### Phase 4: Launch Google Chrome

Chrome opens on the virtual display, pointed at your chosen URL. Key flags:

| Flag | Why It's Needed |
|------|----------------|
| `--no-sandbox` | Required inside Docker containers |
| `--disable-dev-shm-usage` | Prevents crash in low-memory containers |
| `--window-size=$W,$H` | Fills the virtual screen exactly (no black bars) |
| `--window-position=0,0` | Pins window to top-left corner |
| `--no-first-run` | Skips Chrome's setup wizard |
| `--disable-software-rasterizer` | Software rendering (no GPU) |

### Phase 5: x11vnc — Stream the Display

x11vnc captures whatever is on the virtual display and serves it over VNC protocol on port 5900.

```
x11vnc -display :0 -rfbport 5900 -nopw -forever -shared -bg
```

- No password (`-nopw`) — the Railway URL is already unguessable
- Runs forever, allows multiple viewers

### Phase 6: websockify — Bridge WebSocket to TCP

Your browser speaks WebSocket. x11vnc speaks TCP. websockify translates between them.

```
websockify --web /opt/noVNC 6080 localhost:5900
```

It also serves the noVNC web interface files (`vnc.html`, `javascript`).

### Phase 7: You Connect via Browser

1. Open `https://project.up.railway.app/vnc.html`
2. noVNC (JavaScript) loads in your browser
3. It opens a WebSocket to the Railway server
4. websockify forwards to x11vnc (TCP)
5. VNC handshake completes (no password)
6. Screen updates flow: Chrome → Xvfb → x11vnc → websockify → your browser
7. Your clicks/keys flow back: browser → WebSocket → websockify → x11vnc → Chrome

---

## File 1: Dockerfile — Full Explanation

```dockerfile
FROM ubuntu:22.04
```

Minimal Ubuntu — just enough to run Chrome + streaming tools. **No desktop GUI installed.**

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV PORT=6080
```

**`DISPLAY=:0`** — tells Chrome which virtual screen to use. Without this, Chrome doesn't know where to render.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \              # Virtual display (fake monitor)
    x11vnc \            # Screen capture → VNC stream
    x11-utils \         # xdpyinfo for readiness check
    wget curl ca-certificates gnupg \   # Download tools
    python3 python3-pip \               # For websockify
    fonts-liberation \                  # Chrome needs fonts
    libx11-dev libxrender1 libxtst6 \   # X11 libraries
    libnss3 libasound2 libatk-bridge2.0-0 \  # Chrome deps
    libdrm2 libgbm1 libgtk-3-0 \        # Chrome deps
    libu2f-udev libvulkan1 \            # Chrome deps
    xdg-utils procps \
    && rm -rf /var/lib/apt/lists/*
```

**No desktop packages** (no xfce4, no gnome, no lxde). Only the minimum to run Chrome in a terminal.

```dockerfile
RUN pip3 install --no-cache-dir websockify==0.11.0
```

WebSocket ↔ TCP bridge. Converts your browser's WebSocket connection into a plain TCP connection that x11vnc understands.

```dockerfile
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y -f /tmp/chrome.deb && \
    rm -f /tmp/chrome.deb
```

Installs **Google Chrome** from the official Google .deb package.  
`chromium-browser` from Ubuntu repos is a snap wrapper — it fails in Docker with:  
`Command requires the chromium snap to be installed.`

```dockerfile
RUN mkdir -p /opt/noVNC && \
    cd /tmp && \
    wget --tries=3 --timeout=30 -O novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz && \
    tar xzf novnc.tar.gz -C /opt/noVNC --strip-components=1 && \
    rm -f novnc.tar.gz
```

Downloads **noVNC v1.4.0** — an HTML5 VNC viewer. This is the web page you open in your browser to see Chrome's screen.

```dockerfile
RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{"ExtensionInstallForcelist": ["EXTENSION_ID_HERE"]}' \
    > /etc/opt/chrome/policies/managed/auto_install.json
```

Chrome **managed policy** — force-installs an extension without user interaction.  
Find extension IDs at: Chrome Web Store → extension page → URL pattern: `.../detail/NAME/EXTENSION_ID`

```dockerfile
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE ${PORT}
CMD ["/start.sh"]
```

---

## File 2: start.sh — Full Explanation

```bash
#!/bin/bash
set -e
```

`set -e` = exit immediately if any command fails.

```bash
echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 3
```

Creates virtual display `:0` at resolution `1280x720x24` in the background.

```bash
for i in 1 2 3 4 5; do
  if xdpyinfo -display $DISPLAY >/dev/null 2>&1; then
    echo "X display ready!"
    break
  fi
  echo "Waiting for X display... attempt $i"
  sleep 2
done
```

**Safety check:** waits up to 10 seconds for Xvfb to initialize. Without this, Chrome starts too early and crashes.

```bash
W=${RESOLUTION%x*}; H=${RESOLUTION#*x}; H=${H%x*}
echo "Launching Google Chrome (${W}x${H})..."
```

Extracts width and height from `1280x720x24`.

```bash
google-chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --window-size=$W,$H \
  --window-position=0,0 \
  --disable-software-rasterizer \
  --disable-translate \
  --disable-notifications \
  --no-first-run \
  --disable-default-apps \
  https://your-start-url.com &
sleep 2
```

Launches Chrome on the virtual display.

```bash
echo "Starting x11vnc (no password)..."
x11vnc -display $DISPLAY -rfbport 5900 -nopw -forever -shared -bg -o /var/log/x11vnc.log
sleep 2
```

Starts VNC server to capture and stream the virtual display.

```bash
echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &

echo "=== Ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
wait
```

Starts the WebSocket proxy and keeps the container alive.

---

## File 3: railway.json

```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 5
  }
}
```

Tells Railway: use Dockerfile to build, restart if the container crashes.

---

## File 4: .dockerignore

```
.git
.gitignore
README.md
*.md
node_modules
```

Excludes unnecessary files from Docker build for faster builds.

---

## File 5: .gitignore

```
*.log
.DS_Store
Thumbs.db
```

Excludes logs and OS junk from git.

---

## Complete Method — From Zero to Deployed

### Prerequisites

| Required | Purpose |
|----------|---------|
| GitHub account | Host the code |
| Railway account (free) | Deploy the container |

### Step 1: Create the Project Folder

```powershell
mkdir cloud-browser
cd cloud-browser
```

Create these 6 files with the exact contents from above:

```
cloud-browser/
├── Dockerfile
├── start.sh
├── railway.json
├── .dockerignore
├── .gitignore
└── README.md
```

### Step 2: Customize Your Settings

**Change default URL** — edit `start.sh` line with `https://your-start-url.com`

**Change extension** — edit `Dockerfile` line with `EXTENSION_ID_HERE`

**Change resolution** — edit `Dockerfile` line `ENV RESOLUTION=1280x720x24`

### Step 3: Push to GitHub

```powershell
git init
git add .
git commit -m "Cloud browser with terminal access"
git branch -M main
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

### Step 4: Deploy on Railway

1. Open https://railway.com
2. Click **New Project** → **Deploy from GitHub**
3. Select your repository
4. Railway detects Dockerfile → builds automatically
5. Wait for build to finish (first time: 5-10 minutes)
6. Click the generated project URL

### Step 5: Connect

1. Open `https://your-project.up.railway.app/vnc.html`
2. Click **Connect** (no password)
3. Chrome loads with your chosen URL and the pre-installed extension

---

## Customization

### Change the Start URL

In `start.sh`:

```bash
https://my-website.com &
```

### Change Resolution

In `Dockerfile`:

```dockerfile
ENV RESOLUTION=1920x1080x24    # Full HD
ENV RESOLUTION=1024x768x24     # Standard
```

### Change Chrome Extension

1. Go to Chrome Web Store
2. Copy extension ID from URL: `.../detail/NAME/`**`EXTENSION_ID`**
3. Edit `Dockerfile`:

```dockerfile
"ExtensionInstallForcelist": [
    "NEW_EXTENSION_ID"
]
```

Multiple extensions:

```dockerfile
"ExtensionInstallForcelist": [
    "EXT_1_ID",
    "EXT_2_ID"
]
```

### Add a Password

In `start.sh`, change:

```bash
x11vnc ... -nopw ...
```

to:

```bash
x11vnc ... -passwd "mypassword" ...
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `password check failed` | Corrupt password file | Use `-passwd "pass"` or `-nopw` |
| `chromium-browser requires snap` | Ubuntu snap wrapper | Use Google Chrome .deb instead |
| `--break-system-packages` error | Old pip version | Remove that flag |
| Black borders around Chrome | Window size mismatch | Use `--window-size=$W,$H --window-position=0,0` |
| Chrome crashes on start | Xvfb not ready yet | Wait loop in start.sh handles this |
| noVNC shows "Disconnected" | x11vnc/websockify failed | Check Railway logs |
| Blank screen in noVNC | Chrome failed to launch | Check logs for missing libs |
| Container exits immediately | Script error | Check Railway runtime logs |

---

## Local Testing

If you have Docker Desktop:

```powershell
docker build -t cloud-browser .
docker run -d -p 6080:6080 cloud-browser
# Open http://localhost:6080/vnc.html
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOLUTION` | `1280x720x24` | Virtual display size |
| `PORT` | `6080` | Web server port (Railway overrides) |
| `DISPLAY` | `:0` | X11 display number |

Set custom values in Railway Dashboard → Project → Variables.

---

## Quick Commands

```powershell
# Build & test locally
docker build -t cloud-browser .
docker run -d -p 6080:6080 cloud-browser

# Push updates
git add .
git commit -m "update"
git push

# Railway auto-deploys on every push
```
