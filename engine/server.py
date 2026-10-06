"""HTTP wrapper around conversion-engine.py for container hosting.

POST /convert  (header X-Engine-Token must match $ENGINE_TOKEN)
  body: {"tool": "...", "files": [{"name": "a.pdf", "data": "<base64>"}], "options": {...}}
  200:  {"outputName": "...", "dataBase64": "...", "note": "..."}
  422:  {"error": "..."}
GET /health -> 200 "ok"
"""
import base64
import importlib.util
import json
import os
import re
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENGINE_FILE = HERE / 'conversion-engine.py'
if not ENGINE_FILE.exists():  # running from the repo checkout instead of the image
    ENGINE_FILE = HERE.parent / 'conversion-engine.py'
spec = importlib.util.spec_from_file_location('conversion_engine', ENGINE_FILE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

TOKEN = os.environ.get('ENGINE_TOKEN', '')
MAX_BODY = 40 * 1024 * 1024
slots = threading.BoundedSemaphore(int(os.environ.get('ENGINE_CONCURRENCY', '2')))

IMAGES = ('.png', '.jpg', '.jpeg', '.webp')
KINDS = {
    'PDF to Excel': (('.pdf',), '.xlsx'), 'PDF to PowerPoint': (('.pdf',), '.pptx'),
    'PDF to Text': (('.pdf',), '.txt'), 'Image to PDF': (IMAGES, '.pdf'),
    'Image to Excel': (IMAGES, '.xlsx'), 'Image to Text': (IMAGES, '.txt'),
    'Word to PDF': (('.docx', '.doc', '.rtf'), '.pdf'), 'Excel to PDF': (('.xlsx', '.xls', '.csv'), '.pdf'),
    'PowerPoint to PDF': (('.pptx', '.ppt'), '.pdf'), 'Merge PDF': (('.pdf',), '.pdf'),
    'Compress PDF': (('.pdf',), '.pdf'), 'Watermark PDF': (('.pdf',), '.pdf'),
    'More Formats': (('.pdf',), '.zip'),
}


class Rejected(Exception):
    pass


def convert(job):
    tool = job.get('tool')
    if tool not in KINDS:
        raise Rejected('Choose a supported conversion.')
    files = job.get('files')
    if not isinstance(files, list) or not 1 <= len(files) <= 20:
        raise Rejected('Select between 1 and 20 files.')
    if len(files) > 1 and tool not in ('Merge PDF', 'Image to PDF'):
        raise Rejected('Select one file for this conversion.')
    inputs, extension_out = KINDS[tool]
    options = job.get('options') or {}
    if tool == 'More Formats' and options.get('format') == 'txt':
        extension_out = '.txt'
    with tempfile.TemporaryDirectory(prefix='convertory-job-') as folder:
        paths = []
        for index, file in enumerate(files):
            name = str(file.get('name', ''))
            extension = os.path.splitext(name)[1].lower()
            if extension not in inputs:
                raise Rejected(f"{tool} requires {','.join(inputs)} files.")
            data = base64.b64decode(file.get('data') or '')
            if not data:
                raise Rejected('The selected file is empty.')
            path = Path(folder) / f'input-{index}{extension}'
            path.write_bytes(data)
            paths.append(str(path))
        output = Path(folder) / f'output{extension_out}'
        try:
            result = engine.run({'tool': tool, 'paths': paths, 'output': str(output), 'options': options})
        except ValueError as error:
            raise Rejected(str(error))
        except Exception as error:  # engine/library failure: do not leak internals
            print(f'[engine] {tool} failed: {error!r}', flush=True)
            raise Rejected('Conversion failed. Check that the input file opens normally.')
        stem = re.sub(r'[\\/:*?"<>|]', '_', os.path.splitext(str(files[0].get('name', 'converted')))[0]).strip() or 'converted'
        return {
            'outputName': stem + extension_out,
            'dataBase64': base64.b64encode(output.read_bytes()).decode('ascii'),
            'note': result.get('note', ''),
        }


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, payload, content_type='application/json'):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health':
            self.reply(200, b'ok', 'text/plain')
        else:
            self.reply(404, {'error': 'Not found'})

    def do_POST(self):
        if self.path != '/convert':
            return self.reply(404, {'error': 'Not found'})
        if not TOKEN or self.headers.get('X-Engine-Token') != TOKEN:
            return self.reply(401, {'error': 'Unauthorized'})
        length = int(self.headers.get('Content-Length') or 0)
        if length <= 0 or length > MAX_BODY:
            return self.reply(413, {'error': 'File is too large (limit 25 MB).'})
        if not slots.acquire(timeout=60):
            return self.reply(503, {'error': 'The converter is busy. Try again in a moment.'})
        try:
            self.reply(200, convert(json.loads(self.rfile.read(length))))
        except Rejected as error:
            self.reply(422, {'error': str(error)})
        except Exception as error:
            print(f'[engine] unexpected: {error!r}', flush=True)
            self.reply(422, {'error': 'Conversion failed. Check that the input file opens normally.'})
        finally:
            slots.release()

    def log_message(self, fmt, *args):  # never log request contents
        print('[engine]', fmt % args, flush=True)


if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', int(os.environ.get('PORT', '8080'))), Handler).serve_forever()
