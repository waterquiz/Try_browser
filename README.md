# Web Terminal — Cloud Shell via ttyd on Railway

**Terminal access only.** No browser, no desktop, no GUI.  
This project gives you a **bash terminal** in your browser — a cloud shell running on Railway.

Open the URL → you get a terminal prompt. That's it.

---

## File Structure

```
web-terminal/
├── Dockerfile          # Ubuntu + ttyd (web terminal binary)
├── start.sh            # Starts ttyd on $PORT
├── railway.json        # Railway config
├── .dockerignore
├── .gitignore
└── README.md
```

---

## How It Works

```
Your Browser
    │  HTTPS → https://project.up.railway.app/
    ▼
┌──────────────────────────────────┐
│          RAILWAY SERVER          │
│  ┌────────────────────────────┐  │
│  │       Docker Container     │  │
│  │                           │  │
│  │   ttyd ──► /bin/bash      │  │
│  │   (web term)  (shell)     │  │
│  │       :$PORT              │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

**ttyd** is a single Go binary that:
- Serves an xterm.js terminal in any browser
- Spawns a shell (`bash`) on connection
- Supports websockets for real-time I/O
- Requires no Xvfb, no VNC, no browser streaming

---

## File 1: Dockerfile

```dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080
```

Minimal Ubuntu. No X11, no display, no GUI packages at all.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates curl \
    git nano htop sudo bash \
    && rm -rf /var/lib/apt/lists/*
```

Only CLI tools:
- `wget` — downloads ttyd binary
- `git`, `nano`, `htop` — useful terminal tools
- `sudo` — allow privilege escalation
- `bash` — the shell

```dockerfile
RUN wget -q -O /usr/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /usr/bin/ttyd
```

Downloads **ttyd v1.7.7** for x86_64 — a single static binary, no dependencies.

```dockerfile
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE ${PORT}
CMD ["/start.sh"]
```

---

## File 2: start.sh

```bash
#!/bin/bash
set -e

echo "=== Web Terminal Starting ==="

ttyd -p $PORT bash
```

That's it. One command. `ttyd` listens on `$PORT` and spawns `bash` for each connection.

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

---

## Complete Method — Zero to Terminal

### Step 1: Create Project

```
web-terminal/
├── Dockerfile
├── start.sh
├── railway.json
├── .dockerignore
├── .gitignore
└── README.md
```

### Step 2: Push to GitHub

```powershell
git init
git add .
git commit -m "Web terminal via ttyd on Railway"
git branch -M main
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

### Step 3: Deploy on Railway

1. https://railway.com → **New Project** → **Deploy from GitHub**
2. Select your repo → Railway auto-builds
3. Wait ~2-3 minutes
4. Open the generated URL

### Step 4: Use the Terminal

Open the Railway URL → you get a `bash` prompt. Type commands, run scripts, install packages.

---

## Customization

### Change the Shell

In `start.sh`:

```bash
ttyd -p $PORT zsh      # Z shell
ttyd -p $PORT fish     # Fish shell
ttyd -p $PORT sh       # Basic shell
```

### Add Authentication

```bash
ttyd -p $PORT -c user:password bash
```

Then log in with username `user` and password `password` when prompted.

### Install More Tools

In `Dockerfile`:

```dockerfile
RUN apt-get install -y python3 nodejs vim tmux
```

### Use a Different Base

```dockerfile
FROM debian:bookworm-slim
FROM alpine:latest       # Smaller image (~5MB)
FROM python:3.11-slim   # Python pre-installed
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Blank page | WebSocket blocked | Use a modern browser |
| Connection refused | Railway PORT mismatch | Ensure ttyd uses `$PORT` |
| Permission denied | ttyd binary not executable | Check `chmod +x` |
| Command not found | Missing packages | Add to `apt-get install` |

---

## Local Test

```powershell
docker build -t web-terminal .
docker run -d -p 8080:8080 web-terminal
# Open http://localhost:8080
```

---

## Quick Reference

```powershell
# Build & test
docker build -t web-terminal .
docker run -d -p 8080:8080 web-terminal

# Deploy updates
git add .
git commit -m "update"
git push
```
