# Browser Desktop on Railway — Full Documentation

## What This Project Does

This project runs **Google Chrome** inside a container on Railway and streams it to your browser via **noVNC**. You get a remote browser (with pre-installed extensions) accessible from any device with a web browser.

No desktop environment, no RDP — just the browser window directly.

---

## File Structure

```
browser-desktop/
├── Dockerfile          # Container build instructions
├── start.sh            # Entrypoint script (runs on container start)
├── railway.json        # Railway deployment config
├── .dockerignore       # Files to exclude from Docker build
├── .gitignore          # Files to exclude from Git
└── README.md           # This file
```

---

## File-by-File Explanation

### 1. Dockerfile — The Container Blueprint

```dockerfile
FROM ubuntu:22.04
```

Base image. Ubuntu 22.04 LTS is stable and well-supported. You can change this to `debian:bookworm-slim` for a smaller image, or `ubuntu:24.04` for newer packages.

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV PORT=6080
```

- `DEBIAN_FRONTEND=noninteractive` — Prevents apt from asking interactive questions during build.
- `DISPLAY=:0` — The X11 display number. Xvfb creates this virtual display.
- `RESOLUTION=1280x720x24` — Screen width x height x color depth. This controls the browser window size.
- `PORT=6080` — Default port for noVNC websockify. Railway overrides this via its own `$PORT` env var.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    x11-utils \
    ...
    && rm -rf /var/lib/apt/lists/*
```

**Key packages:**
| Package | Purpose |
|---------|---------|
| `xvfb` | Creates a virtual monitor (no physical screen needed) |
| `x11vnc` | Captures the virtual display and serves it via VNC protocol |
| `x11-utils` | Provides `xdpyinfo` to verify Xvfb is ready |
| `python3-pip` | Needed to install websockify |
| `fonts-liberation` | Google Chrome requires it |
| `libnss3`, `libgtk-3-0`, etc. | Chrome library dependencies |

```dockerfile
RUN pip3 install --no-cache-dir websockify==0.11.0
```

