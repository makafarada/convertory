// Tools that need the container engine (engine/server.py: LibreOffice, Tesseract,
// PyMuPDF). Only forwarded when ENGINE_URL + ENGINE_TOKEN are configured; keep in
// sync with KINDS in engine/server.py and capabilities.js.
export const ENGINE_TOOLS = [
  "PDF to Excel", "PDF to PowerPoint", "Image to Excel", "Image to Text", "Word to PDF",
  "Excel to PDF", "PowerPoint to PDF", "Compress PDF", "More Formats"
];
