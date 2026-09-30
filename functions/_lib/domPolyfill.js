// Cloudflare Pages Functions run in a Workers V8 isolate: no `document`, no
// canvas, no `DOMMatrix`. pdfjs-dist's module top level does
// `const SCALE_MATRIX = new DOMMatrix();` unconditionally (used by its
// canvas-rendering code paths), so importing pdf.mjs throws
// "DOMMatrix is not defined" before any of our code runs -- even though we
// only ever call `getTextContent()`, never `page.render()`.
// This is a minimal 2D-affine stand-in, just enough for pdf.js's module
// top level (and any incidental matrix math on the text-extraction path) to
// not throw. It is NOT a full DOMMatrix implementation (no 3D/CSS parsing).
// Import this module (for its side effect) before anything that imports
// pdfjs-dist.
if (typeof globalThis.DOMMatrix === "undefined") {
  class DOMMatrixPolyfill {
    constructor(init) {
      this.a = 1;
      this.b = 0;
      this.c = 0;
      this.d = 1;
      this.e = 0;
      this.f = 0;
      if (Array.isArray(init) && init.length >= 6) {
        [this.a, this.b, this.c, this.d, this.e, this.f] = init;
      }
    }
    multiplySelf(other) {
      const { a, b, c, d, e, f } = this;
      this.a = a * other.a + c * other.b;
      this.b = b * other.a + d * other.b;
      this.c = a * other.c + c * other.d;
      this.d = b * other.c + d * other.d;
      this.e = a * other.e + c * other.f + e;
      this.f = b * other.e + d * other.f + f;
      return this;
    }
    preMultiplySelf(other) {
      const result = new DOMMatrixPolyfill([other.a, other.b, other.c, other.d, other.e, other.f]).multiplySelf(this);
      Object.assign(this, result);
      return this;
    }
    translate(tx, ty) {
      return new DOMMatrixPolyfill([this.a, this.b, this.c, this.d, this.e, this.f]).multiplySelf({ a: 1, b: 0, c: 0, d: 1, e: tx, f: ty });
    }
    scale(sx, sy = sx) {
      return new DOMMatrixPolyfill([this.a, this.b, this.c, this.d, this.e, this.f]).multiplySelf({ a: sx, b: 0, c: 0, d: sy, e: 0, f: 0 });
    }
    invertSelf() {
      const { a, b, c, d, e, f } = this;
      const det = a * d - b * c || 1;
      this.a = d / det;
      this.b = -b / det;
      this.c = -c / det;
      this.d = a / det;
      this.e = (c * f - d * e) / det;
      this.f = (b * e - a * f) / det;
      return this;
    }
  }
  globalThis.DOMMatrix = DOMMatrixPolyfill;
}
