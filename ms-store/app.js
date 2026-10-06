const state = {
  selectedSample: null,
  selectedTool: "PDF to Word",
  selectedFile: null,
  selectedFiles: [],
  pro: false,
  batch: [],
  history: [],
  cachePurged: false,
  lastDownloadUrl: null,
  converting: false
};

const samples = [
  { name: "Invoice PDF", detail: "Line items, tax, totals", tag: "Excel .xlsx", icon: "pdf", output: "invoice.xlsx", tool: "PDF to Excel" },
  { name: "Contract PDF", detail: "Clauses and headings", tag: "Word .rtf", icon: "pdf", output: "contract.rtf", tool: "PDF to Word" },
  { name: "Receipt Scan", detail: "OCR to searchable PDF", tag: "PDF + OCR", icon: "image", output: "receipt.pdf", tool: "Image to PDF" },
  { name: "Monthly Deck", detail: "Presentation pages", tag: "PPTX", icon: "powerpoint", output: "monthly-deck.pdf", tool: "PowerPoint to PDF" }
];

const allTools = [
  { name: "PDF to Word", detail: "Editable DOCX layout", from: "pdf", to: "word", output: "pdf-to-word.docx", free: true },
  { name: "PDF to Excel", detail: "Extract tables", from: "pdf", to: "excel", output: "tables.xlsx", free: false },
  { name: "PDF to Text", detail: "Extract plain text", from: "pdf", to: "text", output: "extracted.txt", free: true },
  { name: "PDF to PowerPoint", detail: "Create presentations", from: "pdf", to: "powerpoint", output: "slides.pptx", free: false },
  { name: "Image to PDF", detail: "JPG, PNG, WEBP → PDF", from: "image", to: "pdf", output: "images.pdf", free: false },
  { name: "Image to Excel", detail: "Extract text (OCR)", from: "image", to: "excel", output: "ocr-table.xlsx", free: false },
  { name: "Image to Text", detail: "OCR - Scan to text", from: "image", to: "text", output: "scan.txt", free: false },
  { name: "Word to PDF", detail: "DOCX → PDF", from: "word", to: "pdf", output: "document.pdf", free: false },
  { name: "Excel to PDF", detail: "XLSX → PDF", from: "excel", to: "pdf", output: "spreadsheet.pdf", free: true },
  { name: "PowerPoint to PDF", detail: "PPTX → PDF", from: "powerpoint", to: "pdf", output: "deck.pdf", free: false },
  { name: "Merge PDF", detail: "Combine files", from: "pdf", to: "merge", output: "merged.pdf", free: false },
  { name: "Compress PDF", detail: "Smaller file size", from: "pdf", to: "compress", output: "compressed.pdf", free: false },
  { name: "Watermark PDF", detail: "Add text or image", from: "pdf", to: "lock", output: "watermarked.pdf", free: false },
  { name: "More Formats", detail: "PDF to PNG or TXT", from: "more", to: "more", output: "converted-file.zip", free: false }
];

// Hosted deployments (web/PWA/Android/iOS) only run the tools the Cloudflare
// Function + client-side fallbacks can actually do. The Windows build serves
// this same file from a local server that reports `tools: "all"` at
// /api/capabilities, which restores the full list (see applyCapabilities()).
const HOSTED_TOOLS = new Set(["PDF to Word", "PDF to Text", "Merge PDF", "Watermark PDF", "Image to PDF"]);
const tools = allTools.filter((tool) => HOSTED_TOOLS.has(tool.name));
const allSamples = [...samples];
samples.splice(0, samples.length, ...allSamples.filter((sample) => !sample.tool || HOSTED_TOOLS.has(sample.tool)));
const toolAvailable = (name) => tools.some((tool) => tool.name === name);

async function applyCapabilities() {
  try {
    const response = await fetch("/api/capabilities", { cache: "no-store" });
    if (!response.ok || !(response.headers.get("content-type") || "").includes("json")) return;
    const caps = await response.json();
    const names = caps.tools === "all" ? null : new Set(Array.isArray(caps.tools) ? caps.tools : []);
    if (names && !names.size) return;
    const visible = (name) => !names || names.has(name);
    tools.splice(0, tools.length, ...allTools.filter((tool) => visible(tool.name)));
    samples.splice(0, samples.length, ...allSamples.filter((sample) => !sample.tool || visible(sample.tool)));
    renderTools();
    renderModalFiles();
  } catch (error) {
    /* hosted default stays */
  }
}

const $ = (selector) => document.querySelector(selector);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));

function iconGlyph(type) {
  const glyphs = {
    pdf: "PDF",
    excel: "X",
    powerpoint: "P",
    image: "IMG",
    text: "T",
    word: "W",
    merge: "＋",
    compress: "↧",
    lock: "▣",
    more: "•••"
  };
  return glyphs[type] ?? "▤";
}

function formatIcon(type) {
  return `<span class="format-icon icon-${type}">${iconGlyph(type)}</span>`;
}

function formatFlowIcon(from, to) {
  if (!to || from === to) return formatIcon(from);
  return `
    <span class="flow-icon flow-${from}-to-${to}" aria-hidden="true">
      <span class="source-format-icon icon-${from}">${iconGlyph(from)}</span>
      <span class="flow-corner-arrow">→</span>
      <span class="target-format-icon icon-${to}">${iconGlyph(to)}</span>
    </span>
  `;
}

function isToolLocked(tool) {
  return !state.pro && !tool.free;
}

function renderTools() {
  $("#tools").innerHTML = tools.map((tool) => {
    const locked = isToolLocked(tool);
    return `
      <button class="format-card ${state.selectedTool === tool.name ? "active" : ""} ${locked ? "locked" : ""}" data-tool="${tool.name}" aria-label="${locked ? `${tool.name} Pro` : tool.name}">
        ${formatFlowIcon(tool.from, tool.to)}
        <span class="format-copy">
          <strong>${tool.name}</strong>
        </span>
        <span class="${locked ? "pro-lock" : "chevron"}">${locked ? "PRO" : "›"}</span>
      </button>
    `;
  }).join("");
  const special=['Watermark PDF','More Formats','Merge PDF','PDF to PowerPoint','Image to PDF'].includes(state.selectedTool);
  $('#conversionOptions')?.classList.toggle('hidden',!special);
  $('#watermarkOption')?.classList.toggle('hidden',state.selectedTool!=='Watermark PDF');
  $('#formatOption')?.classList.toggle('hidden',state.selectedTool!=='More Formats');
  if ($('#conversionHint')) $('#conversionHint').textContent = ({'Merge PDF':'Choose two or more PDFs. Files are merged in the selected order.','Image to PDF':'Choose one or more images. Each image becomes a PDF page.','PDF to PowerPoint':'PDF pages become slide images, preserving appearance. Text inside these images is not editable.'})[state.selectedTool] || '';
}

