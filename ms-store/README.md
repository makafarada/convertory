# Convertory Microsoft Store Package

This folder contains the Windows preview surface for Convertory. It is the web UI portion of an MSIX desktop package; the editable DOCX workflow requires its local companion runtime.

The Android APK/AAB cannot be uploaded as a normal Microsoft Store desktop app. For Store distribution on Windows, Convertory needs a Windows package such as PWA/MSIX, WinUI, .NET MAUI, Electron, or a Store-supported Android route where available to the account. This package uses the quickest Store-compatible path: installable PWA.

## Local Preview

Run `open-ms-store-preview.cmd` from the package root. It starts a local, no-cache preview at `http://127.0.0.1:4755/`, so the browser always loads the current app files.

## Store Packaging

1. Bundle `preview-server.mjs`, `convert-pdf-to-docx.py`, `conversion-engine.py`, `vendor/pdf2docx/`, and `runtime/` into a local desktop host. `runtime/python/` (a portable Python 3.12 interpreter) and `runtime/poppler/` (a portable `pdftotext.exe`) are already bundled machine-independent — `preview-server.mjs` prefers them automatically over any dev-machine path, so no end-user Python/Poppler install is required. Verified end-to-end (PDF→DOCX/XLSX/PPTX/TXT, Image→PDF) via the local preview server with these bundled runtimes only. (Folder names avoid a leading dot — MSIX packaging rejects dot-prefixed paths.)
2. Validate `manifest.webmanifest` and the local DOCX workflow.
3. Generate an MSIX that starts the local host process. Done: see `msix/` — `msix/package/` is the AppX payload (built via a Node.js Single Executable Application launcher, `Convertory.exe`, since no .NET SDK is available on this machine to compile a native host), `msix/Convertory.msix` is the packaged output.
4. In Partner Center, create a Windows app listing and upload that desktop MSIX.

## What Is Included

- `index.html`: Windows-first app shell and product surface
- `styles.css`: responsive Store-quality UI styling
- `app.js`: editable PDF-to-DOCX workflow
- `../convert-pdf-to-docx.py`: local PDF layout reconstruction helper
- `manifest.webmanifest`: install metadata for PWA/MSIX generation

PDF to Word sends the selected document only to the local preview process at `127.0.0.1`. The bundled local engine reconstructs selectable text, images, tables, and layout into an editable `.docx`; it does not export page screenshots. Scanned PDFs still require a separate OCR engine.
