# Cloud Browser — noVNC + Google Chrome on Railway

**NOT a desktop.** There is no Ubuntu window, no XFCE, no Windows.  
This is just a **browser** running in the cloud, streamed to you through your own web browser via noVNC.

You open a URL → you see Chrome. That's it. No OS, no desktop, no RDP.

---

## File Structure

```
cloud-browser/
├── Dockerfile          # Builds the container (Ubuntu minimal + Chrome + noVNC)
├── start.sh            # Startup script: Xvfb → Chrome → x11vnc → websockify
├── railway.json        # Railway deploy config (auto-detect Dockerfile)
├── .dockerignore       # Excludes git, md from Docker build context
├── .gitignore          # Excludes logs, OS files from git
└── README.md           # This file
```

---

## How It Works — The Pipeline (A to Z)

```
Your Browser (Chrome/Firefox/Edge on YOUR machine)
        │
        │  HTTPS request to Railway URL
        ▼
┌─────────────────────────────────────────┐
│         Railway Cloud Server            │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │         Docker Container        │   │
│  │                                 │   │
│  │  noVNC ← websockify ← x11vnc ←─┼── Xvfb virtual display
│  │  (web UI)   (proxy)  (VNC srv)  │      │
│  │                                 │      │
│  │                                 │  Google Chrome ← Extension (Sportsy)
│  │                                 │      │
│  │                                 │  renders web pages on virtual screen
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Step-by-Step Flow

1. **Xvfb** creates a fake monitor (no physical screen exists)
2. **Google Chrome** launches on that fake monitor (opens your chosen URL)
3. **x11vnc** captures whatever is on the fake monitor and serves it via VNC
4. **websockify** proxies WebSocket ↔ TCP so your browser can talk to VNC
5. **noVNC** is an HTML5 page served to you — it connects through websockify to x11vnc
6. **You** open the Railway URL → see Chrome directly — no desktop in between

---

## File 1: Dockerfile — The Container

```dockerfile
FROM ubuntu:22.04
```

Minimal Ubuntu. This is **NOT** a desktop — just enough OS to run Chrome and the streaming tools.

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV PORT=6080
```

