# Debian Browser Desktop via noVNC

Lightweight Debian XFCE desktop with Chromium, accessible via web browser using noVNC.

## Features
- Debian Bookworm + XFCE4 desktop
- Chromium browser (supports extensions)
- noVNC web-based VNC client (no RDP client needed)
- Password-protected connection
- Railway-deployable (single $PORT)

## Deploy on Railway

1. Push this repo to GitHub
2. Go to [railway.com](https://railway.com) → New Project → Deploy from GitHub
3. Select this repo → Railway detects the Dockerfile
4. Set environment variables (optional):
   - `VNC_PASSWORD` - VNC password (default: `debian`)
   - `RESOLUTION` - Screen resolution (default: `1280x720x24`)
5. Open the generated `*.up.railway.app` URL
6. Click **Connect** → enter password → desktop loads!

## Local Test

```bash
docker build -t browser-desktop .
docker run -d -p 6080:6080 -e VNC_PASSWORD=debian browser-desktop
```

Open http://localhost:6080/vnc.html → Connect → password: `debian`