**websockify** — A WebSocket-to-TCP proxy. It translates WebSocket connections (from the user's browser) to raw TCP connections (to x11vnc). Version 0.11.0 is stable.

```dockerfile
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y -f /tmp/chrome.deb && \
    rm -f /tmp/chrome.deb
```

Downloads and installs **Google Chrome** directly from Google. We use the `.deb` file instead of the `chromium-browser` package because on Ubuntu 22.04, `chromium-browser` is a snap wrapper that doesn't work in Docker.

```dockerfile
RUN mkdir -p /opt/noVNC && \
    cd /tmp && \
    wget --tries=3 --timeout=30 -O novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz && \
    tar xzf novnc.tar.gz -C /opt/noVNC --strip-components=1 && \
    rm -f novnc.tar.gz
```

Downloads and extracts **noVNC** v1.4.0 — an HTML5 VNC client. It provides the web page (`vnc.html`) that users open in their browser.

```dockerfile
RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{\n  "ExtensionInstallForcelist": [\n    "ocgahpobhhfjgaggafmidogklgiefenj"\n  ]\n}\n' \
    > /etc/opt/chrome/policies/managed/sports_extension.json
```

Creates a Chrome **managed policy** that force-installs the "Sportsy" extension (ID: `ocgahpobhhfjgaggafmidogklgiefenj`) on every launch. To install a different extension:
1. Go to Chrome Web Store
2. Find your extension
3. Copy its ID from the URL (e.g., `https://chromewebstore.google.com/detail/.../EXTENSION_ID_HERE`)
4. Replace the ID in this file

```dockerfile
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE ${PORT}
CMD ["/start.sh"]
```

Copies the startup script, makes it executable, exposes the port, and sets it as the container entrypoint.

---

### 2. start.sh — The Startup Pipeline

```bash
#!/bin/bash
set -e
```

`set -e` makes the script exit immediately if any command fails (safety net).

```bash
echo "Starting Xvfb on $DISPLAY..."
Xvfb $DISPLAY -screen 0 $RESOLUTION &
sleep 3
```

**Step 1: Virtual Display** — Xvfb creates a virtual monitor at `:0` with the specified resolution. The `&` backgrounds it. Sleep 3 seconds to let it initialize.

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

**Step 2: Wait for X** — Polls every 2 seconds (up to 5 attempts) to confirm Xvfb is fully ready. Without this check, Chrome might start before Xvfb is ready and crash.

```bash
W=${RESOLUTION%x*}; H=${RESOLUTION#*x}; H=${H%x*}
echo "Launching Google Chrome (${W}x${H})..."
```

**Step 3: Parse Resolution** — Extracts width and height from `RESOLUTION` (e.g., `1280x720x24` → W=1280, H=720).

```bash
google-chrome \
  --no-sandbox --disable-dev-shm-usage \
  --window-size=$W,$H --window-position=0,0 \
  --disable-software-rasterizer \
  --disable-translate --disable-notifications \
  --no-first-run --disable-default-apps \
  https://teaserfast.ru &
sleep 2
```

**Step 4: Launch Chrome** — Important flags explained:

| Flag | Why |
|------|-----|
| `--no-sandbox` | Required in Docker containers (no user namespace) |
| `--disable-dev-shm-usage` | Prevents crashes in memory-constrained containers |
| `--window-size=$W,$H` | Makes Chrome fill the entire virtual display |
| `--window-position=0,0` | Pins window to top-left corner (no black borders) |
| `--disable-software-rasterizer` | Uses CPU rendering (no GPU available) |
| `--no-first-run` | Skips Chrome's first-run wizard |
| `https://teaserfast.ru` | Default startup URL — change this to any site |

```bash
echo "Starting x11vnc (no password)..."
x11vnc -display $DISPLAY -rfbport 5900 -nopw -forever -shared -bg -o /var/log/x11vnc.log 2>&1
sleep 2
```

**Step 5: VNC Server** — x11vnc captures the Xvfb display and serves it via VNC on port 5900.
- `-nopw` — No password (the Railway URL is already private/unguessable)
- `-forever` — Keep running after client disconnects
- `-shared` — Allow multiple simultaneous connections
- `-bg` — Run in background

```bash
echo "Starting noVNC on port $PORT..."
websockify --web /opt/noVNC $PORT localhost:5900 &
```

**Step 6: Web Proxy** — websockify serves two things on `$PORT`:
1. The noVNC web interface (`vnc.html`, `app.js`, etc.) from `/opt/noVNC`
2. A WebSocket proxy from the browser → `localhost:5900` (x11vnc)

```bash
echo "=== Desktop ready! ==="
echo "Open http://localhost:$PORT/vnc.html to connect"
wait
```

`wait` keeps the container alive by waiting for any background process to finish.

---

### 3. railway.json — Railway Config

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

Tells Railway to build using the Dockerfile and restart the container if it crashes.

---

### 4. How Everything Connects (The Pipeline)

```
User's Browser
      │
      ▼  (WebSocket)
┌─────────────────┐
│   websockify    │  Port 6080 ($PORT)
│  ┌───────────┐  │
│  │ noVNC     │  │  Serves vnc.html web page
│  │ (web app) │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │ WebSocket │  │  Proxies VNC traffic
│  │ Proxy     │  │
│  └─────┬─────┘  │
└────────┼────────┘
         │  (TCP)
┌────────▼────────┐
│   x11vnc        │  Port 5900
│   (VNC Server)  │  Captures screen
└────────┬────────┘
         │
┌────────▼────────┐
│   Xvfb          │  Display :0
│ (Virtual Screen)│  1280x720
└────────┬────────┘
         │
┌────────▼────────┐
│ Google Chrome   │  Renders web pages
│ ┌────────────┐  │
│ │ Sportsy    │  │  Auto-installed extension
│ │ Extension  │  │
│ └────────────┘  │
└─────────────────┘
```

**Data flow:**
1. You open `https://your-project.up.railway.app/vnc.html` in your browser
2. noVNC loads and opens a WebSocket connection to the Railway server
3. websockify proxies the WebSocket to x11vnc (TCP 5900)
4. x11vnc captures whatever is on the virtual display (Chrome)
5. The image is sent back through the chain to your browser
6. Your input (mouse clicks, keyboard) travels in reverse to Chrome

---

## Complete Setup Guide (From Zero)

### Prerequisites

| Requirement | Purpose |
|-------------|---------|
| GitHub account | Host the repository |
| Railway account | Deploy the container (free tier works) |

### Step 1: Create the Project Locally

Create this folder structure on your computer:

```
browser-desktop/
├── Dockerfile
├── start.sh
├── railway.json
├── .dockerignore
├── .gitignore
└── README.md
```

Copy the exact file contents from the sections above.

### Step 2: Customize It

Edit these values before pushing:

**In `Dockerfile`:**
- `RESOLUTION` — Change screen size (e.g., `1920x1080x24` for Full HD)
- Extension ID in the policy file — Replace with your preferred extension

**In `start.sh`:**
- `https://teaserfast.ru` — Replace with your default start URL

### Step 3: Push to GitHub

```bash
cd browser-desktop/
git init
git add .
git commit -m "Initial: browser desktop on Railway"
git branch -M main
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

### Step 4: Deploy on Railway

1. Go to https://railway.com and log in
2. Click **New Project** → **Deploy from GitHub**
3. Select your repository
4. Railway auto-detects the `Dockerfile` and builds
5. Wait for the build to complete (first build: 5-10 minutes)
6. Click the generated URL (e.g., `https://your-project.up.railway.app`)

### Step 5: Connect

1. Open the Railway URL in your browser
2. Click **Connect** (no password needed)
3. Google Chrome loads with `teaserfast.ru` and the Sportsy extension installed

---

## How to Customize

### Change the Default URL

Edit `start.sh`, line where `https://teaserfast.ru` appears:

```bash
https://your-desired-url.com &
```

### Change Screen Resolution

Edit the `RESOLUTION` line in `Dockerfile`:

```dockerfile
ENV RESOLUTION=1920x1080x24
```

### Install a Different Chrome Extension

1. Go to Chrome Web Store
2. Find the extension you want
3. Copy the extension ID from the URL: `https://chromewebstore.google.com/detail/.../`**`EXTENSION_ID`**
4. Edit `Dockerfile` line 48-49, replace the existing ID:

```dockerfile
"ExtensionInstallForcelist": [
    "YOUR_NEW_EXTENSION_ID"
]
```

Multiple extensions:

```dockerfile
"ExtensionInstallForcelist": [
    "EXTENSION_ID_1",
    "EXTENSION_ID_2"
]
```

### Use a Different Browser

- **Firefox**: Replace `google-chrome` with `firefox` (install via apt). Remove Chrome-specific flags.
- **Chromium (on Debian)**: Use `debian:bookworm-slim` base image and `apt install chromium`.

### Add a Password

In `start.sh`, change:

```bash
x11vnc -display $DISPLAY -rfbport 5900 -nopw ...
```

to:

```bash
x11vnc -display $DISPLAY -rfbport 5900 -passwd "mypassword" ...
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| Build fails, `no such option: --break-system-packages` | Old pip version | Remove `--break-system-packages` from Dockerfile |
| `chromium-browser: requires the chromium snap` | Ubuntu snap wrapper | Replace with Google Chrome (see Dockerfile above) |
| `password check failed` | Corrupted password file | Use `-nopw` or `-passwd "pass"` instead of `-storepasswd` |
| Black borders around browser | Window size mismatch | Use `--window-size=$W,$H --window-position=0,0` instead of `--start-maximized` |
| Browser crashes on start | Missing dependencies | Check logs; add missing libraries to `apt-get install` |
| Container exits immediately | Startup script error | Check Railway deployment logs; remove `set -e` temporarily |
| Can't connect to noVNC | Wrong PORT | Railway overrides `$PORT` — websockify must use `$PORT` not hardcoded value |
| Slow/laggy display | High resolution | Lower to `1280x720x24` or `1024x768x24` |

### How to View Logs

1. Railway Dashboard → your project → **Deployments** → click deployment
2. Click **View Logs**
3. Look for errors in the build and runtime logs
4. The startup script prints status messages prefixed with `===`

---

## Architecture Diagram (Simplified)

```
┌─────────────────────────────────────────────────────┐
│                     Railway                          │
│  ┌─────────────────────────────────────────────┐   │
│  │           Docker Container                    │   │
│  │                                               │   │
│  │  ┌──────────┐    ┌──────────┐    ┌────────┐  │   │
│  │  │ noVNC    │◄──►│x11vnc    │◄──►│ Chrome │  │   │
│  │  │ (web UI) │    │(VNC srv) │    │(browser│  │   │
│  │  │ :6080    │    │ :5900    │    │  :0)   │  │   │
│  │  └────┬─────┘    └──────────┘    └────────┘  │   │
│  │       │                            Xvfb ▲      │   │
│  │       │                           (virtual │    │   │
│  │       │                            display)│    │   │
│  │       └────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────┘   │
│            │                                        │
└────────────┼────────────────────────────────────────┘
             │  HTTPS
             ▼
     ┌──────────────┐
     │  Your Browser │  ← Open Railway URL
     │  (any device)  │
     └──────────────┘
```

---

## Key Concepts Summary

| Concept | What it does |
|---------|-------------|
| **Xvfb** | Creates a fake monitor so apps think a screen exists |
| **x11vnc** | Takes screenshots of the fake monitor and serves them via VNC |
| **noVNC** | A web page that speaks VNC over WebSocket so no VNC client needed |
| **websockify** | Translates WebSocket↔TCP so browser can talk to VNC server |
| **Google Chrome** | The app we want to use remotely |
| **Chrome Policies** | JSON files that force-install extensions, set defaults |
| **Railway** | Cloud platform that builds and hosts the Docker container |
| **$PORT** | Railway's env var — must match noVNC's port |

---

## Quick Reference: Common Commands

```bash
# Local test
docker build -t browser-desktop .
docker run -d -p 6080:6080 browser-desktop
# Open http://localhost:6080/vnc.html

# Push to GitHub
git add .
git commit -m "message"
git push

# Railway auto-deploys on git push
```
