import { PDFDocument } from "pdf-lib";

// Concatenates every input PDF's pages, in order, into one output PDF.
// Mirrors conversion-engine.py's `Merge PDF` branch (PyMuPDF insert_pdf loop).
export async function mergePdf(files) {
  if (!Array.isArray(files) || files.length < 2) {
    throw new Error("Select at least two PDFs to merge.");
  }
  const merged = await PDFDocument.create();
  for (const file of files) {
    const src = await PDFDocument.load(file.bytes, { ignoreEncryption: true });
    const pages = await merged.copyPages(src, src.getPageIndices());
    for (const page of pages) merged.addPage(page);
  }
  return merged.save();
}