function renderModalFiles() {
  $("#modalFiles").innerHTML = samples.map((sample) => `
    <button class="modal-file" data-modal-file="${sample.name}">
      ${formatIcon(sample.icon)}
      <span>
        <strong>${sample.name}</strong>
        <small>${sample.detail} • ${sample.tag}</small>
      </span>
    </button>
  `).join("");
}

function selectSample(sample, { selectTool = true } = {}) {
  state.selectedSample = sample;
  if (!sample.file) state.selectedFile = null;
  if (selectTool && sample.tool) state.selectedTool = sample.tool;
  $("#selectedName").textContent = sample.name;
  $("#convertNowButton")?.classList.toggle("hidden", !sample.file);
  renderTools();
}

function formatBytes(bytes) {
  if (!bytes) return "Ready for local conversion";
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function recommendedToolForExtension(extension) {
  const pick = (name) => (toolAvailable(name) ? name : null);
  if (extension.includes("XLS")) return pick("Excel to PDF") ?? "PDF to Word";
  if (extension.includes("DOC")) return pick("Word to PDF") ?? "PDF to Word";
  if (extension.includes("PPT")) return pick("PowerPoint to PDF") ?? "PDF to Word";
  if (["JPG", "JPEG", "PNG", "WEBP"].includes(extension)) return "Image to PDF";
  if (extension.includes("PDF")) return "PDF to Word";
  return pick("More Formats") ?? "PDF to Word";
}

function selectRealFile(file, files = [file]) {
  const extension = file.name.includes(".") ? file.name.split(".").pop().toUpperCase() : "FILE";
  state.selectedFile = file;
  state.selectedFiles = files;
  const compatible = ({'PDF':['PDF to Word','PDF to Excel','PDF to PowerPoint','PDF to Text','Merge PDF','Compress PDF','Watermark PDF','More Formats'],'PNG':['Image to PDF','Image to Text','Image to Excel'],'JPG':['Image to PDF','Image to Text','Image to Excel'],'JPEG':['Image to PDF','Image to Text','Image to Excel'],'WEBP':['Image to PDF','Image to Text','Image to Excel']})[extension] || [];
  if (!compatible.includes(state.selectedTool)) state.selectedTool = recommendedToolForExtension(extension);
  if (files.length>1) state.selectedTool=extension==='PDF'?'Merge PDF':'Image to PDF';
  selectSample({
    name: file.name,
    detail: `${extension} • ${formatBytes(file.size)}`,
    tag: extension,
    file,
    files,
    icon: extension.includes("PDF") ? "pdf" : extension.includes("XLS") ? "excel" : extension.includes("DOC") ? "word" : extension.includes("PPT") ? "powerpoint" : extension.includes("TXT") ? "text" : "image",
    output: file.name.replace(/\.[^.]+$/, "") || "converted-file",
    tool: state.selectedTool
  });
  if (files.length>1) $('#selectedName').textContent=`${files.length} files selected`;
  $("#result").classList.add("hidden");
  renderTools();
}

function escapePdfText(value) {
  return String(value).replace(/[\\()]/g, "\\$&");
}

function sanitizePdfLine(value) {
  return String(value).replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, " ").slice(0, 96);
}

function getOutputName(source, tool) {
  const fallback = tool.output || "converted-file.txt";
  const extension = tool.name==='More Formats' && $('#extraFormat')?.value==='txt' ? '.txt' : fallback.includes(".") ? fallback.slice(fallback.lastIndexOf(".")) : ".txt";
  const base = (source?.name || "converted-file").replace(/\.[^.]+$/, "") || "converted-file";
  return `${base}${extension}`;
}

function escapeRtfText(value) {
  return String(value)
    .replace(/\\/g, "\\\\")
    .replace(/\{/g, "\\{")
    .replace(/\}/g, "\\}")
    .replace(/[\u0080-\uffff]/g, (char) => `\\u${char.charCodeAt(0)}?`);
}

function buildRtfContent(lines) {
  const landscape = lines.some((line) => line.length > 110);
  const page = landscape
    ? "\\paperw15840\\paperh12240\\landscape\\margl720\\margr720\\margt720\\margb720"
    : "\\paperw12240\\paperh15840\\margl1080\\margr1080\\margt1080\\margb1080";
  const body = lines.map((line) => {
    if (line === "\f") return "\\page";
    const safe = escapeRtfText(line || " ");
    return `\\pard\\sa0\\sl180\\slmult0 ${safe}\\par`;
  }).join("\n");
  return `{\\rtf1\\ansi\\ansicpg1254\\deff0{\\fonttbl{\\f0 Consolas;}}${page}\\f0\\fs18\n${body}\n}`;
}

let pdfRendererPromise;

async function loadPdfRenderer() {
  if (!pdfRendererPromise) {
    pdfRendererPromise = import("./vendor/pdf.min.mjs").then((renderer) => {
      renderer.GlobalWorkerOptions.workerSrc = "./vendor/pdf.worker.min.mjs";
      return renderer;
    });
  }
  return pdfRendererPromise;
}

function toTwips(points) {
  return Math.max(0, Math.round(points * 20));
}

function groupPdfTextIntoLines(items) {
  const source = items.filter((item) => item.str && item.str.trim()).map((item) => ({
    ...item,
    x: item.transform[4],
    y: item.transform[5],
    fontPoints: Math.max(7, Math.min(24, Math.hypot(item.transform[1], item.transform[3])))
  })).sort((left, right) => right.y - left.y || left.x - right.x);
  const lines = [];
  for (const item of source) {
    const line = lines.find((candidate) => Math.abs(candidate.y - item.y) <= Math.max(1.25, item.fontPoints * 0.18));
    if (line) line.items.push(item);
    else lines.push({ y: item.y, items: [item] });
  }
  return lines.map((line) => {
    const itemsOnLine = line.items.sort((left, right) => left.x - right.x);
    const fontPoints = Math.max(...itemsOnLine.map((item) => item.fontPoints));
    let cursor = itemsOnLine[0].x;
    let text = "";
    for (const item of itemsOnLine) {
      const gap = item.x - cursor;
      if (text && gap > fontPoints * 0.15) text += " ".repeat(Math.max(1, Math.min(80, Math.round(gap / (fontPoints * 0.58)))));
      text += item.str;
      cursor = Math.max(cursor, item.x + Math.abs(item.width || 0));
    }
    return { x: itemsOnLine[0].x, y: line.y, fontPoints, text };
  });
}

