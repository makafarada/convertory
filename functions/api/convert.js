import { mergePdf } from "../_lib/tools/mergePdf.js";
import { watermarkPdf } from "../_lib/tools/watermarkPdf.js";
import { imageToPdf } from "../_lib/tools/imageToPdf.js";
import { pdfToText } from "../_lib/tools/pdfToText.js";

// Tools implemented as real JS in this Cloudflare Pages Function. Every other
// tool name preview-server.mjs/conversion-engine.py handle (Compress PDF, OCR
// tools, Office conversions, PDF to Excel/PowerPoint/Word, the PNG branch of
// More Formats) is intentionally NOT here yet -- they need Python/native
// binaries/a WASM renderer that don't run in a V8-isolate Function, so on
// this deployment they fall through to the `unsupported` branch below and
// return a clear error instead of a 404.
const SUPPORTED_TOOLS = new Set(["Merge PDF", "Watermark PDF", "Image to PDF", "PDF to Text"]);

const EXPECTED_INPUT_EXT = {
  "Merge PDF": [".pdf"],
  "Watermark PDF": [".pdf"],
  "Image to PDF": [".png", ".jpg", ".jpeg", ".webp"],
  "PDF to Text": [".pdf"]
};

const OUTPUT_EXT = {
  "Merge PDF": ".pdf",
  "Watermark PDF": ".pdf",
  "Image to PDF": ".pdf",
  "PDF to Text": ".txt"
};

const CONTENT_TYPE = {
  ".pdf": "application/pdf",
  ".txt": "text/plain;charset=utf-8"
};

function safeOutputName(value, ext) {
  const fallback = `converted${ext}`;
  const name = String(value || fallback).replace(/[\\/:*?"<>|]/g, "_").trim();
  if (!name) return fallback;
  return name.toLowerCase().endsWith(ext) ? name : `${name}${ext}`;
}

function extOf(name) {
  const lower = String(name || "").toLowerCase();
  const dot = lower.lastIndexOf(".");
  return dot === -1 ? "" : lower.slice(dot);
}

function base64ToBytes(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store, max-age=0" }
  });
}

import { ENGINE_TOOLS } from "../_lib/engineTools.js";

async function forwardToEngine(job, env) {
  let response;
  try {
    response = await fetch(`${String(env.ENGINE_URL).replace(/\/+$/, "")}/convert`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-engine-token": env.ENGINE_TOKEN },
      body: JSON.stringify({ tool: job.tool, files: job.files, options: job.options || {} }),
      signal: AbortSignal.timeout(170000)
    });
  } catch {
    return json(503, { error: "The converter is starting up or unavailable. Please try again in a minute." });
  }
  let payload;
  try { payload = await response.json(); } catch { payload = {}; }
  if (!response.ok || !payload.dataBase64) {
    return json(response.status === 503 ? 503 : 422, { error: payload.error || "Conversion failed. Check that the input file opens normally." });
  }
  const ext = extOf(payload.outputName);
  const types = { ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation", ".zip": "application/zip", ".pdf": "application/pdf", ".txt": "text/plain;charset=utf-8" };
  return json(200, {
    downloadUrl: `data:${types[ext] || "application/octet-stream"};base64,${payload.dataBase64}`,
    savedFile: payload.outputName, outputName: payload.outputName, note: payload.note || ""
  });
}

export async function onRequestPost({ request, env }) {
  try {
    const job = await request.json();
    const tool = job?.tool;
    if (!tool) return json(422, { error: "Choose a supported conversion." });

    if (!SUPPORTED_TOOLS.has(tool) && env?.ENGINE_URL && env?.ENGINE_TOKEN && ENGINE_TOOLS.includes(tool)) {
      if (!Array.isArray(job.files) || !job.files.length || job.files.length > 20) {
        return json(422, { error: "Select between 1 and 20 files." });
      }
      return forwardToEngine(job, env);
    }

    if (!SUPPORTED_TOOLS.has(tool)) {
      return json(422, {
        error: `${tool} is not available on this deployment yet. This conversion needs a compute engine outside the browser/Workers runtime and is coming in a later update.`
      });
    }

    if (!Array.isArray(job.files) || !job.files.length || job.files.length > 20) {
      return json(422, { error: "Select between 1 and 20 files." });
    }
    if (job.files.length > 1 && !["Merge PDF", "Image to PDF"].includes(tool)) {
      return json(422, { error: "Select one file for this conversion." });
    }

    const allowedExt = EXPECTED_INPUT_EXT[tool];
    const files = job.files.map((f) => {
      const ext = extOf(f.name);
      if (!allowedExt.includes(ext)) {
        throw new Error(`${tool} requires ${allowedExt.join(",")} files.`);
      }
      const bytes = base64ToBytes(String(f.data || ""));
      if (!bytes.length) throw new Error("The selected file is empty.");
      return { name: f.name, bytes };
    });

    const options = job.options || {};
    let outputBytes;
    let note = "";

    switch (tool) {
      case "Merge PDF":
        outputBytes = await mergePdf(files);
        break;
      case "Watermark PDF":
        outputBytes = await watermarkPdf(files[0].bytes, options);
        break;
      case "Image to PDF":
        outputBytes = await imageToPdf(files);
        break;
      case "PDF to Text": {
        const text = await pdfToText(files[0].bytes);
        if (!text.trim()) {
          return json(422, { error: "No selectable text found. This PDF needs OCR." });
        }
        outputBytes = new TextEncoder().encode(text);
        note = "Columns are separated with tabs so the text pastes into Excel as real columns.";
        break;
      }
      default:
        return json(422, { error: "Unsupported conversion." });
    }

    const ext = OUTPUT_EXT[tool];
    const baseName = job.files[0].name.replace(/\.[^./\\]+$/, "");
    const outputName = safeOutputName(baseName + ext, ext);
    const dataUrl = `data:${CONTENT_TYPE[ext]};base64,${bytesToBase64(outputBytes)}`;

    // Stateless Function: instead of preview-server.mjs's in-memory staged
    // download + /api/download/:id (there's no shared, reliable place to
    // stash bytes between two separate Worker invocations here), the file is
    // handed back inline as a data: URL. app.js only ever does
    // `new URL(result.downloadUrl, location.origin)` and `fetch(downloadUrl)`
    // -- both work unchanged on a data: URL -- and its "Save to Downloads"
    // helper explicitly checks `pathname.startsWith('/api/download/')` before
    // trying the local-desktop-only save flow, so it no-ops gracefully here
    // and falls back to a normal browser download.
    return json(200, { downloadUrl: dataUrl, savedFile: outputName, outputName, note });
  } catch (error) {
    return json(422, { error: error?.message || "Conversion failed. Check that the input file opens normally." });
  }
}
