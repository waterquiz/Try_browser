#!/usr/bin/env python3
import asyncio, os, pty, struct, termios, fcntl, json
from aiohttp import web

HTML = """<!DOCTYPE html>
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
const ws = new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/ws');
ws.onmessage = e => term.write(e.data);
term.onData(d => ws.send('i'+d));
term.onResize(({cols,rows}) => ws.send('r'+JSON.stringify({cols,rows})));
term.element.addEventListener('contextmenu', e => { e.preventDefault();
  navigator.clipboard.readText().then(t => term.paste(t)).catch(()=>{});
});
</script></body></html>"""

async def handle_root(request):
    return web.Response(text=HTML, content_type='text/html')

async def handle_ws(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    loop = asyncio.get_event_loop()
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execvp('bash', ['bash'])
        os._exit(1)
    try:
        async def reader():
            while True:
                data = await loop.run_in_executor(None, os.read, fd, 65536)
                if not data: break
                await ws.send_bytes(data)
        async def writer():
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    d = msg.data
                    if d.startswith('i'):
                        os.write(fd, d[1:].encode())
                    elif d.startswith('r'):
                        data = json.loads(d[1:])
                        win = struct.pack("HHHH", data['rows'], data['cols'], 0, 0)
                        fcntl.ioctl(fd, termios.TIOCSWINSZ, win)
                elif msg.type == web.WSMsgType.ERROR:
                    break
        await asyncio.gather(reader(), writer())
    finally:
        try: os.close(fd)
        except: pass
        try: os.kill(pid, 9)
        except: pass
    return ws

app = web.Application()
app.router.add_get('/', handle_root)
app.router.add_get('/ws', handle_ws)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    web.run_app(app, port=port, handle_signals=False)