function buildPositionedRtfLine(line, pageWidth, pageHeight) {
  const topPoints = Math.max(0, pageHeight - line.y - line.fontPoints);
  return "{\\pard\\plain\\phpg\\pvpg\\posx" + toTwips(line.x) + "\\posy" + toTwips(topPoints) + "\\absw" + toTwips(pageWidth - line.x) + "\\absh" + toTwips(line.fontPoints * 1.7) + "\\dxfrtext0\\dfrmtxtx0\\dfrmtxty0\\f0\\fs" + Math.round(line.fontPoints * 2) + " " + escapeRtfText(line.text) + "\\par}";
}

async function buildEditableLayoutRtf(file) {
  const pdfjs = await loadPdfRenderer();
  const pdf = await pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
  const pages = [];
  try {
    for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
      const page = await pdf.getPage(pageNumber);
      const viewport = page.getViewport({ scale: 1 });
      const textContent = await page.getTextContent({ disableNormalization: false });
      const lines = groupPdfTextIntoLines(textContent.items);
      const runs = lines.map((line) => buildPositionedRtfLine(line, viewport.width, viewport.height));
      if (!runs.length) throw new Error("No selectable text was found in this PDF. Scanned PDFs need OCR.");
      pages.push("\\paperw" + toTwips(viewport.width) + "\\paperh" + toTwips(viewport.height) + "\\margl0\\margr0\\margt0\\margb0\n" + runs.join("\n"));
    }
  } finally {
    await pdf.destroy();
  }
  return "{\\rtf1\\ansi\\ansicpg1254\\deff0{\\fonttbl{\\f0 Consolas;}}\n" + pages.join("{\\pard\\page\\par}\n") + "\n}";
}

