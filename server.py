import http.server
import os
import urllib.parse
from pathlib import Path

PORT = 3000
ROOT = Path(__file__).parent.resolve()

MIME_TYPES = {
    '.html':  'text/html',
    '.js':    'application/javascript',
    '.mjs':   'application/javascript',
    '.css':   'text/css',
    '.json':  'application/json',
    '.png':   'image/png',
    '.jpg':   'image/jpeg',
    '.jpeg':  'image/jpeg',
    '.gif':   'image/gif',
    '.svg':   'image/svg+xml',
    '.ico':   'image/x-icon',
    '.woff':  'font/woff',
    '.woff2': 'font/woff2',
    '.txt':   'text/plain',
}


class Handler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        url_path = urllib.parse.unquote(self.path.split('?')[0])
        file_path = (ROOT / url_path.lstrip('/')).resolve()

        if not str(file_path).startswith(str(ROOT)):
            self._send(403, 'text/plain', b'Forbidden')
            return

        if not file_path.exists():
            self._send(404, 'text/plain', b'Not Found')
            return

        if file_path.is_dir():
            index_path = file_path / 'index.html'
            if index_path.exists():
                self._send(200, 'text/html', index_path.read_bytes())
            else:
                self._serve_directory(file_path, url_path)
            return

        ext = file_path.suffix
        content_type = MIME_TYPES.get(ext, 'application/octet-stream')
        self._send(200, content_type, file_path.read_bytes())

    def _serve_directory(self, dir_path, url_path):
        base = url_path.rstrip('/')
        rows = []
        for entry in sorted(dir_path.iterdir()):
            name = entry.name
            is_dir = entry.is_dir()
            href = f'{base}/{name}{"/" if is_dir else ""}'
            rows.append(f'<li><a href="{href}">{name}{"/" if is_dir else ""}</a></li>')
        html = f'<!DOCTYPE html><html><body><h2>{url_path}</h2><ul>{"".join(rows)}</ul></body></html>'
        self._send(200, 'text/html', html.encode())

    def _send(self, status, content_type, body: bytes):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f'{self.address_string()} - {fmt % args}')


if __name__ == '__main__':
    os.chdir(ROOT)
    with http.server.HTTPServer(('', PORT), Handler) as server:
        print(f'서버 실행 중: http://localhost:{PORT}')
        server.serve_forever()
