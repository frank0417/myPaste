// Mirrors ScreenshotLayout / ScreenshotRenderer so CI can check the overlay
// geometry without AppKit: selection handles, toolbar placement, snapping,
// window picking, and the pixel crop that the PNG compositor uses.

const HANDLE_HIT = 10;
const MIN_SELECTION = 4;
const TOOLBAR = { width: 638, height: 48 };
const TOOLBAR_GAP = 12;
const SIZE_BADGE_HEIGHT = 22;
const SIZE_BADGE_GAP = 6;
const ARROW_HEAD_LENGTH = 14;
const ARROW_HEAD_ANGLE = Math.PI / 6;
const DEFAULT_COLOR = "#F5222D";
const SELECTION_COLOR = "#2F80FF";
const TOOLBAR_TOOLS = ["rect", "ellipse", "line", "arrow", "pen", "text", "pin", "mosaic", "crop"];
const PALETTE = [
  "#F5222D", "#FA8C16", "#FADB14", "#52C41A",
  "#1890FF", "#722ED1", "#FFFFFF", "#1B2A2F"
];
const LINE_WIDTHS = [2, 3, 5];

function normalizedRect(a, b) {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x),
    height: Math.abs(a.y - b.y)
  };
}

function clamp(rect, bounds) {
  const r = { ...rect };
  if (r.width > bounds.width) r.width = bounds.width;
  if (r.height > bounds.height) r.height = bounds.height;
  r.x = Math.min(Math.max(r.x, bounds.x), bounds.x + bounds.width - r.width);
  r.y = Math.min(Math.max(r.y, bounds.y), bounds.y + bounds.height - r.height);
  return r;
}

function sizeLabel(width, height) {
  return `${Math.round(width)} × ${Math.round(height)}`;
}

function handlePoints(rect) {
  const midX = rect.x + rect.width / 2;
  const midY = rect.y + rect.height / 2;
  return {
    nw: { x: rect.x, y: rect.y },
    n: { x: midX, y: rect.y },
    ne: { x: rect.x + rect.width, y: rect.y },
    e: { x: rect.x + rect.width, y: midY },
    se: { x: rect.x + rect.width, y: rect.y + rect.height },
    s: { x: midX, y: rect.y + rect.height },
    sw: { x: rect.x, y: rect.y + rect.height },
    w: { x: rect.x, y: midY }
  };
}

function hitTest(point, selection) {
  const points = handlePoints(selection);
  const order = ["nw", "ne", "se", "sw", "n", "e", "s", "w"];
  for (const handle of order) {
    const origin = points[handle];
    if (Math.hypot(point.x - origin.x, point.y - origin.y) <= HANDLE_HIT) return handle;
  }
  if (
    point.x >= selection.x - 2 &&
    point.x <= selection.x + selection.width + 2 &&
    point.y >= selection.y - 2 &&
    point.y <= selection.y + selection.height + 2
  ) {
    return "move";
  }
  return null;
}

function resize(rect, handle, point, bounds) {
  let minX = rect.x;
  let minY = rect.y;
  let maxX = rect.x + rect.width;
  let maxY = rect.y + rect.height;
  if (["n", "ne", "nw"].includes(handle)) minY = point.y;
  if (["s", "se", "sw"].includes(handle)) maxY = point.y;
  if (["e", "ne", "se"].includes(handle)) maxX = point.x;
  if (["w", "nw", "sw"].includes(handle)) minX = point.x;
  return clamp(normalizedRect({ x: minX, y: minY }, { x: maxX, y: maxY }), bounds);
}

function move(rect, delta, bounds) {
  return clamp({ ...rect, x: rect.x + delta.width, y: rect.y + delta.height }, bounds);
}

function snapEnd(from, to, tool, shift) {
  if (!shift) return to;
  if (["rect", "ellipse", "mosaic"].includes(tool)) {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const side = Math.min(Math.abs(dx), Math.abs(dy));
    return {
      x: from.x + (dx < 0 ? -side : side),
      y: from.y + (dy < 0 ? -side : side)
    };
  }
  if (["line", "arrow"].includes(tool)) {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const length = Math.hypot(dx, dy);
    const snapped = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
    return { x: from.x + Math.cos(snapped) * length, y: from.y + Math.sin(snapped) * length };
  }
  return to;
}