function buildPdfContent(lines) {
  const safeLines = lines.map((line) => escapePdfText(sanitizePdfLine(line)));
  const textOps = safeLines.slice(0, 28).map((line, index) => `1 0 0 1 54 ${760 - index * 22} Tm (${line}) Tj`).join("\n");
  const stream = `BT\n/F1 12 Tf\n${textOps}\nET`;
  const objects = [
    "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
    "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
    "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n",
    "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
    `5 0 obj\n<< /Length ${stream.length} >>\nstream\n${stream}\nendstream\nendobj\n`
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  for (const object of objects) { offsets.push(pdf.length); pdf += object; }
  const xrefOffset = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (let index = 1; index <= objects.length; index += 1) pdf += `${String(offsets[index]).padStart(10, "0")} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return pdf;
}

function decodeXml(value) {
  return value.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'");
}

function bytesToString(bytes) { return new TextDecoder("utf-8").decode(bytes); }

function findEndOfCentralDirectory(view) {
  for (let offset = view.byteLength - 22; offset >= Math.max(0, view.byteLength - 65558); offset -= 1) {
    if (view.getUint32(offset, true) === 0x06054b50) return offset;
  }
  return -1;
}

function readZipEntries(buffer) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const entries = new Map();
  const eocd = findEndOfCentralDirectory(view);
  if (eocd >= 0) {
    const totalEntries = view.getUint16(eocd + 10, true);
    let directoryOffset = view.getUint32(eocd + 16, true);
    for (let index = 0; index < totalEntries && directoryOffset + 46 < bytes.length; index += 1) {
      if (view.getUint32(directoryOffset, true) !== 0x02014b50) break;
      const method = view.getUint16(directoryOffset + 10, true);
      const compressedSize = view.getUint32(directoryOffset + 20, true);
      const fileNameLength = view.getUint16(directoryOffset + 28, true);
      const extraLength = view.getUint16(directoryOffset + 30, true);
      const commentLength = view.getUint16(directoryOffset + 32, true);
      const localHeaderOffset = view.getUint32(directoryOffset + 42, true);
      const nameStart = directoryOffset + 46;
      const name = bytesToString(bytes.slice(nameStart, nameStart + fileNameLength));
      const localNameLength = view.getUint16(localHeaderOffset + 26, true);
      const localExtraLength = view.getUint16(localHeaderOffset + 28, true);
      const dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength;
      entries.set(name, { method, data: bytes.slice(dataStart, dataStart + compressedSize) });
      directoryOffset = nameStart + fileNameLength + extraLength + commentLength;
    }
    return entries;
  }

  let offset = 0;
  while (offset + 30 < bytes.length) {
    if (view.getUint32(offset, true) !== 0x04034b50) break;
    const method = view.getUint16(offset + 8, true);
    const compressedSize = view.getUint32(offset + 18, true);
    const fileNameLength = view.getUint16(offset + 26, true);
    const extraLength = view.getUint16(offset + 28, true);
    const nameStart = offset + 30;
    const dataStart = nameStart + fileNameLength + extraLength;
    const name = bytesToString(bytes.slice(nameStart, nameStart + fileNameLength));
    entries.set(name, { method, data: bytes.slice(dataStart, dataStart + compressedSize) });
    offset = dataStart + compressedSize;
  }
  return entries;
}

async function inflateZipEntry(entry) {
  if (!entry) return "";
  if (entry.method === 0) return bytesToString(entry.data);
  if (entry.method !== 8 || typeof DecompressionStream === "undefined") return "";
  const stream = new Blob([entry.data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const buffer = await new Response(stream).arrayBuffer();
  return bytesToString(new Uint8Array(buffer));
}

function parseSharedStrings(xml) {
  const strings = [];
  for (const match of xml.matchAll(/<si[\s\S]*?<\/si>/g)) {
    strings.push([...match[0].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((part) => decodeXml(part[1])).join(""));
  }
  return strings;
}

function parseSheetRows(xml, sharedStrings) {
  const rows = [];
  for (const rowMatch of xml.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells = [];
    for (const cellMatch of rowMatch[1].matchAll(/<c([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = cellMatch[1];
      const body = cellMatch[2];
      const valueMatch = body.match(/<v[^>]*>([\s\S]*?)<\/v>/);
      const inlineMatch = body.match(/<t[^>]*>([\s\S]*?)<\/t>/);
      let value = inlineMatch ? decodeXml(inlineMatch[1]) : valueMatch ? decodeXml(valueMatch[1]) : "";
      if (/t="s"/.test(attrs)) value = sharedStrings[Number(value)] ?? value;
      cells.push(value);
    }
    if (cells.some(Boolean)) rows.push(cells);
  }
  return rows;
}

async function extractXlsxRows(file) {
  const entries = readZipEntries(await file.arrayBuffer());
  const sharedXml = await inflateZipEntry(entries.get("xl/sharedStrings.xml"));
  const sheetName = [...entries.keys()].find((name) => /^xl\/worksheets\/sheet\d+\.xml$/.test(name));
  const sheetXml = await inflateZipEntry(entries.get(sheetName));
  if (!sheetXml) return [];
  return parseSheetRows(sheetXml, parseSharedStrings(sharedXml));
}

function decodePdfLiteral(value) {
  return value
    .replace(/\\([nrtbf])/g, (_, character) => ({ n: "\n", r: "\r", t: "\t", b: "\b", f: "\f" }[character]))
    .replace(/\\([()\\])/g, "$1")
    .replace(/\\([0-7]{1,3})/g, (_, octal) => String.fromCharCode(parseInt(octal, 8)));
}

function pdfTextFromStream(stream) {
  const lines = [];
  const textOperator = /\((?:\\.|[^\\)])*\)\s*(?:Tj|'|")|\[(.*?)\]\s*TJ/gms;
  for (const block of stream.matchAll(/\bBT\b([\s\S]*?)\bET\b/g)) {
    for (const match of block[1].matchAll(textOperator)) {
      const token = match[0];
      const literals = [...token.matchAll(/\((?:\\.|[^\\)])*\)/g)].map((literal) => decodePdfLiteral(literal[0].slice(1, -1)));
      const text = literals.join("").replace(/\s+/g, " ").trim();
      if (text) lines.push(text);
    }
  }
  return lines;
}

async function inflatePdfStream(bytes) {
  if (typeof DecompressionStream === "undefined") return "";
  try {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
    return new TextDecoder("latin1").decode(new Uint8Array(await new Response(stream).arrayBuffer()));
  } catch {
    return "";
  }
}

async function extractPdfTextLines(file) {
  if (location.protocol.startsWith("http")) {
    const response = await fetch("/api/pdf-text", {
      method: "POST",
      headers: { "Content-Type": "application/pdf" },
      body: await file.arrayBuffer()
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || "This PDF could not be read.");
    return payload.text.replace(/\r\n/g, "\n").split("\n").flatMap((line) => {
      const parts = line.split("\f");
      return parts.flatMap((part, index) => index === 0 ? [part] : ["\f", part]);
    });
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const header = new TextDecoder("ascii").decode(bytes.slice(0, 5));
  if (header !== "%PDF-") throw new Error("Select a PDF file for PDF to Word. Images need OCR.");
  const documentText = new TextDecoder("latin1").decode(bytes);
  const lines = [];
  const streamPattern = /<<(.*?)>>\s*stream\r?\n/gms;
  let match;
  while ((match = streamPattern.exec(documentText))) {
    const streamStart = streamPattern.lastIndex;
    const streamEnd = documentText.indexOf("endstream", streamStart);
    if (streamEnd < 0) break;
    let rawEnd = streamEnd;
    if (bytes[rawEnd - 2] === 13 && bytes[rawEnd - 1] === 10) rawEnd -= 2;
    else if (bytes[rawEnd - 1] === 10 || bytes[rawEnd - 1] === 13) rawEnd -= 1;
    const rawBytes = bytes.slice(streamStart, rawEnd);
    const stream = /\/FlateDecode/.test(match[1])
      ? await inflatePdfStream(rawBytes)
      : new TextDecoder("latin1").decode(rawBytes);
    lines.push(...pdfTextFromStream(stream));
    streamPattern.lastIndex = streamEnd + "endstream".length;
  }
  const ignored = /^(Convertory Conversion Result|Source:|Conversion:|Output:|Preview conversion completed locally\.|For full native fidelity)/i;
  return [...new Set(lines.filter((line) => !ignored.test(line)))];
}

async function createPdfLinesForConversion(output, toolName, source) {
  const file = source?.file ?? state.selectedFile;
  const extension = (file?.name?.split(".").pop() || "").toLowerCase();
  if (toolName === "Excel to PDF" && file) {
    if (extension === "csv" || extension === "txt") {
      const text = await file.text();
      const rows = text.split(/\r?\n/).filter(Boolean).slice(0, 22);
      if (rows.length) return rows;
    }
    if (extension === "xlsx") {
      const rows = await extractXlsxRows(file);
      if (rows.length) return rows.slice(0, 22).map((row) => row.join(" | "));
    }
    throw new Error("No readable cells were found in the first worksheet.");
  }
  throw new Error(toolName + " is not available in this preview yet.");
}

function xmlEscape(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function makeCrcTable() {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    table[index] = value >>> 0;
  }
  return table;
}

const crcTable = makeCrcTable();

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function writeUint16(target, offset, value) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
}

function writeUint32(target, offset, value) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
  target[offset + 2] = (value >>> 16) & 0xff;
  target[offset + 3] = (value >>> 24) & 0xff;
}

function stringBytes(value) {
  return new TextEncoder().encode(value);
}

function concatBytes(parts) {
  const size = parts.reduce((sum, part) => sum + part.length, 0);
  const output = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function getZipDosTimeParts() {
  const date = new Date(2026, 0, 1, 12, 0, 0);
  return {
    time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
    date: ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate()
  };
}

function buildZip(entries) {
  const localParts = [];
  const centralParts = [];
  const dos = getZipDosTimeParts();
  let offset = 0;
  for (const entry of entries) {
    const nameBytes = stringBytes(entry.name);
    const dataBytes = stringBytes(entry.content);
    const crc = crc32(dataBytes);
    const local = new Uint8Array(30 + nameBytes.length + dataBytes.length);
    writeUint32(local, 0, 0x04034b50);
    writeUint16(local, 4, 20);
    writeUint16(local, 6, 0x0800);
    writeUint16(local, 8, 0);
    writeUint16(local, 10, dos.time);
    writeUint16(local, 12, dos.date);
    writeUint32(local, 14, crc);
    writeUint32(local, 18, dataBytes.length);
    writeUint32(local, 22, dataBytes.length);
    writeUint16(local, 26, nameBytes.length);
    writeUint16(local, 28, 0);
    local.set(nameBytes, 30);
    local.set(dataBytes, 30 + nameBytes.length);
    localParts.push(local);
    const central = new Uint8Array(46 + nameBytes.length);
    writeUint32(central, 0, 0x02014b50);
    writeUint16(central, 4, 20);
    writeUint16(central, 6, 20);
    writeUint16(central, 8, 0x0800);
    writeUint16(central, 10, 0);
    writeUint16(central, 12, dos.time);
    writeUint16(central, 14, dos.date);
    writeUint32(central, 16, crc);
    writeUint32(central, 20, dataBytes.length);
    writeUint32(central, 24, dataBytes.length);
    writeUint16(central, 28, nameBytes.length);
    writeUint16(central, 30, 0);
    writeUint16(central, 32, 0);
    writeUint16(central, 34, 0);
    writeUint16(central, 36, 0);
    writeUint32(central, 38, 0);
    writeUint32(central, 42, offset);
    central.set(nameBytes, 46);
    centralParts.push(central);
    offset += local.length;
  }
  const centralDirectory = concatBytes(centralParts);
  const end = new Uint8Array(22);
  writeUint32(end, 0, 0x06054b50);
  writeUint16(end, 8, entries.length);
  writeUint16(end, 10, entries.length);
  writeUint32(end, 12, centralDirectory.length);
  writeUint32(end, 16, offset);
  return concatBytes([...localParts, centralDirectory, end]);
}

async function createDocxLinesForConversion(output, toolName, source) {
  const file = source?.file ?? state.selectedFile;
  if (toolName === "PDF to Word" && file) {
    const lines = await extractPdfTextLines(file);
    if (lines.length) return lines;
    throw new Error("No selectable text was found in this PDF. Scanned PDFs need OCR.");
  }
  const lines = ["Convertory Conversion Result", `Source: ${source?.name ?? source}`, `Conversion: ${toolName}`, `Output: ${output}`, ""];
  if (file && file.type?.startsWith("text/")) {
    const text = await file.text();
    return lines.concat(text.split(/\r?\n/).filter(Boolean).slice(0, 40));
  }
  return lines.concat("No source text is available for this export.");
}

function buildDocxContent(lines) {
  const paragraphs = lines.map((line, index) => {
    if (line === "\f") return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
    const empty = !line || !line.trim();
    const text = empty ? " " : line;
    const spacing = empty ? '<w:spacing w:after="80" w:line="160" w:lineRule="exact"/>' : '<w:spacing w:after="0" w:line="240" w:lineRule="exact"/>';
    return `<w:p><w:pPr>${spacing}</w:pPr><w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr><w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r></w:p>`;
  }).join("");
  const contentTypesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/><Override PartName="/word/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>`;
  const rootRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>`;
  const documentRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/></Relationships>`;
  const documentXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" mc:Ignorable="w14 w15 wp14"><w:body>${paragraphs}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>`;
  const stylesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="exact"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>`;
  const settingsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" mc:Ignorable="w14"><w:zoom w:percent="100"/><w:defaultTabStop w:val="720"/><w:compat/><w:themeFontLang w:val="en-US"/></w:settings>`;
  const fontTableXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:font w:name="Consolas"><w:family w:val="modern"/><w:pitch w:val="fixed"/></w:font></w:fonts>`;
  const themeXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Convertory"><a:themeElements><a:clrScheme name="Convertory"><a:dk1><a:srgbClr val="111827"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F2937"/></a:dk2><a:lt2><a:srgbClr val="F8FAFC"/></a:lt2><a:accent1><a:srgbClr val="0EA5E9"/></a:accent1><a:accent2><a:srgbClr val="FACC15"/></a:accent2><a:accent3><a:srgbClr val="22C55E"/></a:accent3><a:accent4><a:srgbClr val="8B5CF6"/></a:accent4><a:accent5><a:srgbClr val="EF4444"/></a:accent5><a:accent6><a:srgbClr val="14B8A6"/></a:accent6><a:hlink><a:srgbClr val="2563EB"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink></a:clrScheme><a:fontScheme name="Convertory"><a:majorFont><a:latin typeface="Aptos"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme><a:fmtScheme name="Convertory"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle/></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>`;
  const coreXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>Convertory Export</dc:title><dc:creator>Convertory</dc:creator><cp:lastModifiedBy>Convertory</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">2026-01-01T12:00:00Z</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">2026-01-01T12:00:00Z</dcterms:modified></cp:coreProperties>`;
  const appXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Convertory</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop><Company>Convertory</Company><LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged><AppVersion>1.0</AppVersion></Properties>`;
  return buildZip([
    { name: "[Content_Types].xml", content: contentTypesXml },
    { name: "_rels/.rels", content: rootRelsXml },
    { name: "docProps/core.xml", content: coreXml },
    { name: "docProps/app.xml", content: appXml },
    { name: "word/document.xml", content: documentXml },
    { name: "word/styles.xml", content: stylesXml },
    { name: "word/settings.xml", content: settingsXml },
    { name: "word/fontTable.xml", content: fontTableXml },
    { name: "word/theme/theme1.xml", content: themeXml },
    { name: "word/_rels/document.xml.rels", content: documentRelsXml }
  ]);
}
async function convertPdfToDocxViaTextApi(file, output) {
  const data = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.onerror = () => reject(new Error("Could not read the selected file."));
    reader.readAsDataURL(file);
  });
  const response = await fetch("/api/convert", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tool: "PDF to Text", files: [{ name: file.name, data }], options: {} }),
    signal: AbortSignal.timeout(120000)
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "This PDF could not be converted to editable DOCX.");
  if (!result.downloadUrl) throw new Error("The converter returned no output.");
  const text = await (await fetch(result.downloadUrl)).text();
  const lines = text.replace(/\r\n/g, "\n").split("\n").map((line) => line.replace(/\t/g, "    "));
  const blob = new Blob([buildDocxContent(lines)], { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" });
  state.lastSavedFile = output;
  state.lastPreviewText = text;
  state.lastConversionNote = "Text-only Word export: layout, images and tables are not preserved on this version.";
  return URL.createObjectURL(blob);
}

async function createConvertedFile(output, toolName, source) {
  state.lastConversionNote = '';
  state.lastPreviewText = '';
  if (toolName === "PDF to Word") {
    const file = source?.file ?? state.selectedFile;
    if (!file) throw new Error("Choose a PDF file before converting.");
    if (!location.protocol.startsWith("http")) throw new Error("Start the local Convertory preview before converting to DOCX.");
    const response = await fetch("/api/pdf-to-docx", {
      method: "POST",
      headers: {
        "Content-Type": "application/pdf",
        "X-Convertory-Response": "download-url",
        "X-Convertory-Output-Name": encodeURIComponent(output)
      },
      body: await file.arrayBuffer(),
      signal: AbortSignal.timeout(120000)
    });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      // A real engine error carries a message; a bare/non-JSON failure means this
      // deployment has no local DOCX engine, so use the hosted text-only path.
      if (!payload.error) return await convertPdfToDocxViaTextApi(file, output);
      throw new Error(payload.error);
    }
    const payload = await response.json().catch(() => ({}));
    if (!payload.downloadUrl) throw new Error("The local DOCX engine did not return a download link.");
    state.lastSavedFile = payload.savedFile || output;
    const downloadResponse = await fetch(new URL(payload.downloadUrl, window.location.origin), { signal: AbortSignal.timeout(30000) });
    if (!downloadResponse.ok) throw new Error("The converted file could not be downloaded. Please retry.");
    const blob = await downloadResponse.blob();
    const signature = new Uint8Array(await blob.slice(0, 4).arrayBuffer());
    if (signature[0] !== 0x50 || signature[1] !== 0x4b || signature[2] !== 3 || signature[3] !== 4) {
      throw new Error("The converter returned an invalid DOCX file.");
    }
    return new URL(payload.downloadUrl, window.location.origin).toString();
  }
  const files = source.files || [source.file || state.selectedFile];
  if (!files.length || !files[0]) throw new Error('Choose a file first.');
  const encoded=[];
  for (const file of files) {
    const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(',')[1]);reader.onerror=()=>reject(new Error('Could not read the selected file.'));reader.readAsDataURL(file);});
    encoded.push({name:file.name,data});
  }
  const response=await fetch('/api/convert',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({tool:toolName,files:encoded,options:{watermark:$('#watermarkText')?.value,format:$('#extraFormat')?.value}}),signal:AbortSignal.timeout(200000)});
  const rawBody=await response.text();
  let result;
  try {
    result=rawBody?JSON.parse(rawBody):{};
  } catch (parseError) {
    console.error('[Convertory] /api/convert returned a non-JSON response', {status:response.status,url:response.url,bodyPreview:rawBody.slice(0,300)});
    throw new Error(`Conversion server error (HTTP ${response.status}). This URL likely has no working conversion backend.`);
  }
  if(!response.ok) throw new Error(result.error || 'Conversion failed.');
  if(!result.downloadUrl) throw new Error('The converter returned no output.');
  state.lastSavedFile=result.savedFile;
  state.lastConversionNote=result.note || '';
  if (result.downloadUrl.startsWith('data:')) {
    // Chrome/TWA handle blob: downloads far more reliably than data: URLs.
    const blob = await (await fetch(result.downloadUrl)).blob();
    return URL.createObjectURL(blob);
  }
  return new URL(result.downloadUrl,location.origin).toString();
}

