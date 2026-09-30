import { PDFDocument, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import { LIBERATION_SANS_REGULAR_B64 } from "../fonts/liberation-sans-regular.js";

function base64ToBytes(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

const FONT_BYTES = base64ToBytes(LIBERATION_SANS_REGULAR_B64);

// Draws a diagonal-free, centered translucent text overlay on every page.
// Mirrors conversion-engine.py's `Watermark PDF` branch (PyMuPDF TextWriter):
// same 120-char cap, same "min(36, availableWidth / widthAtSize1)" sizing,
// same center-x / mid-height placement, same opacity/color. Liberation Sans
// is a full-Unicode TTF (not pdf-lib's built-in WinAnsi-only StandardFonts),
// so it renders Turkish characters (ğ, ş, ı, ö, ü, ç) correctly.
export async function watermarkPdf(fileBytes, options) {
  const label = String(options?.watermark ?? "CONFIDENTIAL").trim().slice(0, 120);
  if (!label) throw new Error("Enter watermark text.");

  const doc = await PDFDocument.load(fileBytes, { ignoreEncryption: true });
  doc.registerFontkit(fontkit);
  const font = await doc.embedFont(FONT_BYTES, { subset: true });

  for (const page of doc.getPages()) {
    const { width, height } = page.getSize();
    const availableWidth = Math.max(1, width - 48);
    const widthAtSize1 = font.widthOfTextAtSize(label, 1) || 1;
    const size = Math.min(36, availableWidth / widthAtSize1);
    const textWidth = font.widthOfTextAtSize(label, size);
    const x = Math.max(12, (width - textWidth) / 2);
    const y = height / 2;
    page.drawText(label, {
      x,
      y,
      size,
      font,
      color: rgb(0.25, 0.3, 0.4),
      opacity: 0.25
    });
  }

  return doc.save();
}