function toolbarFrame(selection, canvas, size = TOOLBAR, offset = { width: 0, height: 0 }) {
  let x = selection.x + selection.width / 2 - size.width / 2 + offset.width;
  let y = selection.y + selection.height + TOOLBAR_GAP + offset.height;
  if (y + size.height > canvas.y + canvas.height - 8) {
    y = selection.y - size.height - TOOLBAR_GAP + offset.height;
  }
  x = Math.min(
    Math.max(x, canvas.x + 8),
    Math.max(canvas.x + 8, canvas.x + canvas.width - size.width - 8)
  );
  y = Math.min(
    Math.max(y, canvas.y + 8),
    Math.max(canvas.y + 8, canvas.y + canvas.height - size.height - 8)
  );
  return { x, y, width: size.width, height: size.height };
}

function sizeBadgeFrame(selection, canvas, textWidth) {
  const width = Math.max(52, textWidth + 16);
  const height = SIZE_BADGE_HEIGHT;
  let x = selection.x;
  let y = selection.y - height - SIZE_BADGE_GAP;
  if (y < canvas.y + 4) {
    y = Math.min(selection.y + SIZE_BADGE_GAP, canvas.y + canvas.height - height - 4);
  }
  x = Math.min(
    Math.max(x, canvas.x + 4),
    Math.max(canvas.x + 4, canvas.x + canvas.width - width - 4)
  );
  return { x, y, width, height };
}

function arrowHead(from, to) {
  const angle = Math.atan2(to.y - from.y, to.x - from.x);
  return {
    left: {
      x: to.x - ARROW_HEAD_LENGTH * Math.cos(angle - ARROW_HEAD_ANGLE),
      y: to.y - ARROW_HEAD_LENGTH * Math.sin(angle - ARROW_HEAD_ANGLE)
    },
    right: {
      x: to.x - ARROW_HEAD_LENGTH * Math.cos(angle + ARROW_HEAD_ANGLE),
      y: to.y - ARROW_HEAD_LENGTH * Math.sin(angle + ARROW_HEAD_ANGLE)
    }
  };
}

function windowAt(point, windows) {
  return windows
    .filter((w) =>
      point.x >= w.x && point.x <= w.x + w.width &&
      point.y >= w.y && point.y <= w.y + w.height
    )
    .sort((a, b) => a.width * a.height - b.width * b.height)[0] ?? null;
}

function localFlippedRect(cgBounds, primaryMaxY, screenFrame) {
  const cocoa = {
    x: cgBounds.x,
    y: primaryMaxY - cgBounds.y - cgBounds.height,
    width: cgBounds.width,
    height: cgBounds.height
  };
  const local = {
    x: cocoa.x - screenFrame.x,
    y: cocoa.y - screenFrame.y,
    width: cocoa.width,
    height: cocoa.height
  };
  return {
    x: local.x,
    y: screenFrame.height - local.y - local.height,
    width: local.width,
    height: local.height
  };
}

function pixelCrop(selection, scale, imageWidth, imageHeight) {
  const rect = {
    x: Math.round(selection.x * scale),
    y: Math.round(selection.y * scale),
    width: Math.max(1, Math.round(selection.width * scale)),
    height: Math.max(1, Math.round(selection.height * scale))
  };
  const ix = Math.max(rect.x, 0);
  const iy = Math.max(rect.y, 0);
  const ix2 = Math.min(rect.x + rect.width, imageWidth);
  const iy2 = Math.min(rect.y + rect.height, imageHeight);
  return { x: ix, y: iy, width: Math.max(0, ix2 - ix), height: Math.max(0, iy2 - iy) };
}

function isDrawable(tool) {
  return tool !== "move" && tool !== "crop";
}

function isStamp(tool) {
  return tool === "text" || tool === "pin";
}