async function downloadConvertedFile(output, toolName, source) {
  const url = await createConvertedFile(output, toolName, source);
  state.lastDownloadUrl = url;
  state.lastOutputName = output;
  return url;
}

async function openSavedFile(fileName) {
  const response = await fetch("/api/open", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ savedFile: fileName }),
    signal: AbortSignal.timeout(10000)
  });
  if (response.status === 404 || response.status === 405) {
    // Hosted/mobile deployment has no desktop "open" endpoint: hand the file to the browser instead.
    if (!state.lastDownloadUrl) throw new Error("Could not open the file.");
    triggerDownload(state.lastDownloadUrl, state.lastOutputName || fileName);
    return;
  }
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "Could not open the file.");
}

function triggerDownload(downloadUrl, output) {
  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = output;
  link.rel = "noopener";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  window.setTimeout(() => link.remove(), 0);
}

async function buildPreviewMarkup(downloadUrl, output) {
  const extension = output.slice(output.lastIndexOf(".")).toLowerCase();
  try {
    if (extension === ".txt") {
      const response = await fetch(downloadUrl, { signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error("Could not load the preview.");
      const text = await response.text();
      const truncated = text.length > 4000;
      return `<div class="preview-box preview-text"><pre>${escapeHtml(truncated ? text.slice(0, 4000) : text)}${truncated ? "\n…" : ""}</pre></div>`;
    }
    if (extension === ".docx" && state.lastPreviewText) {
      const text = state.lastPreviewText;
      const truncated = text.length > 4000;
      return `<div class="preview-box preview-text"><pre>${escapeHtml(truncated ? text.slice(0, 4000) : text)}${truncated ? "\n…" : ""}</pre></div>`;
    }
    if (extension === ".pdf") {
      const response = await fetch(downloadUrl, { signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error("Could not load the preview.");
      const bytes = new Uint8Array(await response.arrayBuffer());
      const pdfjs = await loadPdfRenderer();
      const pdf = await pdfjs.getDocument({ data: bytes }).promise;
      const page = await pdf.getPage(1);
      const baseViewport = page.getViewport({ scale: 1 });
      const scale = Math.min(320 / baseViewport.width, 1.5);
      const viewport = page.getViewport({ scale });
      const canvas = document.createElement("canvas");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise;
      const pageNote = pdf.numPages > 1 ? `<span>Page 1 of ${pdf.numPages}</span>` : "";
      return `<div class="preview-box preview-pdf"><img src="${canvas.toDataURL("image/png")}" alt="Preview of ${escapeHtml(output)}" />${pageNote}</div>`;
    }
  } catch (error) {
    return `<div class="preview-box preview-unavailable">Preview couldn't be generated (${escapeHtml(error.message || "unknown error")}). Use Download to view the file.</div>`;
  }
  return `<div class="preview-box preview-unavailable">Preview isn't available for this file type. Use Download to view it.</div>`;
}

const isInlineResult = (url) => /^(blob|data):/.test(url || "");

// A web page cannot launch a downloaded file, so the converted text is shown in a full-screen reader instead.
function openViewer(name, url, text) {
  document.querySelector("#fileViewer")?.remove();
  const viewer = document.createElement("div");
  viewer.id = "fileViewer";
  viewer.innerHTML = `<div class="file-viewer-bar"><strong></strong><button type="button" class="file-viewer-close">Close</button></div><pre></pre><div class="file-viewer-actions"><button type="button" class="preview-download-button file-viewer-download">Download</button><button type="button" class="file-viewer-share">Share</button></div>`;
  viewer.querySelector("strong").textContent = name;
  viewer.querySelector("pre").textContent = text;
  viewer.querySelector(".file-viewer-close").addEventListener("click", () => viewer.remove());
  viewer.querySelector(".file-viewer-download").addEventListener("click", () => triggerDownload(url, name));
  viewer.querySelector(".file-viewer-share").addEventListener("click", async () => {
    try {
      if (navigator.share) await navigator.share({ title: name, text });
      else await navigator.clipboard.writeText(text);
    } catch (error) { /* cancelled */ }
  });
  document.body.appendChild(viewer);
}

async function runConversion() {
  if (state.converting) return;
  const selected = state.selectedSample;
  if (!selected?.file || !state.selectedFile) {
    $("#result").classList.remove("hidden");
    $("#result").innerHTML = "<strong>Choose a real PDF first</strong><span>Demo names are previews only. Use Choose File to select the PDF you want converted.</span>";
    $("#result").scrollIntoView({ behavior: "auto", block: "nearest" });
    return;
  }
  const tool = tools.find((item) => item.name === state.selectedTool) ?? tools[0];
  if (isToolLocked(tool)) {
    showProLocked(tool.name);
    return;
  }
  const output = getOutputName(selected, tool);
  const selectedTool = state.selectedTool;
  const convertButton = $("#convertNowButton");
  const buttonLabel = convertButton.innerHTML;
  state.converting = true;
  convertButton.disabled = true;
  convertButton.textContent = "Converting…";
  $("#result").classList.remove("hidden");
  $("#result").innerHTML = `<strong>Converting...</strong><span>${escapeHtml(selectedTool)} • ${escapeHtml(selected.name)}</span>`;
  $("#result").scrollIntoView({ behavior: "auto", block: "nearest" });
  try {
    const downloadUrl = await downloadConvertedFile(output, selectedTool, selected);
    state.history.unshift({ output, tool: selectedTool, source: selected.name, time: "Just now", url: downloadUrl });
    renderHistory();
    const inline = isInlineResult(downloadUrl);
    const viewText = inline && /\.(docx|txt)$/i.test(output) ? state.lastPreviewText : "";
    const previewMarkup = downloadUrl && !viewText ? await buildPreviewMarkup(downloadUrl, output) : "";
    $("#result").innerHTML = `
      <strong>✓ ${escapeHtml(output)}</strong>
      <span>${inline ? "" : `Saved to Downloads\Convertory\${escapeHtml(state.lastSavedFile || output)} • `}${escapeHtml(selectedTool)}</span>
      <span>${escapeHtml(state.lastConversionNote || '')}</span>
      ${previewMarkup}
      ${downloadUrl ? `
        <div class="result-actions">
          ${viewText ? `<button type="button" class="view-file-button" data-url="${downloadUrl}" data-name="${escapeHtml(output)}">Open</button>` : ""}
          <button type="button" class="preview-download-button" data-url="${downloadUrl}" data-name="${escapeHtml(output)}">Download</button>
          ${inline ? "" : `<a class="download-again" href="${downloadUrl}" download="${escapeHtml(output)}">Save file</a>
          <button type="button" class="open-file-button" data-file="${escapeHtml(state.lastSavedFile || output)}">Open File</button>`}
        </div>
      ` : ""}
    `;
    if (viewText) openViewer(output, downloadUrl, viewText);
  } catch (error) {
    const message = error.name === "TimeoutError" ? "Conversion timed out. Please retry with a smaller PDF." : error.message || "Could not read this file locally.";
    $("#result").innerHTML = `<strong>Conversion failed</strong><span>${escapeHtml(message)}</span>`;
  } finally {
    state.converting = false;
    convertButton.disabled = false;
    convertButton.innerHTML = buttonLabel;
  }
}

function showProLocked(toolName) {
  $("#result").classList.remove("hidden");
  $("#result").innerHTML = `
    <strong>♛ ${toolName} is Pro</strong>
    <span>Free includes PDF to Word and Excel to PDF.</span>
  `;
  $("#result").scrollIntoView({ behavior: "auto", block: "nearest" });
}

function renderBatch() {
  $("#batchList").innerHTML = state.batch.length
    ? state.batch.map((item) => `
      <div class="stack-item file-row ${item.status === "Pro required" ? "needs-pro" : ""}">
        <span class="file-dot">${item.status === "Completed" ? "✓" : item.status === "Pro required" ? "♛" : "•"}</span>
        <span>
          <strong>${item.name}</strong>
          <small>${item.tool} • ${item.status}</small>
        </span>
        ${item.url ? `<a class="mini-download" href="${item.url}" download="${item.output}">Save</a>` : ""}
      </div>
    `).join("")
    : `<div class="empty-state">No files queued yet. Add demo files or convert a document first.</div>`;
}

function renderHistory() {
  $("#historyList").innerHTML = state.history.length
    ? state.history.map((item) => `
      <div class="stack-item file-row">
        <span class="file-dot">✓</span>
        <span>
          <strong>${item.output}</strong>
          <small>${item.tool} • ${item.source ?? "Converted file"} • ${item.time}</small>
        </span>
        ${item.url ? `<a class="mini-download" href="${item.url}" download="${item.output}">Save</a>` : ""}
      </div>
    `).join("")
    : `<div class="empty-state">No conversions yet. Completed files will appear here.</div>`;
}

function queueDemoFiles() {
  const selected = state.selectedSample;
  if (!selected?.file) {
    state.batch = [];
    $("#result").classList.remove("hidden");
    $("#result").innerHTML = "<strong>Choose a real file first</strong><span>Batch conversion only queues files you selected locally.</span>";
    renderBatch();
    return;
  }
  const tool = tools.find((item) => item.name === state.selectedTool) ?? tools[0];
  const output = getOutputName(selected, tool);
  const alreadyQueued = state.batch.some((item) => item.name === selected.name && item.tool === tool.name);
  if (!alreadyQueued) {
    state.batch.push({
      name: selected.name,
      file: selected.file,
      files: selected.files,
      tool: tool.name,
      output,
      status: "Queued",
      url: null
    });
  }
  renderBatch();
}

async function runBatchQueue() {
  if (!state.batch.length) queueDemoFiles();
  if (!state.batch.length) return;
  let completed = 0;
  state.batch = await Promise.all(state.batch.map(async (item) => {
    const tool = tools.find((entry) => entry.name === item.tool) ?? tools[0];
    if (isToolLocked(tool)) return { ...item, status: "Pro required", url: null };
    let url;
    try { url = item.url ?? await createConvertedFile(item.output, item.tool, item); }
    catch (error) { return {...item,status:`Failed: ${error.message}`,url:null}; }
    completed += item.status === "Completed" ? 0 : 1;
    if (!state.history.some((historyItem) => historyItem.output === item.output && historyItem.source === item.name)) {
      state.history.unshift({ output: item.output, tool: item.tool, source: item.name, time: "Just now", url });
    }
    return { ...item, status: "Completed", url };
  }));
  renderBatch();
  renderHistory();
  if (completed === 0 && state.batch.some((item) => item.status === "Pro required")) {
    $("#result").classList.remove("hidden");
    $("#result").innerHTML = `<strong>♛ Batch needs Pro</strong><span>Some queued formats are locked in Free.</span>`;
  }
}

function updatePrivacyPanel() {
  const rows = document.querySelectorAll(".privacy-row strong");
  if (rows[1]) rows[1].textContent = state.cachePurged ? "0 MB" : "0.8 MB";
  $("#purgeButton").textContent = state.cachePurged ? "Cache Clean" : "Purge Cache";
}

function setTab(tab) {
  document.querySelectorAll("[data-tab]").forEach((button) => {
    button.classList.toggle("active", button.dataset.tab === tab);
  });
  document.querySelectorAll(".tab-panel").forEach((panel) => panel.classList.remove("active"));
  $(`#panel-${tab}`).classList.add("active");
}

document.addEventListener("click", async (event) => {
  const downloadButton = event.target.closest(".preview-download-button");
  if (downloadButton) {
    triggerDownload(downloadButton.dataset.url, downloadButton.dataset.name);
    return;
  }
  const viewButton = event.target.closest(".view-file-button");
  if (viewButton) {
    openViewer(viewButton.dataset.name, viewButton.dataset.url, state.lastPreviewText);
    return;
  }
  const openButton = event.target.closest(".open-file-button");
  if (openButton) {
    if (openButton.dataset.opening) return;
    openButton.dataset.opening = "true";
    const originalLabel = openButton.textContent;
    openButton.textContent = "Opening…";
    try {
      await openSavedFile(openButton.dataset.file);
      openButton.textContent = originalLabel;
    } catch (error) {
      openButton.textContent = error.message || "Could not open";
      window.setTimeout(() => { openButton.textContent = originalLabel; }, 2500);
    } finally {
      delete openButton.dataset.opening;
    }
    return;
  }
  const saveLink = event.target.closest(".download-again, .mini-download");
  if (saveLink && new URL(saveLink.href).pathname.startsWith("/api/download/")) {
    event.preventDefault();
    if (saveLink.dataset.saving) return;
    saveLink.dataset.saving = "true";
    saveLink.textContent = "Saving…";
    let status = saveLink.parentElement.querySelector(".save-status");
    if (!status) {
      status = document.createElement("span");
      status.className = "save-status";
      status.setAttribute("role", "status");
      saveLink.after(status);
    }
    try {
      const saveUrl = new URL(saveLink.href);
      saveUrl.pathname = saveUrl.pathname.replace("/api/download/", "/api/save/");
      const response = await fetch(saveUrl, { method: "POST", signal: AbortSignal.timeout(30000) });
      const saved = await response.json();
      if (!response.ok) throw new Error(saved.error || "Could not save the file.");
      status.textContent = `Saved to Downloads\\Convertory\\${saved.savedFile}`;
      saveLink.textContent = "Save again";
      let openBtn = status.parentElement.querySelector(".open-file-button");
      if (!openBtn) {
        openBtn = document.createElement("button");
        openBtn.type = "button";
        openBtn.className = "open-file-button";
        openBtn.textContent = "Open File";
        status.after(openBtn);
      }
      openBtn.dataset.file = saved.savedFile;
    } catch (error) {
      status.textContent = error.message || "Could not save the file. Please retry.";
      saveLink.textContent = "Retry save";
    } finally {
      delete saveLink.dataset.saving;
    }
    return;
  }
  const toolButton = event.target.closest("[data-tool]");
  if (toolButton) {
    const tool = tools.find((item) => item.name === toolButton.dataset.tool);
    if (tool && isToolLocked(tool)) {
      showProLocked(tool.name);
      return;
    }
    state.selectedTool = toolButton.dataset.tool;
    renderTools();
    $("#result").classList.add("hidden");
  }

  const tabButton = event.target.closest("[data-tab]");
  if (tabButton) setTab(tabButton.dataset.tab);

  const modalFile = event.target.closest("[data-modal-file]");
  if (modalFile) {
    const sample = samples.find((item) => item.name === modalFile.dataset.modalFile);
    selectSample(sample);
    $("#fileModal").classList.add("hidden");
  }
});

const openFileModal = () => $("#fileModal").classList.remove("hidden");
const openFilePicker = () => $("#fileInput").click();

$("#dropzone").addEventListener("click", openFilePicker);
$("#dropzone").addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    openFilePicker();
  }
});
["dragenter", "dragover"].forEach((eventName) => {
  $("#dropzone").addEventListener(eventName, (event) => {
    event.preventDefault();
    event.stopPropagation();
    $("#dropzone").classList.add("is-dragging");
  });
});
["dragleave", "dragend"].forEach((eventName) => {
  $("#dropzone").addEventListener(eventName, (event) => {
    event.preventDefault();
    event.stopPropagation();
    $("#dropzone").classList.remove("is-dragging");
  });
});
$("#dropzone").addEventListener("drop", (event) => {
  event.preventDefault();
  event.stopPropagation();
  $("#dropzone").classList.remove("is-dragging");
  const files = Array.from(event.dataTransfer?.files ?? []);
  if (files.length) selectRealFile(files[0], files);
});
// Safety net: stop the browser/WebView from navigating away to display the raw
// file if a drop lands outside the dropzone.
["dragover", "drop"].forEach((eventName) => {
  window.addEventListener(eventName, (event) => event.preventDefault());
});
$("#selectButton").addEventListener("click", (event) => {
  event.stopPropagation();
  openFilePicker();
});
$("#sampleLinkButton").addEventListener("click", (event) => {
  event.stopPropagation();
  openFileModal();
});
$("#fileInput").addEventListener("change", (event) => {
  const [file] = event.target.files;
  if (file) selectRealFile(file,Array.from(event.target.files));
});
$("#convertNowButton").addEventListener("click", (event) => {
  event.stopPropagation();
  runConversion();
});
$("#closeModalButton").addEventListener("click", () => $("#fileModal").classList.add("hidden"));
$("#proToggle").addEventListener("click", () => {
  state.pro = !state.pro;
  $("#proToggle").textContent = state.pro ? "♛ PRO ACTIVE" : "♛ PRO";
  renderTools();
});
$("#addBatchButton").addEventListener("click", queueDemoFiles);
$("#runBatchButton").addEventListener("click", runBatchQueue);
$("#purgeButton").addEventListener("click", () => {
  state.cachePurged = true;
  updatePrivacyPanel();
});

renderTools();
renderModalFiles();
renderBatch();
renderHistory();
applyCapabilities();
updatePrivacyPanel();





