| Variable | Purpose |
|----------|---------|
| `DISPLAY=:0` | Tells Chrome which virtual screen to use |
| `RESOLUTION=1280x720x24` | Width × Height × Color Depth |
| `PORT=6080` | Default port (Railway overrides with its own `$PORT`) |

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    x11-utils \
    wget curl ca-certificates gnupg \
    python3 python3-pip \
    fonts-liberation \
    libx11-dev libxrender1 libxtst6 \
    libnss3 libasound2 libatk-bridge2.0-0 \
    libdrm2 libgbm1 libgtk-3-0 \
    libu2f-udev libvulkan1 \
    xdg-utils procps \
    && rm -rf /var/lib/apt/lists/*
```

**What each package does:**

| Package | Role |
|---------|------|
| `xvfb` | Creates a virtual display (fake screen) |
| `x11vnc` | Captures virtual display → VNC stream |
| `x11-utils` | Provides `xdpyinfo` to check Xvfb is ready |
| `python3-pip` | Installs websockify |
| `fonts-liberation` | Chrome font rendering |
| `libnss3`, `libgtk-3-0`, etc. | Chrome shared library dependencies |
| `procps` | Provides `ps`, `kill` etc. |

No desktop environment (no XFCE, no GNOME, no KDE). Just the bare minimum to run a browser.

```dockerfile
RUN pip3 install --no-cache-dir websockify==0.11.0
```

**websockify** — translates WebSocket (your browser) → TCP (VNC server). Required because noVNC uses WebSockets and x11vnc uses plain TCP.

```dockerfile
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y -f /tmp/chrome.deb && \
    rm -f /tmp/chrome.deb
```

Installs **Google Chrome** from Google's official .deb.  
Why not `chromium-browser`? On Ubuntu 22.04, that package is a snap wrapper and fails inside Docker with:  
`Command '/usr/bin/chromium-browser' requires the chromium snap to be installed.`

```dockerfile
RUN mkdir -p /opt/noVNC && \
    cd /tmp && \
    wget --tries=3 --timeout=30 -O novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz && \
    tar xzf novnc.tar.gz -C /opt/noVNC --strip-components=1 && \
    rm -f novnc.tar.gz
```

Downloads **noVNC v1.4.0** — a web-based VNC viewer written in HTML5/JavaScript. This is what the user sees in their browser.

```dockerfile
RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{"ExtensionInstallForcelist": ["EXTENSION_ID_HERE"]}' \
    > /etc/opt/chrome/policies/managed/auto_install.json
```

**Chrome Managed Policy** — force-installs a Chrome extension on every launch without user interaction.  
To find an extension ID: Chrome Web Store → extension page → URL ends with `/detail/.../EXTENSION_ID`

```dockerfile
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE ${PORT}
CMD ["/start.sh"]
```

Sets the startup script as the container entrypoint.

---

## File 2: start.sh — The Startup Sequence

```bash
#!/bin/bash
set -e
```

`set -e` = exit on first error.

### Phase 1: Start Virtual Display

```bash
echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 3
```

Xvfb creates display `:0` at `1280x720x24`. The `&` runs it in background.

### Phase 2: Wait for X

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

Without this loop, Chrome might start before Xvfb is ready and crash immediately.

### Phase 3: Parse Resolution

```bash
W=${RESOLUTION%x*}; H=${RESOLUTION#*x}; H=${H%x*}
```

Takes `1280x720x24` → W=1280, H=720

### Phase 4: Launch Chrome

```bash
echo "Launching Google Chrome (${W}x${H})..."
google-chrome \
  --no-sandbox                        # Required in Docker containers
  --disable-dev-shm-usage              # Prevents crash in low-memory
  --window-size=$W,$H                  # Fills fake screen completely
  --window-position=0,0                # No black borders on sides
  --disable-software-rasterizer        # No GPU needed
  --disable-translate                  # Skip translate popup
  --disable-notifications              # No notification prompts
  --no-first-run                       # Skip first-run wizard
  --disable-default-apps               # No welcome page
  https://your-start-url.com &         # ← CHANGE THIS
sleep 2
```

**Why `--window-size` instead of `--start-maximized`:**  
`--start-maximized` asks a window manager to maximize. No window manager exists here.  
`--window-size=1280,720 --window-position=0,0` directly sets the exact position and size.

### Phase 5: Start VNC Server

```bash
echo "Starting x11vnc (no password)..."
x11vnc -display $DISPLAY -rfbport 5900 -nopw -forever -shared -bg -o /var/log/x11vnc.log
sleep 2
```

x11vnc captures the virtual display content.

| Flag | Purpose |
|------|---------|
| `-nopw` | No password (URL is already private) |
| `-forever` | Keep running after client disconnects |
| `-shared` | Multiple people can view |
| `-bg` | Run in background |

### Phase 6: Start Web Proxy

```bash
echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &
```

websockify serves:
- Static files from `/opt/noVNC` (vnc.html, etc.) at `http://host:PORT/`
- WebSocket proxy at `ws://host:PORT/` → `tcp://localhost:5900`

```bash
echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
wait
```

`wait` keeps the container alive.

---

## File 3: railway.json — Deployment Config

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

Tells Railway: build using Dockerfile, restart if crashed.

---

## File 4: .dockerignore

```
.git
.gitignore
README.md
*.md
node_modules
```

Keeps the Docker build context small.

---

## File 5: .gitignore

```
*.log
.DS_Store
Thumbs.db
```

Prevents log files and OS artifacts from being committed.

---

## Full Method — From Zero to Running Browser

### Prerequisites

- A **GitHub** account
- A **Railway** account (free tier: https://railway.com)

### Step 1 — Create the Project

Create a folder with these 6 files:

```
cloud-browser/
├── Dockerfile
├── start.sh
├── railway.json
├── .dockerignore
├── .gitignore
└── README.md
```

Copy the contents from the sections above into each file.

### Step 2 — Customize

In `start.sh`, line 27:  
Change `https://your-start-url.com` to your desired URL.

In `Dockerfile`, line 48-49:  
Change the extension ID to your preferred Chrome extension.

### Step 3 — Push to GitHub

```powershell
cd cloud-browser
git init
git add .
git commit -m "Cloud browser: Chrome + noVNC on Railway"
git branch -M main
git remote add origin https://github.com/YOUR_USER/REPO_NAME.git
git push -u origin main
```

### Step 4 — Deploy on Railway

1. Go to https://railway.com
2. Click **New Project** → **Deploy from GitHub**
3. Select your new repository
4. Railway auto-detects `Dockerfile` and builds
5. Wait ~5-10 minutes for first build
6. Click the generated URL (ends with `.up.railway.app`)

### Step 5 — Connect

1. Open the Railway URL in your browser
2. Add `/vnc.html` to the URL (e.g., `https://project.up.railway.app/vnc.html`)
3. Click **Connect** — no password needed
4. Google Chrome loads with your chosen URL

---

## Customization Guide

### Change Default URL

Edit `start.sh`:

```bash
https://your-new-url.com &
```

### Change Screen Resolution

Edit `Dockerfile`:

```dockerfile
ENV RESOLUTION=1920x1080x24
```

Also update `start.sh` to match if hardcoded — our script auto-parses from `$RESOLUTION`.

### Install a Different Chrome Extension

1. Chrome Web Store → find extension
2. URL: `.../detail/EXTENSION_ID`
3. Edit `Dockerfile`:

```dockerfile
"ExtensionInstallForcelist": [
    "NEW_EXTENSION_ID"
]
```

For multiple extensions:

```dockerfile
"ExtensionInstallForcelist": [
    "EXTENSION_1_ID",
    "EXTENSION_2_ID"
]
```

### Remove Chrome Extension

Delete the policy file from the Dockerfile:

```dockerfile
# Remove this entire RUN block:
# RUN mkdir -p ... && printf ...
```

### Add VNC Password

In `start.sh`, replace:

```bash
x11vnc ... -nopw ...
```

with:

```bash
x11vnc ... -passwd "yourpassword" ...
```

---

## Troubleshooting

### Build Fails: `no such option: --break-system-packages`

**Cause:** Old pip version doesn't support this flag.  
**Fix:** Use `pip3 install --no-cache-dir websockify==0.11.0` (no `--break-system-packages`).

### Build Fails: Chrome install error

**Cause:** Network timeout downloading Chrome.  
**Fix:** The Dockerfile uses `wget` with retries. Add `|| apt-get install -y chromium` as fallback.

### Runtime: `chromium-browser requires the chromium snap`

**Cause:** Ubuntu's `chromium-browser` is a snap wrapper that doesn't work in Docker.  
**Fix:** Use `google-chrome` from the official `.deb` (as shown in our Dockerfile).

### Runtime: `password check failed`

**Cause:** Broken VNC password file.  
**Fix:** Use `-passwd "pass"` or `-nopw` instead of `-storepasswd`.

### Runtime: Black borders around browser

**Cause:** `--start-maximized` doesn't work without a window manager.  
**Fix:** Use `--window-size=$W,$H --window-position=0,0`.

### Runtime: Browser crashes on start

**Cause:** Xvfb not ready when Chrome launches.  
**Fix:** The startup script has a 5-attempt wait loop. Check logs for `X display ready!`.

### Connection: noVNC loads but shows "Disconnected"

**Cause:** x11vnc or websockify not running.  
**Fix:** Check Railway logs. Ensure x11vnc started successfully.

### Connection: Blank screen / no Chrome

**Cause:** Chrome failed to launch (missing library).  
**Fix:** Check logs for missing `.so` files. Add them via `apt-get install`.

---

## Comparison: This vs. Traditional Remote Desktop

| Feature | This Project | Traditional RDP/VNC |
|---------|-------------|-------------------|
| What you see | Only Chrome browser | Full desktop (start menu, taskbar, etc.) |
| OS in container | Minimal Ubuntu, no desktop | Full desktop environment |
| Deployment | Railway (2-click deploy) | Requires VPN, port forwarding, static IP |
| Access | Any browser, no client needed | Requires RDP/VNC client |
| Security | Railway URL (HTTPS + unguessable) | Requires firewall rules |
| Resource usage | ~500MB RAM | ~2GB+ RAM |
| Cost | Railway free tier | VPS/server monthly cost |
| Setup time | 10 minutes | 1-2 hours |

---

## How to Test Locally (Before Deploying)

Requires Docker Desktop:

```powershell
docker build -t cloud-browser .
docker run -d -p 6080:6080 cloud-browser
# Open http://localhost:6080/vnc.html
```

---

## Architecture: What Happens on Each Connection

```
1. You open https://project.up.railway.app/vnc.html
   │
2. Your browser downloads noVNC (HTML + JS) from websockify
   │
3. noVNC opens a WebSocket connection to wss://project.up.railway.app/
   │
4. websockify receives the WebSocket and opens TCP to localhost:5900
   │
5. x11vnc accepts the TCP connection (VNC handshake)
   │
6. VNC protocol negotiates: no auth needed (-nopw)
   │
7. x11vnc starts sending framebuffer updates (screen captures)
   │
8. noVNC renders the framebuffer as an HTML5 canvas in your browser
   │
9. Your mouse clicks / key presses go back through:
   Browser → WebSocket → websockify → TCP → x11vnc → Xvfb → Chrome
   │
10. Chrome processes the input (click link, type URL, etc.)
    │
11. Screen updates flow back → noVNC renders them
    │
    (Loop continues until you close the tab)
```

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOLUTION` | `1280x720x24` | Screen size (WxHxD) |
| `PORT` | `6080` | noVNC port (Railway auto-sets this) |
| `DISPLAY` | `:0` | X11 display number |

Set these in Railway Dashboard → Project → Variables.

---

## Quick Commands Reference

```powershell
# Build and test locally
docker build -t cloud-browser .
docker run -d -p 6080:6080 cloud-browser
# Open http://localhost:6080/vnc.html

# Push to GitHub
git add .
git commit -m "update"
git push

# Railway deploys automatically on push
```
