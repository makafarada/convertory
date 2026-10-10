import { createReadStream, existsSync, statSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { homedir, tmpdir } from "node:os";
import { basename, extname, join, normalize, resolve } from "node:path";
import { promisify } from "node:util";

const root = resolve(process.cwd(), "ms-store");
const projectRoot = process.cwd();
const port = Number(process.argv[2]) || 4755;
const execFile = promisify(execFileCallback);
const bundledPython = "C:\\Users\\emrsa\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe";
const localPython = join(projectRoot, "runtime", "python", "python.exe");
const python = existsSync(localPython) ? localPython : bundledPython;
const converterScript = join(projectRoot, "convert-pdf-to-docx.py");
const converterModules = join(projectRoot, "vendor", "pdf2docx");
const bundledPdfToText = join(projectRoot, "runtime", "poppler", "bin", "pdftotext.exe");
const gitPdfToText = "C:\\Program Files\\Git\\mingw64\\bin\\pdftotext.exe";
const pdfToText = existsSync(bundledPdfToText)
  ? bundledPdfToText
  : (existsSync(gitPdfToText) ? gitPdfToText : "pdftotext");
const maxPdfBytes = 25 * 1024 * 1024;
const localDownloadsFolder = join(homedir(), "Downloads", "Convertory");
const stagedDownloads = new Map();
const openssl = existsSync("C:\\Program Files\\Git\\usr\\bin\\openssl.exe")
  ? "C:\\Program Files\\Git\\usr\\bin\\openssl.exe" : "openssl";

async function unwrapPdf(file, folder) {
  if (file.subarray(0, 5).toString("ascii") === "%PDF-") return file;
  // CMS SignedData can contain a PDF even when the download is named .pdf.
  const signedDataOid = Buffer.from("06092a864886f70d010702", "hex");
  if (!file.subarray(0, 64).includes(signedDataOid)) {
    throw new Error("This file does not contain a readable PDF. Select the original PDF document.");
  }
  const signedPath = join(folder, "signed-document.der");
  const extractedPath = join(folder, "unwrapped.pdf");
  await writeFile(signedPath, file);
  try {
    // Verify content integrity while extracting; certificate trust is not asserted.
    await execFile(openssl, ["cms", "-verify", "-inform", "DER", "-in", signedPath,
      "-noverify", "-binary", "-out", extractedPath], { windowsHide: true, timeout: 30000 });
  } catch {
    throw new Error("The electronically signed document could not be extracted. Select its original PDF.");
  }
  const pdf = await readFile(extractedPath);
  if (pdf.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw new Error("The signed document does not contain a PDF.");
  }
  logConversion("signed-pdf-extracted", { inputBytes: file.length, pdfBytes: pdf.length });
  return pdf;
}
const types = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webmanifest": "application/manifest+json; charset=utf-8"
};

function sendJson(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store, max-age=0"
  });
  response.end(JSON.stringify(payload));
}