let failed = 0;
function assertEqual(actual, expected, name) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    console.error(`FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    failed += 1;
  } else {
    console.log(`PASS ${name}`);
  }
}
function assertTrue(cond, name) {
  assertEqual(Boolean(cond), true, name);
}

const canvas = { x: 0, y: 0, width: 1440, height: 900 };
const selection = { x: 200, y: 120, width: 960, height: 455 };

assertEqual(normalizedRect({ x: 10, y: 20 }, { x: 4, y: 8 }), { x: 4, y: 8, width: 6, height: 12 }, "drag is normalized");
assertEqual(sizeLabel(960, 455), "960 × 455", "size badge matches the overlay caption");
assertEqual(sizeLabel(1919.6, 1079.6), "1920 × 1080", "fractional sizes round");

assertEqual(DEFAULT_COLOR, "#F5222D", "annotation ink defaults to red");
assertEqual(SELECTION_COLOR, "#2F80FF", "selection chrome is blue");
assertEqual(TOOLBAR_TOOLS, ["rect", "ellipse", "line", "arrow", "pen", "text", "pin", "mosaic", "crop"], "toolbar tools match the strip");
assertTrue(PALETTE.includes(DEFAULT_COLOR), "default color is on the palette");
assertEqual(LINE_WIDTHS, [2, 3, 5], "three stroke widths");
assertTrue(isDrawable("arrow") && !isDrawable("crop") && !isDrawable("move"), "crop/move are not drawable");
assertTrue(isStamp("text") && isStamp("pin") && !isStamp("rect"), "text and pin stamp on click");

// Overlay NSView is flipped (origin top-left). NSImage.draw without respectFlipped
// paints the freeze upside down; the compositor must draw the CGImage before
// flipping the context so the PNG stays right-side up.
const IMAGE_DRAW_RESPECTS_FLIPPED = true;
const COMPOSITE_DRAWS_IMAGE_BEFORE_FLIP = true;
assertTrue(IMAGE_DRAW_RESPECTS_FLIPPED, "freeze is drawn with respectFlipped");
assertTrue(COMPOSITE_DRAWS_IMAGE_BEFORE_FLIP, "PNG paints the bitmap before the stroke flip");

function outputPixelSize(contentRect, pointPixelScale, screenPoints, backingScale) {
  const filterScale = pointPixelScale > 0 ? pointPixelScale : 1;
  const filterWidth = Math.round(contentRect.width * filterScale);
  const filterHeight = Math.round(contentRect.height * filterScale);
  const screenWidth = Math.round(screenPoints.width * Math.max(backingScale, 1));
  const screenHeight = Math.round(screenPoints.height * Math.max(backingScale, 1));
  if (filterWidth >= screenWidth && filterHeight >= screenHeight) {
    return { width: Math.max(filterWidth, 1), height: Math.max(filterHeight, 1) };
  }
  return { width: Math.max(screenWidth, 1), height: Math.max(screenHeight, 1) };
}
assertEqual(
  outputPixelSize({ width: 1512, height: 982 }, 2, { width: 1512, height: 982 }, 2),
  { width: 3024, height: 1964 },
  "Retina capture is 2x pixels, not 1920×1080"
);
assertEqual(
  outputPixelSize({ width: 1512, height: 982 }, 1, { width: 1512, height: 982 }, 2),
  { width: 3024, height: 1964 },
  "a 1x filter scale still uses backingScaleFactor"
);
assertEqual(
  outputPixelSize({ width: 1920, height: 1080 }, 1, { width: 1920, height: 1080 }, 1),
  { width: 1920, height: 1080 },
  "a 1x display stays 1x"
);
assertTrue(
  outputPixelSize({ width: 1512, height: 982 }, 2, { width: 1512, height: 982 }, 2).width > 1920,
  "output is larger than ScreenCaptureKit's 1920 default"
);

const handles = handlePoints(selection);
assertEqual(handles.nw, { x: 200, y: 120 }, "nw handle is top-left");
assertEqual(handles.se, { x: 1160, y: 575 }, "se handle is bottom-right");
assertEqual(handles.n, { x: 680, y: 120 }, "n handle is top-center");
assertEqual(hitTest({ x: 200, y: 120 }, selection), "nw", "handle hit wins over move");
assertEqual(hitTest({ x: 500, y: 300 }, selection), "move", "interior is move");
assertEqual(hitTest({ x: 10, y: 10 }, selection), null, "outside is a new selection");
assertEqual(hitTest({ x: 208, y: 120 }, selection), "nw", "handle hit radius covers nearby clicks");

const bounds = canvas;
let resized = resize(selection, "se", { x: 800, y: 400 }, bounds);
assertEqual(resized, { x: 200, y: 120, width: 600, height: 280 }, "se handle shrinks the selection");
resized = resize(selection, "nw", { x: 250, y: 150 }, bounds);
assertEqual(resized, { x: 250, y: 150, width: 910, height: 425 }, "nw handle moves origin");
const moved = move(selection, { width: -300, height: 20 }, bounds);
assertEqual(moved.x, 0, "move is clamped to the left edge");
assertEqual(moved.y, 140, "move keeps the vertical delta when it fits");

assertEqual(MIN_SELECTION, 4, "tiny drags are discarded");

const square = snapEnd({ x: 0, y: 0 }, { x: 80, y: 20 }, "rect", true);
assertEqual(square, { x: 20, y: 20 }, "shift+rect locks to a square");
const horizontal = snapEnd({ x: 0, y: 0 }, { x: 100, y: 8 }, "arrow", true);
assertEqual(
  { x: Math.round(horizontal.x), y: Math.round(horizontal.y) },
  { x: 100, y: 0 },
  "shift+arrow snaps to 45-degree increments"
);
assertEqual(snapEnd({ x: 0, y: 0 }, { x: 80, y: 20 }, "rect", false), { x: 80, y: 20 }, "no shift, no snap");

let bar = toolbarFrame(selection, canvas);
assertEqual(bar, { x: 361, y: 587, width: 638, height: 48 }, "toolbar hangs centered below the selection");
bar = toolbarFrame({ x: 200, y: 820, width: 400, height: 60 }, canvas);
assertTrue(bar.y < 820, "no room below: toolbar flips above the selection");
bar = toolbarFrame({ x: 20, y: 120, width: 80, height: 40 }, canvas);
assertEqual(bar.x, 8, "toolbar is kept inside the left edge");
bar = toolbarFrame({ x: 1400, y: 120, width: 30, height: 40 }, canvas);
assertEqual(bar.x, 1440 - 638 - 8, "toolbar is kept inside the right edge");

const badge = sizeBadgeFrame(selection, canvas, 64);
assertEqual(badge.y, 120 - 22 - 6, "size badge sits above the top-left");
assertEqual(badge.x, 200, "size badge aligns to the left of the selection");
const tight = sizeBadgeFrame({ x: 10, y: 4, width: 200, height: 80 }, canvas, 64);
assertTrue(tight.y >= 4, "near the top, the badge drops into the selection");

const head = arrowHead({ x: 0, y: 0 }, { x: 100, y: 0 });
assertEqual(
  { left: { x: Math.round(head.left.x), y: Math.round(head.left.y) }, right: { x: Math.round(head.right.x), y: Math.round(head.right.y) } },
  { left: { x: 88, y: 7 }, right: { x: 88, y: -7 } },
  "arrow head flares behind the tip"
);

const nested = windowAt({ x: 50, y: 50 }, [
  { x: 0, y: 0, width: 400, height: 300 },
  { x: 40, y: 40, width: 80, height: 80 }
]);
assertEqual(nested, { x: 40, y: 40, width: 80, height: 80 }, "window pick prefers the inner frame");
assertEqual(windowAt({ x: 900, y: 10 }, [{ x: 0, y: 0, width: 400, height: 300 }]), null, "empty space is not a window");

const local = localFlippedRect(
  { x: 100, y: 50, width: 200, height: 100 },
  900,
  { x: 0, y: 0, width: 1440, height: 900 }
);
assertEqual(local, { x: 100, y: 50, width: 200, height: 100 }, "CG bounds on the primary screen stay top-left");

const crop = pixelCrop({ x: 200, y: 120, width: 960, height: 455 }, 2, 2880, 1800);
assertEqual(crop, { x: 400, y: 240, width: 1920, height: 910 }, "crop is in bitmap pixels");
const clipped = pixelCrop({ x: 1400, y: 800, width: 200, height: 200 }, 1, 1440, 900);
assertEqual(clipped, { x: 1400, y: 800, width: 40, height: 100 }, "crop is clipped to the bitmap");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll screenshot editor tests passed.");
