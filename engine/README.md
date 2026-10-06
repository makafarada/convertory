# Convertory conversion engine (container)

Linux container that runs the same `conversion-engine.py` the Windows build uses,
with LibreOffice (Word/Excel/PowerPoint to PDF) and Tesseract (OCR) instead of
Windows COM/OCR. The Cloudflare Pages Function `functions/api/convert.js`
forwards the tools in `functions/_lib/engineTools.js` to it.

Tools served: PDF to Excel, PDF to PowerPoint, Image to Excel, Image to Text,
Word/Excel/PowerPoint to PDF, Compress PDF, More Formats.

## Run / test locally (no Docker needed for the PDF tools)

    ENGINE_TOKEN=secret PORT=8791 python engine/server.py

## Build and deploy

    docker build -f engine/Dockerfile -t convertory-engine .

Host it anywhere that runs a container (Cloud Run, Fly.io, Cloudflare
Containers). It needs ~1 GB RAM. Set `ENGINE_TOKEN` on the container, then on the
Pages project set the secrets `ENGINE_URL` (https base URL) and `ENGINE_TOKEN`
(same value). Until both are set the site keeps advertising only the 5 built-in
tools via `/api/capabilities`, so nothing breaks.

## Before going live

- Files now leave the device for these tools: update `ms-store/privacy.html`,
  the store listings and any "100% on-device" claims.
- The container never stores files (temp dir per job, deleted after) and never
  logs request bodies.
