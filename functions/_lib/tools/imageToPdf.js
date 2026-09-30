import { PDFDocument } from "pdf-lib";

const MAX_DIM = 14400; // mirrors conversion-engine.py's `scale = min(1, 14400 / max(image.size))`

// Wraps each raster image as its own PDF page, sized to the image's pixel
// dimensions (capped at MAX_DIM like the Python PyMuPDF path).
export async function imageToPdf(files) {
  if (!Array.isArray(files) || !files.length) {
    throw new Error("Select at least one image.");
  }
  const doc = await PDFDocument.create();
  for (const file of files) {
    const name = String(file.name || "").toLowerCase();
    let image;
    if (name.endsWith(".png")) {
      image = await doc.embedPng(file.bytes);
    } else if (name.endsWith(".jpg") || name.endsWith(".jpeg")) {
      image = await doc.embedJpg(file.bytes);
    } else if (name.endsWith(".webp")) {
      throw new Error("WebP not yet supported, please convert to PNG/JPEG first.");
    } else {
      throw new Error("Image to PDF requires .png,.jpg,.jpeg files.");
    }
    const scale = Math.min(1, MAX_DIM / Math.max(image.width, image.height));
    const width = image.width * scale;
    const height = image.height * scale;
    const page = doc.addPage([width, height]);
    page.drawImage(image, { x: 0, y: 0, width, height });
  }
  return doc.save();
}
