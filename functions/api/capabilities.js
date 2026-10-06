// Reports which tools this deployment can run, so the UI hides the rest instead
// of showing "Conversion failed". The container engine tools (see ENGINE_TOOLS in
// _lib/engineTools.js) are advertised only when ENGINE_URL + ENGINE_TOKEN are configured.
import { ENGINE_TOOLS } from "../_lib/engineTools.js";

const BASE_TOOLS = ["PDF to Word", "PDF to Text", "Merge PDF", "Watermark PDF", "Image to PDF"];

export function onRequestGet({ env }) {
  const engine = Boolean(env?.ENGINE_URL && env?.ENGINE_TOKEN);
  return new Response(JSON.stringify({
    tools: engine ? [...BASE_TOOLS, ...ENGINE_TOOLS] : BASE_TOOLS,
    engine: engine ? "container" : "hosted"
  }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
