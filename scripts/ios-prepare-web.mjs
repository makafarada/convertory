// Copies ms-store/ into ios-web/ for the Capacitor iOS shell, leaving out
// files that aren't part of the running app (msix/ is a ~1.1GB Windows
// Store package, screenshots/ is store-listing marketing art — neither
// is referenced by index.html/app.js, both would just bloat the IPA).
import { cpSync, rmSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = join(root, "ms-store");
const dest = join(root, "ios-web");

if (existsSync(dest)) rmSync(dest, { recursive: true, force: true });

cpSync(src, dest, {
  recursive: true,
  filter: (path) => {
    const rel = path.slice(src.length + 1).replace(/\\/g, "/");
    if (rel.startsWith("msix")) return false;
    if (rel.startsWith("screenshots")) return false;
    return true;
  },
});

console.log(`ios-web/ prepared from ms-store/ (msix/, screenshots/ excluded)`);
