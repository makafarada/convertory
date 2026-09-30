import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';

const input = process.argv[2];
assert(input, 'Pass a real PDF path');
const base = process.env.CONVERTORY_URL || 'http://127.0.0.1:4755';
const filename = 'Türkçe-İşlem-şğı-test.docx';
const response = await fetch(`${base}/api/pdf-to-docx`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/pdf',
    'X-Convertory-Response': 'download-url',
    'X-Convertory-Output-Name': encodeURIComponent(filename),
  },
  body: await readFile(input),
  signal: AbortSignal.timeout(120000),
});
assert.equal(response.status, 200, await response.clone().text());
const result = await response.json();
const url = new URL(result.downloadUrl, base);
let original;
for (let attempt = 1; attempt <= 2; attempt++) {
  const download = await fetch(url);
  assert.equal(download.status, 200, `Download ${attempt}`);
  assert(download.headers.get('content-disposition').includes(encodeURIComponent(filename)));
  const bytes = Buffer.from(await download.arrayBuffer());
  assert.equal(bytes.subarray(0, 4).toString('hex'), '504b0304');
  assert(bytes.length > 1024);
  if (original) assert.deepEqual(bytes, original, 'Repeated download must be identical');
  original = bytes;
}
await mkdir('tmp', {recursive: true});
await writeFile('tmp/verified-download.docx', original);
const save = await fetch(new URL(result.downloadUrl.replace('/api/download/', '/api/save/'), base), {method:'POST'});
assert.equal(save.status, 200);
assert((await save.json()).savedFile.endsWith('.docx'));
const invalid = await fetch(`${base}/api/pdf-to-docx`, {
  method: 'POST', headers: {'Content-Type': 'application/pdf'}, body: 'not a PDF',
});
assert.equal(invalid.status, 400);
assert((await invalid.json()).error);
console.log(JSON.stringify({passed: true, bytes: original.length, repeatedDownloads: 2, unicodeFilename: true, invalidInputRejected: true, savedFile: result.savedFile}));
