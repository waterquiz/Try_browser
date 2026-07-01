# Cloud Terminal — Web-based Shell on Railway

**Terminal access** in your browser. No Chrome, no desktop, no VNC.  
Just a command-line shell served over HTTP/WebSocket via `ttyd`.

Open the URL → you get a `bash` terminal in your browser.

---

## File Structure

```
cloud-terminal/
├── Dockerfile       # Builds Ubuntu + ttyd (web terminal)
├── start.sh         # Starts ttyd
├── railway.json     # Railway deploy config
├── .dockerignore    # Excludes files from Docker
├── .gitignore       # Excludes files from git
└── README.md        # This file
```

---

## How It Works

```
Your Browser
    │
    │  HTTPS → https://project.up.railway.app/
    ▼
┌─────────────────────────────────┐
│         RAILWAY SERVER          │
│  ┌───────────────────────────┐  │
│  │      Docker Container     │  │
│  │                           │  │
│  │  ttyd ──► WebSocket ──►   │  │
│  │  port $PORT    bash shell │  │
│  │                           │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**ttyd** is a lightweight terminal emulator for the web. It:
1. Serves an HTML page with a terminal emulator (xterm.js)
2. Opens a WebSocket connection to your browser
3. Spawns a `bash` process and connects it to the WebSocket
4. You type → WebSocket → bash → output → WebSocket → your screen

There is no Chrome, no VNC, no desktop GUI. Just a shell.

---

## File-by-File Explanation

### Dockerfile

```dockerfile
FROM ubuntu:22.04
```

Minimal Ubuntu base image.

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080
```

Railway overrides `$PORT` automatically.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl ca-certificates \
    build-essential cmake \
    libjson-c-dev libwebsockets-dev \
    git \
    && rm -rf /var/lib/apt/lists/*
```

**Build dependencies for ttyd.** These are needed to compile ttyd from source:
- `build-essential` — compiler + make
- `cmake` — build system
- `libjson-c-dev` — JSON library
- `libwebsockets-dev` — WebSocket library
- `git` — clone ttyd source

```dockerfile
RUN git clone https://github.com/tsl0922/ttyd.git /tmp/ttyd && \
    cd /tmp/ttyd && \
    mkdir build && cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/ttyd
```

**Compiles ttyd** from source and installs the binary to `/usr/local/bin/ttyd`.

```dockerfile
EXPOSE ${PORT}
CMD ttyd --port $PORT bash
```

Starts ttyd on port `$PORT` serving a `bash` shell.

### start.sh

```bash
#!/bin/bash
set -e
echo "=== Starting Terminal Access ==="
echo "Open http://localhost:$PORT/ to access the terminal"
ttyd --port $PORT bash
```

Simple wrapper — starts ttyd with bash.

### railway.json

Tells Railway to build via Dockerfile, restart on failure.

---

## Complete Method — Zero to Deployed

### Step 1: Create the Project

```
cloud-terminal/
├── Dockerfile
├── start.sh
├── railway.json
├── .dockerignore    (optional)
├── .gitignore       (optional)
└── README.md
```

Copy code from above.

### Step 2: Push to GitHub

```powershell
git init
git add .
git commit -m "Cloud terminal: ttyd on Railway"
git branch -M main
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

### Step 3: Deploy on Railway

1. https://railway.com → New Project → Deploy from GitHub
2. Select your repo
3. Railway builds automatically (first build compiles ttyd, takes ~3-5 min)
4. Open the generated URL → you get a bash terminal

---

## Customization

### Change the Shell

In `Dockerfile` or `start.sh`, replace `bash` with:

```bash
ttyd --port $PORT zsh
ttyd --port $PORT sh
ttyd --port $PORT fish
ttyd --port $PORT python3
```

### Add Command-Line Arguments

ttyd supports many options:

```bash
# Basic auth
ttyd --port $PORT -c user:password bash

# Read-only mode (no input)
ttyd --port $PORT -R bash

# Custom title
ttyd --port $PORT -t title="My Terminal" bash

# Larger font / custom theme
ttyd --port $PORT -t fontSize=16 -t theme='{"background": "#1e1e1e"}' bash
```

Full docs: https://github.com/tsl0922/ttyd

### Use a Pre-built Binary (Faster Build)

Instead of compiling from source:

```dockerfile
RUN wget -q -O /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd
```

Then remove the `RUN git clone ...` block and the build dependencies for smaller image size.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Build fails: cmake error | Missing dependency | Ensure `libwebsockets-dev` is installed |
| Build takes too long | Compiling from source | Use pre-built binary instead (see above) |
| Terminal loads but no prompt | WebSocket blocked | Check Railway port config |
| Connection refused | Wrong port | ttyd must use `$PORT` (Railway env var) |
| Terminal disconnects | Idle timeout | Add `-t idleTimeout=0` to disable |

---

## Quick Commands

```powershell
# Test locally
docker build -t cloud-terminal .
docker run -d -p 8080:8080 cloud-terminal
# Open http://localhost:8080/

# Push update
git add .
git commit -m "update"
git push
```
