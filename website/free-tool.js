(function () {
  var DAILY_LIMIT = 3;
  var STORAGE_KEY = "cf_free_usage_v1";

  if (window.pdfjsLib) {
    window.pdfjsLib.GlobalWorkerOptions.workerSrc =
      "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
  }

  var grid = document.getElementById("tools-grid");
  var fileInput = document.getElementById("ft-file");
  var statusEl = document.getElementById("ft-status");
  var usageEl = document.getElementById("ft-usage");

  if (!grid || !fileInput || !statusEl) return;

  var pendingCard = null;

  function todayKey() {
    var d = new Date();
    return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
  }

  function getUsage() {
    try {
      var raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
      if (raw.date !== todayKey()) return { date: todayKey(), count: 0 };
      return raw;
    } catch (e) {
      return { date: todayKey(), count: 0 };
    }
  }

  function setUsage(u) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(u)); } catch (e) {}
  }

  function remaining() {
    return Math.max(0, DAILY_LIMIT - getUsage().count);
  }

  function renderUsage() {
    usageEl.textContent = "Free conversions left today: " + remaining() + " / " + DAILY_LIMIT;
  }

  function bumpUsage() {
    var u = getUsage();
    u.count += 1;
    setUsage(u);
    renderUsage();
  }

  function setToast(text, cls) {
    statusEl.textContent = "";
    statusEl.className = "tools-toast" + (cls ? " " + cls : "");
    if (cls === "is-pro") {
      statusEl.innerHTML = text;
    } else {
      statusEl.textContent = text;
    }
  }

  function ext(name) {
    var m = /\.([a-z0-9]+)$/i.exec(name || "");
    return m ? m[1].toLowerCase() : "";
  }

  function baseName(name) {
    return name.replace(/\.[a-z0-9]+$/i, "");
  }

  function download(blob, filename) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
  }

  function goToPlatforms(toolName) {
    setToast(
      '"' + toolName + '" is available in Convertory Pro. Download the app and upgrade to Pro to use it — redirecting...',
      "is-pro"
    );
    setTimeout(function () {
      var el = document.getElementById("platforms");
      if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 650);
  }

  function loadPdfText(file) {
    return file.arrayBuffer().then(function (buf) {
      return window.pdfjsLib.getDocument({ data: buf }).promise;
    }).then(function (doc) {
      var pages = [];
      var chain = Promise.resolve();
      for (var i = 1; i <= doc.numPages; i++) {
        (function (pageNum) {
          chain = chain.then(function () {
            return doc.getPage(pageNum).then(function (page) {
              return page.getTextContent();
            }).then(function (content) {
              var text = content.items.map(function (it) { return it.str; }).join(" ");
              pages.push(text);
            });
          });
        })(i);
      }
      return chain.then(function () { return pages; });
    });
  }

  function hasText(pages) {
    return pages.some(function (p) { return p.trim().length > 0; });
  }

  var SCANNED_PDF_ERROR = "This PDF has no selectable text (looks scanned/image-based). The free web tool can't OCR it — use the Convertory app, which includes OCR.";

  function convertPdfToText(file) {
    return loadPdfText(file).then(function (pages) {
      if (!hasText(pages)) throw new Error(SCANNED_PDF_ERROR);
      var text = pages.join("\n\n--- page break ---\n\n");
      download(new Blob([text], { type: "text/plain;charset=utf-8" }), baseName(file.name) + ".txt");
    });
  }

  function convertPdfToWord(file) {
    return loadPdfText(file).then(function (pages) {
      if (!hasText(pages)) throw new Error(SCANNED_PDF_ERROR);
      var blob = window.buildDocx(pages);
      download(blob, baseName(file.name) + ".docx");
    });
  }

  function convertDocToPdf(file) {
    if (ext(file.name) !== "docx") {
      return Promise.reject(new Error("In-browser conversion currently only supports .docx for this format. Download the Convertory app for other formats."));
    }
    return file.arrayBuffer().then(function (buf) {
      return window.mammoth.extractRawText({ arrayBuffer: buf });
    }).then(function (result) {
      var jsPDF = window.jspdf.jsPDF;
      var pdf = new jsPDF({ unit: "pt", format: "a4" });
      var margin = 48;
      var pageWidth = pdf.internal.pageSize.getWidth();
      var pageHeight = pdf.internal.pageSize.getHeight();
      var maxWidth = pageWidth - margin * 2;
      var lineHeight = 16;
      pdf.setFontSize(11);
      var lines = pdf.splitTextToSize(result.value || "(Document appears to be empty)", maxWidth);
      var y = margin;
      for (var i = 0; i < lines.length; i++) {
        if (y > pageHeight - margin) {
          pdf.addPage();
          y = margin;
        }
        pdf.text(lines[i], margin, y);
        y += lineHeight;
      }
      pdf.save(baseName(file.name) + ".pdf");
    });
  }

  function runConversion(tool, file) {
    if (tool === "pdf2text") return convertPdfToText(file);
    if (tool === "pdf2word") return convertPdfToWord(file);
    if (tool === "doc2pdf") return convertDocToPdf(file);
    return Promise.reject(new Error("Unknown tool"));
  }

  grid.addEventListener("click", function (e) {
    var card = e.target.closest(".card[data-tool]");
    if (!card) return;
    var tool = card.getAttribute("data-tool");

    if (tool === "pro") {
      goToPlatforms(card.getAttribute("data-pro-name") || "This tool");
      return;
    }

    if (remaining() <= 0) {
      setToast('You\'ve used today\'s free conversions. Upgrade to Convertory Pro for unlimited use — redirecting...', "is-pro");
      setTimeout(function () {
        var el = document.getElementById("platforms");
        if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 650);
      return;
    }

    pendingCard = card;
    fileInput.value = "";
    fileInput.accept = card.getAttribute("data-accept") || "";
    fileInput.click();
  });

  fileInput.addEventListener("change", function () {
    var file = fileInput.files && fileInput.files[0];
    if (!file || !pendingCard) return;

    if (file.size > 20 * 1024 * 1024) {
      setToast("File is too large (over 20MB). Choose a smaller file.", "is-error");
      pendingCard = null;
      return;
    }

    var tool = pendingCard.getAttribute("data-tool");
    var card = pendingCard;
    card.classList.add("is-busy");
    setToast("Converting, your file never leaves your device...");

    runConversion(tool, file).then(function () {
      setToast("Done! Download started.");
      bumpUsage();
    }).catch(function (err) {
      setToast("Conversion failed: " + (err && err.message ? err.message : "unknown error"), "is-error");
    }).then(function () {
      card.classList.remove("is-busy");
      pendingCard = null;
    });
  });

  renderUsage();
})();
