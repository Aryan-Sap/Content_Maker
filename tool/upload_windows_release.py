"""Upload the installer atomically through the site's authenticated release endpoint.

RELEASE_UPLOAD_TOKEN must be supplied through the process environment.
"""
import hashlib
import json
import os
import socket
from pathlib import Path
import time
from urllib.request import Request, urlopen

installer = Path(__file__).resolve().parents[1] / 'dist/ContentMakerSetup.exe'
base = 'https://contentmaker.site/api/releases/windows/multipart'
token = os.environ['RELEASE_UPLOAD_TOKEN']
# Optional provider-confirmed address for a local DNS resolver outage. TLS still
# verifies contentmaker.site; this does not change system DNS or the Host header.
if address := os.environ.get('RELEASE_HOST_IP'):
    original_resolver = socket.getaddrinfo
    def resolve(host, port, *args, **kwargs):
        return original_resolver(address if host == 'contentmaker.site' else host,
                                 port, *args, **kwargs)
    socket.getaddrinfo = resolve

def request(method, url, body=None, content_type='application/octet-stream'):
    req = Request(url, data=body, method=method, headers={
        'Authorization': f'Bearer {token}', 'Content-Type': content_type,
        'User-Agent': 'ContentMaker-ReleaseUploader/1.1',
    })
    with urlopen(req, timeout=120) as response:
        raw = response.read()
        return json.loads(raw) if raw else None

upload = request('POST', base, b'')
upload_url = base + '/' + upload['uploadId']
parts = []
try:
    with installer.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            number = len(parts) + 1
            for attempt in range(3):
                try:
                    part = request('PUT', upload_url + '/' + str(number), chunk)
                    break
                except Exception:
                    if attempt == 2:
                        raise
                    time.sleep(2)
            parts.append(part)
            print(f'Uploaded part {number}', flush=True)
    result = request('POST', upload_url + '/complete',
                     json.dumps({'parts': parts}).encode(), 'application/json')
    assert result['size'] == installer.stat().st_size
    print(f'Published installer: {result["size"]} bytes', flush=True)
except Exception:
    request('DELETE', upload_url + '/abort')
    raise

local_hash = hashlib.file_digest(installer.open('rb'), 'sha256').hexdigest()
remote_hash = hashlib.sha256()
with urlopen(Request('https://contentmaker.site/downloads/ContentMakerSetup.exe?verify=' + local_hash,
                    headers={'User-Agent': 'ContentMaker-ReleaseUploader/1.1'}),
             timeout=120) as response:
    while chunk := response.read(8 * 1024 * 1024):
        remote_hash.update(chunk)
assert remote_hash.hexdigest() == local_hash, 'Downloaded installer differs from local release'
print('Verified live installer SHA-256: ' + local_hash, flush=True)
