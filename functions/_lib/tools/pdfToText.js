import "../domPolyfill.js";
import * as pdfjsLib from "pdfjs-dist/legacy/build/pdf.mjs";
import * as pdfjsWorker from "pdfjs-dist/legacy/build/pdf.worker.mjs";

// There are no real nested Worker threads inside a Workers/Pages Functions
// isolate. pdf.js's own PDFWorker looks for `globalThis.pdfjsWorker` before
// trying to spawn a real `new Worker(...)` (which would throw here anyway);
// pre-populating it makes pdf.js run its worker message handler directly in
// this isolate ("fake worker") instead of attempting real worker threads.
globalThis.pdfjsWorker = pdfjsWorker;

function groupIntoRows(items) {
  const rows = [];
  for (const it of items) {
    if (!it.str) continue;
    const x = it.transform[4];
    const y = it.transform[5];
    const height = it.height || Math.abs(it.transform[3]) || 10;
    let row = rows.find((r) => Math.abs(r.y - y) <= Math.max(2, height * 0.5));
    if (!row) {
      row = { y, items: [] };
      rows.push(row);
    }
    row.items.push({ x, text: it.str, width: it.width || 0, height });
  }
  // PDF user-space y grows upward, so sort rows top-to-bottom by descending y.
  rows.sort((a, b) => b.y - a.y);
  return rows;
}

function rowToLine(row) {
  const sorted = row.items.slice().sort((a, b) => a.x - b.x);
  let line = sorted[0].text;
  let prevRight = sorted[0].x + sorted[0].width;
  let prevHeight = sorted[0].height;
  for (let k = 1; k < sorted.length; k++) {
    const cur = sorted[k];
    const gap = cur.x - prevRight;
    // Wide gaps read as column breaks (tab); normal word spacing stays a space.
    line += gap > Math.max(prevHeight, cur.height) * 1.6 ? "\t" : " ";
    line += cur.text;
    prevRight = cur.x + cur.width;
    prevHeight = cur.height;
  }
  return line;
}

// Extracts plain text from a PDF, reconstructing reading order from each text
// item's x/y position (row-clustering + left-to-right within a row), rather
// than trusting the PDF content stream's raw item order.
export async function pdfToText(fileBytes) {
  const loadingTask = pdfjsLib.getDocument({
    data: fileBytes,
    useWorkerFetch: false,
    isEvalSupported: false,
    disableFontFace: true
  });
  const pdf = await loadingTask.promise;
  try {
    const pageTexts = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const content = await page.getTextContent();
      const rows = groupIntoRows(content.items);
      pageTexts.push(rows.map(rowToLine).join("\n"));
    }
    return pageTexts.join("\n\n");
  } finally {
    await pdf.destroy();
  }
}
