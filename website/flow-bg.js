(function () {
  var canvas = document.getElementById("flow-canvas");
  if (!canvas || !canvas.getContext) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  var ctx = canvas.getContext("2d");
  var width, height, dpr;
  var paths = [];
  var numPaths = 36;
  var running = true;
  var mouseX = null, mouseY = null;
  var mouseRadius = 170;
  var heroEl = canvas.parentElement || canvas;

  function resize() {
    var rect = canvas.parentElement.getBoundingClientRect();
    dpr = window.devicePixelRatio || 1;
    width = rect.width;
    height = rect.height;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function seedPaths() {
    paths = [];
    for (var i = 0; i < numPaths; i++) {
      paths.push({
        isLeft: i % 2 === 0,
        startY: (i / numPaths) * height * 1.3 - height * 0.15,
        t: Math.random(),
        speed: 0.00035 + Math.random() * 0.00045
      });
    }
  }

  function bezierPoint(t, p0, p1, p2, p3) {
    var u = 1 - t;
    return {
      x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
      y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
    };
  }

  function render() {
    if (!running) return;
    ctx.clearRect(0, 0, width, height);
    var centerX = width / 2;
    var centerY = height * 0.97;

    for (var i = 0; i < paths.length; i++) {
      var path = paths[i];
      var p0 = { x: path.isLeft ? 0 : width, y: path.startY };
      var p1 = { x: path.isLeft ? centerX * 0.5 : width - centerX * 0.5, y: path.startY };
      var p2 = { x: path.isLeft ? centerX * 0.8 : width - centerX * 0.8, y: centerY };
      var p3 = { x: centerX, y: centerY };

      ctx.beginPath();
      ctx.moveTo(p0.x, p0.y);
      ctx.bezierCurveTo(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
      ctx.strokeStyle = "rgba(0, 183, 255, 0.32)";
      ctx.lineWidth = 1.4;
      ctx.setLineDash([1, 5]);
      ctx.stroke();
      ctx.setLineDash([]);

      path.t += path.speed;
      if (path.t > 1) {
        path.t = 0;
        path.startY += (Math.random() - 0.5) * 12;
      }
      var pos = bezierPoint(path.t, p0, p1, p2, p3);
      var drawX = pos.x, drawY = pos.y, size = 4, alpha = 0.75;

      if (mouseX !== null) {
        var dx = mouseX - pos.x, dy = mouseY - pos.y;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < mouseRadius) {
          var pull = (1 - dist / mouseRadius);
          drawX += dx * pull * 0.55;
          drawY += dy * pull * 0.55;
          size += pull * 2.5;
          alpha += pull * 0.35;
        }
      }

      ctx.fillStyle = "rgba(0, 183, 255, " + Math.min(alpha, 1) + ")";
      ctx.fillRect(drawX - size / 2, drawY - size / 2, size, size);
    }

    requestAnimationFrame(render);
  }

  document.addEventListener("visibilitychange", function () {
    running = !document.hidden;
    if (running) requestAnimationFrame(render);
  });

  window.addEventListener("resize", function () {
    resize();
    seedPaths();
  });

  heroEl.addEventListener("mousemove", function (e) {
    var rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
  });

  heroEl.addEventListener("mouseleave", function () {
    mouseX = null;
    mouseY = null;
  });

  resize();
  seedPaths();
  requestAnimationFrame(render);
})();
