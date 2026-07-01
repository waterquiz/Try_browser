# Cloud Terminal — Web-based Shell on Railway

**Terminal access** in your browser. No Chrome, no desktop, no VNC.  
Open the URL → you get a `bash` shell powered by `xterm.js` + Python `aiohttp`.

---

## File Structure

```
cloud-terminal/
├── Dockerfile       # Ubuntu + Python + aiohttp
├── server.py        # Web terminal server (xterm.js + WebSocket + PTY)
├── railway.json     # Railway deploy config
├── .dockerignore    # Excludes files from Docker build
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
┌─────────────────────────────────────┐
│          RAILWAY SERVER             │
│  ┌───────────────────────────────┐  │
│  │        Docker Container       │  │
│  │                               │  │
│  │  Python server.py on $PORT    │  │
│  │  ┌─────────┐   ┌──────────┐  │  │
│  │  │ HTTP: / │──►│ xterm.js │  │  │
│  │  │ (HTML)  │   │ (browser │  │  │
│  │  └─────────┘   │  UI)     │  │  │
│  │                └────┬─────┘  │  │
│  │  ┌─────────┐        │        │  │
│  │  │ WS: /ws │◄───────┘        │  │
│  │  │ (WebSock│                │  │
│  │  │  ->PTY) │──► bash shell  │  │
│  │  └─────────┘                │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Data flow:**
1. Your browser loads `https://url/` → receives HTML page with `xterm.js`
2. xterm.js opens a **WebSocket** to `wss://url/ws`
3. Python `aiohttp` receives the WebSocket connection
4. It spawns a **PTY** (pseudo-terminal) running `bash`
5. xterm.js output → WebSocket → PTY → bash
6. bash output → PTY → WebSocket → xterm.js in your browser

---

## File-by-File

### server.py — The Core

```python
# Uses xterm.js (frontend) + Python PTY (backend)
# WebSocket bridges browser ↔ bash shell
```

Key components:
- **xterm.js** (CDN) — full-featured terminal emulator in the browser
- **aiohttp WebSocket** — real-time bidirectional communication
- **Python PTY** — creates a real pseudo-terminal that bash runs in
- **TIOCSWINSZ** — handles terminal resize events

### Dockerfile

```dockerfile
FROM ubuntu:22.04
RUN apt-get install -y python3 python3-pip
RUN pip3 install aiohttp
COPY server.py /server.py
CMD python3 /server.py
```

Minimal — just Python + aiohttp + the script.

---

## Customization

### Change the Shell

In `server.py`, replace `bash` with any command:

```python
os.execvp('zsh', ['zsh'])
os.execvp('sh', ['sh'])
os.execvp('python3', ['python3'])
```

### Change Terminal Theme

In `server.py` HTML, modify xterm.js options:

```javascript
const term = new Terminal({
  cursorBlink: true,
  fontSize: 15,
  fontFamily: 'Menlo,Consolas,monospace',
  theme: {
    background: '#1e1e1e',
    foreground: '#d4d4d4',
    cursor: '#d4d4d4'
  }
});
```
