// Reports which tools this deployment can run, so the UI hides the rest instead
// of showing "Conversion failed". Keep in sync with SUPPORTED_TOOLS in convert.js
// plus the client-side PDF to Word fallback in ms-store/app.js.
export function onRequestGet() {
  return new Response(JSON.stringify({
    tools: ["PDF to Word", "PDF to Text", "Merge PDF", "Watermark PDF", "Image to PDF"],
    engine: "hosted"
  }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
