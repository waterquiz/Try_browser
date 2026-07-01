#!/usr/bin/env python3
import asyncio, os, pty, struct, termios, fcntl, signal, json
from websockets.server import serve
from websockets.http import Headers

HTML = b"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5/css/xterm.css">
<script src="https://cdn.jsdelivr.net/npm/xterm@5/lib/xterm.js"></script>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#111}
  #term{height:100vh;width:100vw}
</style>
</head>
<body><div id="term"></div>
<script>
const term = new Terminal({cursorBlink:true, fontSize:15, fontFamily:'Menlo,Consolas,monospace'});
term.open(document.getElementById('term'));
const ws = new WebSocket(location.href.replace(/^http/,'ws')+'ws');
ws.onmessage = e => term.write(e.data);
term.onData(d => ws.send('i'+d));
term.onResize(({cols,rows}) => ws.send('r'+JSON.stringify({cols,rows})));
term.element.addEventListener('contextmenu', e => { e.preventDefault();
  navigator.clipboard.readText().then(t => term.paste(t)).catch(()=>{});
});
</script></body></html>"""

async def shell(ws):
    loop = asyncio.get_event_loop()
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execvp('bash', ['bash'])
        os._exit(1)
    try:
        def resize(cols, rows):
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        async def read_pty():
            while True:
                data = await loop.run_in_executor(None, os.read, fd, 65536)
                if not data: break
                await ws.send(data)
        async def write_pty():
            async for msg in ws:
                if msg.startswith('i'):
                    os.write(fd, msg[1:].encode())
                elif msg.startswith('r'):
                    d = json.loads(msg[1:])
                    resize(d['cols'], d['rows'])
        await asyncio.gather(read_pty(), write_pty())
    finally:
        try: os.close(fd)
        except: pass
        try: os.kill(pid, 9)
        except: pass

async def process_req(path, req_headers):
    if path == '/ws':
        return None
    return 200, Headers([('Content-Type', 'text/html; charset=utf-8')]), HTML

async def main():
    port = int(os.environ.get('PORT', 8080))
    async with serve(shell, '0.0.0.0', port, process_request=process_req):
        await asyncio.get_running_loop().create_future()

if __name__ == '__main__':
    asyncio.run(main())
