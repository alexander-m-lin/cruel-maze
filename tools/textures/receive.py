"""Receive images from Roblox Studio and serve them back for upload.

Studio can't save files, but a script there can read an image's pixels (EditableImage) and POST
them here, a block of rows at a time (HttpService posts are limited to about 1 MB):

    POST /<name>.png?w=<width>&h=<height>&y=<first row>   body: raw RGBA bytes of those rows

When every row has arrived the image is saved as <out dir>/<name>.png. The same server answers
GET /<name>.png, so the Studio MCP's upload_image can be given http://127.0.0.1:<port>/<name>.png.

usage: python receive.py <out dir> [port]     (default port 8765; Ctrl+C to stop)
"""
import os, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from PIL import Image

OUT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
os.makedirs(OUT, exist_ok=True)
pending = {}   # name -> {"w", "h", "buf", "rows"}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=OUT, **kwargs)

    def do_POST(self):
        url = urlparse(self.path)
        name = os.path.basename(url.path)
        q = parse_qs(url.query)
        w, h, y = int(q["w"][0]), int(q["h"][0]), int(q["y"][0])
        data = self.rfile.read(int(self.headers["Content-Length"]))
        rows = len(data) // (w * 4)
        p = pending.setdefault(name, {"w": w, "h": h, "buf": bytearray(w * h * 4), "rows": set()})
        p["buf"][y * w * 4:y * w * 4 + len(data)] = data
        p["rows"].update(range(y, y + rows))
        done = len(p["rows"]) >= h
        if done:
            Image.frombytes("RGBA", (w, h), bytes(p["buf"])).save(os.path.join(OUT, name))
            del pending[name]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"saved" if done else b"ok")


print(f"receiving into {OUT} on http://127.0.0.1:{PORT}")
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