function safeDocxName(value) {
  const fallback = "converted.docx";
  const name = String(value || fallback).replace(/[\\/:*?"<>|]/g, "_").trim();
  if (!name) return fallback;
  return /\.(docx|xlsx|pptx|pdf|txt|zip)$/i.test(name) ? name : `${name}.docx`;
}

function sendDocx(response, output, fileName = "converted.docx") {
  const downloadName = safeDocxName(fileName);
  response.writeHead(200, {
    "Content-Type": ({'.docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document','.xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','.pptx':'application/vnd.openxmlformats-officedocument.presentationml.presentation','.pdf':'application/pdf','.txt':'text/plain; charset=utf-8','.zip':'application/zip'})[extname(downloadName).toLowerCase()] || 'application/octet-stream',
    "Content-Disposition": `attachment; filename="converted${extname(downloadName)}"; filename*=UTF-8''${encodeURIComponent(downloadName)}`,
    "Cache-Control": "no-store, max-age=0",
    "Content-Length": output.length
  });
  response.end(output);
}

function logConversion(event, details = {}) {
  console.log(`[convertory] ${event} ${JSON.stringify(details)}`);
}

function stageDownload(output, fileName) {
  const id = randomUUID();
  stagedDownloads.set(id, { output, fileName: safeDocxName(fileName), expiresAt: Date.now() + 10 * 60 * 1000 });
  for (const [key, staged] of stagedDownloads) {
    if (staged.expiresAt < Date.now()) stagedDownloads.delete(key);
  }
  logConversion("download-staged", { bytes: output.length });
  return `/api/download/${id}`;
}

function openInDefaultApp(filePath) {
  const child = spawn("explorer.exe", [filePath], { windowsHide: true, detached: true, stdio: "ignore" });
  child.on("error", () => {});
  child.unref();
}

async function saveOutputToDownloads(output, fileName) {
  await mkdir(localDownloadsFolder, { recursive: true });
  const cleanName = safeDocxName(fileName);
  const extension = extname(cleanName);
  const stem = cleanName.slice(0, -extension.length);
  let index = 0;
  let target = join(localDownloadsFolder, cleanName);
  while (existsSync(target)) {
    index += 1;
    target = join(localDownloadsFolder, `${stem} (${index})${extension}`);
  }
  await writeFile(target, output);
  return basename(target);
}

async function readRequestBody(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > maxPdfBytes) throw new Error("PDF is larger than 25 MB.");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function extractPdfText(request, response) {
  let folder;
  try {
    const file = await readRequestBody(request);
    folder = await mkdtemp(join(tmpdir(), "convertory-pdf-"));
    const inputPath = join(folder, "source.pdf");
    await writeFile(inputPath, await unwrapPdf(file, folder));
    const { stdout } = await execFile(pdfToText, ["-layout", "-enc", "UTF-8", inputPath, "-"], {
      encoding: "utf8",
      windowsHide: true,
      maxBuffer: 12 * 1024 * 1024
    });
    const text = stdout.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
    if (!text.trim()) {
      sendJson(response, 422, { error: "No selectable text was found in this PDF. Scanned PDFs need OCR." });
      return;
    }
    sendJson(response, 200, { text });
  } catch (error) {
    const message = error?.message?.includes("25 MB")
      ? error.message
      : "This PDF could not be read. Try a non-password-protected PDF.";
    sendJson(response, 422, { error: message });
  } finally {
    if (folder) await rm(folder, { recursive: true, force: true });
  }
}

async function convertPdfToDocx(request, response) {
  let folder;
  try {
    const file = await readRequestBody(request);
    if (!existsSync(python) || !existsSync(converterScript) || !existsSync(converterModules)) {
      throw new Error("The local DOCX engine is not installed.");
    }
    folder = await mkdtemp(join(tmpdir(), "convertory-docx-"));
    const inputPath = join(folder, "source.pdf");
    const outputPath = join(folder, "converted.docx");
    try {
      await writeFile(inputPath, await unwrapPdf(file, folder));
    } catch (error) {
      sendJson(response, 400, { error: error.message });
      return;
    }
    await execFile(python, [converterScript, inputPath, outputPath], {
      env: { ...process.env, PYTHONPATH: converterModules },
      windowsHide: true,
      maxBuffer: 8 * 1024 * 1024
    });
    const output = await readFile(outputPath);
    if (output.length < 1024) throw new Error("The local DOCX engine returned an empty file.");
    logConversion("docx-created", { inputBytes: file.length, outputBytes: output.length });
    const outputName = decodeURIComponent(request.headers["x-convertory-output-name"] || "converted.docx");
    const savedFile = await saveOutputToDownloads(output, outputName);
    logConversion("output-saved", { file: savedFile, bytes: output.length });
    if (request.headers["x-convertory-response"] === "download-url") {
      sendJson(response, 200, { downloadUrl: stageDownload(output, outputName), savedFile });
      return;
    }
    sendDocx(response, output, outputName);
  } catch (error) {
    logConversion("docx-failed", { message: error?.message || "Unknown conversion error" });
    const message = error?.message?.includes("not installed")
      ? error.message
      : "This PDF could not be converted to editable DOCX. Try a non-password-protected PDF.";
    sendJson(response, 422, { error: message });
  } finally {
    if (folder) await rm(folder, { recursive: true, force: true });
  }
}

const conversionKinds = {
  'PDF to Excel': ['.pdf','.xlsx'], 'PDF to PowerPoint': ['.pdf','.pptx'],
  'PDF to Text': ['.pdf','.txt'],
  'Image to PDF': ['.png,.jpg,.jpeg,.webp','.pdf'],
  'Image to Excel': ['.png,.jpg,.jpeg,.webp','.xlsx'],
  'Image to Text': ['.png,.jpg,.jpeg,.webp','.txt'],
  'Word to PDF': ['.docx,.doc,.rtf','.pdf'], 'Excel to PDF': ['.xlsx,.xls,.csv','.pdf'],
  'PowerPoint to PDF': ['.pptx,.ppt','.pdf'], 'Merge PDF': ['.pdf','.pdf'],
  'Compress PDF': ['.pdf','.pdf'], 'Watermark PDF': ['.pdf','.pdf'],
  'More Formats': ['.pdf','.zip']
};
async function convertOther(request,response) {
  let folder;
  try {
    const job = JSON.parse((await readRequestBody(request)).toString('utf8'));
    const kind = conversionKinds[job.tool];
    if (!kind) throw new Error('Choose a supported conversion.');
    if (!Array.isArray(job.files) || !job.files.length || job.files.length>20) throw new Error('Select between 1 and 20 files.');
    if (job.files.length>1 && !['Merge PDF','Image to PDF'].includes(job.tool)) throw new Error('Select one file for this conversion.');
    folder=await mkdtemp(join(tmpdir(),'convertory-job-'));
    const paths=[];
    for (const [index,file] of job.files.entries()) {
      const extension=extname(String(file.name)).toLowerCase();
      if (!kind[0].split(',').includes(extension)) throw new Error(`${job.tool} requires ${kind[0]} files.`);
      let data=Buffer.from(file.data || '', 'base64');
      if (!data.length) throw new Error('The selected file is empty.');
      if (extension==='.pdf') data=await unwrapPdf(data,folder);
      const path=join(folder,`input-${index}${extension}`);
      await writeFile(path,data); paths.push(path);
    }
    const extension=job.tool==='More Formats' && job.options?.format==='txt' ? '.txt' : kind[1];
    const outputName=safeDocxName(basename(String(job.files[0].name),extname(String(job.files[0].name)))+extension);
    const outputPath=join(folder,`output${extension}`);
    const manifest=join(folder,'job.json');
    await writeFile(manifest,JSON.stringify({tool:job.tool,paths,output:outputPath,options:job.options || {}}));
    let result;
    try {
      const {stdout}=await execFile(python,[join(projectRoot,'conversion-engine.py'),manifest],{
        env:{...process.env,PYTHONPATH:converterModules},windowsHide:true,timeout:180000,maxBuffer:8*1024*1024
      });
      result=JSON.parse(stdout.trim().split(/\r?\n/).at(-1));
    } catch (error) {
      let message='Conversion failed. Check that the input file opens normally.';
      try { message=JSON.parse(error.stdout.trim().split(/\r?\n/).at(-1)).error || message; } catch {}
      logConversion('conversion-engine-failed',{tool:job.tool,message:error.stderr || error.message});
      throw new Error(message);
    }
    const output=await readFile(outputPath);
    const savedFile=await saveOutputToDownloads(output,outputName);
    logConversion('conversion-complete',{tool:job.tool,bytes:output.length});
    sendJson(response,200,{downloadUrl:stageDownload(output,outputName),savedFile,outputName,note:result.note});
  } catch (error) {
    sendJson(response,422,{error:error.message});
  } finally {
    if(folder) await rm(folder,{recursive:true,force:true});
  }
}

// Real Convertory Pro billing only exists inside the Microsoft Store package
// (package identity is inherited by this process); anywhere else it is a dev run.
const storeBilling = /\\WindowsApps\\/i.test(process.execPath);
const storeLicenseScript = join(projectRoot, "store-license.ps1");

async function runStoreLicense(mode) {
  if (!storeBilling || !existsSync(storeLicenseScript)) return { ok: false, pro: false, error: "Store billing unavailable" };
  try {
    const { stdout } = await execFile("powershell.exe",
      ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", storeLicenseScript, mode],
      { windowsHide: true, timeout: mode === "purchase" ? 10 * 60 * 1000 : 30 * 1000 });
    const parsed = JSON.parse(stdout.trim().split(/\r?\n/).pop());
    return { ok: Boolean(parsed.ok), pro: Boolean(parsed.pro), error: parsed.error || null };
  } catch (error) {
    return { ok: false, pro: false, error: error.message };
  }
}

createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, `http://${request.headers.host}`).pathname);
  if (request.method === "GET" && pathname === "/api/capabilities") {
    sendJson(response, 200, { tools: "all", engine: "local", billing: storeBilling ? "store" : "dev" });
    return;
  }
  if (pathname === "/api/license" && (request.method === "GET" || request.method === "POST")) {
    // Only the app's own page may query/trigger billing: blocks cross-site requests and DNS rebinding.
    const hostOk = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i.test(request.headers.host || "");
    const origin = request.headers.origin;
    const originOk = !origin || new URL(origin).host === request.headers.host;
    const headerOk = request.method === "GET" || request.headers["x-convertory-request"] === "1";
    if (!hostOk || !originOk || !headerOk) {
      sendJson(response, 403, { ok: false, pro: false, error: "Forbidden" });
      return;
    }
    sendJson(response, 200, await runStoreLicense(request.method === "POST" ? "purchase" : "status"));
    return;
  }
  if (request.method==='POST' && pathname==='/api/convert') {
    await convertOther(request,response); return;
  }
  if (request.method === "POST" && pathname.startsWith("/api/save/")) {
    const staged = stagedDownloads.get(pathname.slice("/api/save/".length));
    if (!staged || staged.expiresAt < Date.now()) {
      sendJson(response, 404, { error: "This conversion has expired. Convert the file again." });
      return;
    }
    try {
      const savedFile = await saveOutputToDownloads(staged.output, staged.fileName);
      logConversion("manual-save", { file: savedFile, bytes: staged.output.length });
      sendJson(response, 200, { savedFile });
    } catch {
      sendJson(response, 500, { error: "Could not save the file to Downloads. Please retry." });
    }
    return;
  }
  if (request.method === "POST" && pathname === "/api/open") {
    try {
      const body = JSON.parse((await readRequestBody(request)).toString("utf8"));
      const fileName = basename(String(body.savedFile || ""));
      if (!fileName) throw new Error("No file to open.");
      const target = join(localDownloadsFolder, fileName);
      if (!existsSync(target)) throw new Error("The saved file could not be found. Save it again.");
      openInDefaultApp(target);
      sendJson(response, 200, { opened: true });
    } catch (error) {
      sendJson(response, 400, { error: error.message || "Could not open the file." });
    }
    return;
  }
  if (request.method === "GET" && pathname.startsWith("/api/download/")) {
    const id = pathname.slice("/api/download/".length);
    const staged = stagedDownloads.get(id);
    if (!staged || staged.expiresAt < Date.now()) {
      stagedDownloads.delete(id);
      sendJson(response, 404, { error: "This conversion link has expired. Convert the file again." });
      return;
    }
    logConversion("download-served", { bytes: staged.output.length });
    sendDocx(response, staged.output, staged.fileName);
    return;
  }
  if (request.method === "POST" && pathname === "/api/pdf-text") {
    await extractPdfText(request, response);
    return;
  }
  if (request.method === "POST" && pathname === "/api/pdf-to-docx") {
    await convertPdfToDocx(request, response);
    return;
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Method not allowed");
    return;
  }
  const target = normalize(join(root, pathname === "/" ? "index.html" : pathname));
  if (!target.startsWith(root) || !existsSync(target) || statSync(target).isDirectory()) {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
    return;
  }
  response.writeHead(200, {
    "Content-Type": types[extname(target).toLowerCase()] || "application/octet-stream",
    "Cache-Control": "no-store, max-age=0"
  });
  createReadStream(target).pipe(response);
}).listen(port, storeBilling ? "127.0.0.1" : "0.0.0.0", () => {
  console.log(`Convertory preview: http://127.0.0.1:${port}/`);
});
