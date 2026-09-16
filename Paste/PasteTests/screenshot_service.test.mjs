// Mirrors ScreenshotService so CI / Linux agents can check the capture rules without
// Xcode: which screencapture flags each mode passes, how an exit status plus the
// output file classify the attempt, and what the history payload looks like for the
// two purposes — plain capture keeps the image, 识字 keeps only the text.

const MODES = ["region", "window", "fullScreen"];

const SUBTITLE = {
  region: "区域截图",
  window: "窗口截图",
  fullScreen: "整屏截图"
};

// Mirrors ScreenshotMode.arguments(output:).
function argumentsFor(mode, output) {
  switch (mode) {
    case "region":
      return ["-i", "-t", "png", output];
    case "window":
      return ["-i", "-W", "-t", "png", output];
    case "fullScreen":
      return ["-m", "-t", "png", output];
    default:
      throw new Error(`unknown mode ${mode}`);
  }
}

// Mirrors ScreenshotService.finish: an empty/missing file means the capture produced
// nothing, which is a cancel when we hold the permission and a permission problem
// when we do not. Esc exits with 1, so only other non-zero statuses are real errors.
function outcome({ status, bytes, hasPermission }) {
  if (bytes > 0) return "captured";
  if (!hasPermission) return "permission";
  if (status !== 0 && status !== 1) return "failed";
  return "cancelled";
}

function characterCount(text) {
  return [...text].filter((c) => !/\s/u.test(c)).length;
}

// Mirrors ContentTypeDetector.detect for the 识字 result.
function detect(text) {
  const trimmed = text.trim();
  if (/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(trimmed)) return "color";
  if (/^(https?:\/\/|www\.)\S+$/i.test(trimmed) && !trimmed.includes("\n")) return "link";
  if (trimmed.length > 120 || trimmed.includes("\n")) return "snippet";
  return "text";
}

// Mirrors ScreenshotService.payload: a plain capture is an image item and nothing
// else — OCR never runs, so there is no text to carry.
function payload(mode, { width, height, bytes }) {
  return {
    contentType: "image",
    plainText: null,
    previewTitle: `截图 ${width}×${height}`,
    previewSubtitle: SUBTITLE[mode],
    sourceAppName: "截图",
    sourceAppBundleID: null,
    hasThumbnail: bytes > 0
  };
}

// Mirrors ScreenshotService.textPayload: a 识字 capture keeps only the words. The
// image is discarded, and normal type detection still applies to the text.
function textPayload(mode, text) {
  const type = detect(text);
  return {
    contentType: type,
    plainText: text,
    imageData: null,
    previewTitle: text.trim().split("\n")[0].slice(0, 80),
    previewSubtitle: `截图识字 · ${characterCount(text)} 字`,
    sourceAppName: "截图识字",
    hasThumbnail: false
  };
}

// Mirrors ScreenshotService.hudDetail (识字 mode; plain mode just says 图片已复制).
function hudDetail(text) {
  if (!text) return "未识别到文字";
  return `已识别 ${characterCount(text)} 字，文字已复制`;
}

// The pasteboard contents per purpose: a plain capture offers the image, a 识字
// capture offers only the string.
function pasteboardTypes(purpose) {
  return purpose === "text" ? ["string"] : ["tiff", "png"];
}

// Mirrors ClipboardItem.searchableText. A plain capture is found by 截图 / 图片 /
// its size; a 识字 capture is found by the words inside it.
function searchableText(p) {
  const parts = [p.previewTitle, p.previewSubtitle];
  if (p.plainText) parts.push(p.plainText);
  parts.push(p.sourceAppName, p.contentType === "image" ? "图片" : null);
  return parts.filter(Boolean).join("\n");
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

const OUT = "/tmp/PasteNest-Screenshot-ABC.png";

assertEqual(argumentsFor("region", OUT), ["-i", "-t", "png", OUT], "region captures interactively");
assertEqual(argumentsFor("window", OUT), ["-i", "-W", "-t", "png", OUT], "window starts in window mode");
assertEqual(argumentsFor("fullScreen", OUT), ["-m", "-t", "png", OUT], "full screen stays on the main display");

// Every mode must write exactly one file at the path we later read.
for (const mode of MODES) {
  const args = argumentsFor(mode, OUT);
  assertEqual(args[args.length - 1], OUT, `${mode} writes to the requested path`);
  assertTrue(args.includes("-t") && args[args.indexOf("-t") + 1] === "png", `${mode} asks for png`);
}
// -m would be ignored during interactive selection, so only full screen passes it.
assertTrue(!argumentsFor("region", OUT).includes("-m"), "region does not pass -m");
assertTrue(!argumentsFor("fullScreen", OUT).includes("-i"), "full screen is not interactive");

assertEqual(
  outcome({ status: 0, bytes: 52_480, hasPermission: true }),
  "captured",
  "a written file is a capture"
);
assertEqual(
  outcome({ status: 1, bytes: 0, hasPermission: true }),
  "cancelled",
  "esc during selection is a silent cancel"
);
assertEqual(
  outcome({ status: 0, bytes: 0, hasPermission: true }),
  "cancelled",
  "no file with a clean exit is still a cancel"
);
assertEqual(
  outcome({ status: 1, bytes: 0, hasPermission: false }),
  "permission",
  "missing screen recording access is reported, not swallowed"
);
assertEqual(
  outcome({ status: -1, bytes: 0, hasPermission: true }),
  "failed",
  "a launch failure surfaces an error"
);
// A capture that succeeded must never be downgraded by a stray exit status.
assertEqual(
  outcome({ status: 1, bytes: 1_024, hasPermission: false }),
  "captured",
  "pixels win over status and permission"
);

// --- Plain capture: image only, OCR never runs --------------------------------
const shot = payload("region", { width: 1920, height: 1080, bytes: 52_480 });
assertEqual(shot.contentType, "image", "plain captures are image items");
assertEqual(shot.plainText, null, "a plain capture carries no text");
assertEqual(shot.previewTitle, "截图 1920×1080", "title carries the pixel size");
assertEqual(shot.previewSubtitle, "区域截图", "subtitle names the mode");
assertEqual(shot.sourceAppName, "截图", "source label marks it as a capture");
assertTrue(shot.hasThumbnail, "captures get a shelf thumbnail");

const shotText = searchableText(shot);
assertTrue(shotText.includes("截图"), "searchable by 截图");
assertTrue(shotText.includes("图片"), "searchable by 图片");
assertTrue(shotText.includes("1920"), "searchable by pixel size");

// --- 识字 capture: text only, image discarded ----------------------------------
const ocr = textPayload("region", "安静、好用的 Mac 工具。\n岸上工作室");
assertEqual(ocr.contentType, "snippet", "multi-line recognized text is a snippet");
assertEqual(ocr.plainText, "安静、好用的 Mac 工具。\n岸上工作室", "the words are the whole item");
assertEqual(ocr.imageData, null, "the image is not kept");
assertEqual(ocr.previewSubtitle, "截图识字 · 17 字", "subtitle reports the recognized length");
assertEqual(ocr.sourceAppName, "截图识字", "source label marks it as recognized text");
assertTrue(!ocr.hasThumbnail, "no thumbnail without an image");
assertTrue(searchableText(ocr).includes("好用的"), "searchable by the recognized words");
assertTrue(searchableText(ocr).includes("截图识字"), "searchable by 截图识字");

// Type detection still applies: a recognized URL becomes a link item.
assertEqual(textPayload("region", "https://example.com/docs").contentType, "link", "a recognized URL is a link");
assertEqual(textPayload("region", "#0F766E").contentType, "color", "a recognized hex is a color");
assertEqual(textPayload("region", "短句").contentType, "text", "a short line is plain text");

assertEqual(hudDetail("安静好用"), "已识别 4 字，文字已复制", "a result reports its length");
assertEqual(hudDetail(null), "未识别到文字", "an empty result says so and saves nothing");

assertEqual(pasteboardTypes("image"), ["tiff", "png"], "a plain capture offers the image");
assertEqual(pasteboardTypes("text"), ["string"], "a 识字 capture offers only the text");

// --- 下载截图: file naming -----------------------------------------------------
// Mirrors ScreenshotService.downloadFileName and uniqueURL: a timestamped PNG in
// 下载, and a numeric suffix rather than an overwrite when the name is taken.
function downloadFileName(date) {
  const p = (n) => String(n).padStart(2, "0");
  const stamp = `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())} ${p(date.getHours())}.${p(date.getMinutes())}.${p(date.getSeconds())}`;
  return `PasteNest 截图 ${stamp}.png`;
}
function uniqueName(existing, name) {
  const dot = name.lastIndexOf(".");
  const base = name.slice(0, dot);
  const ext = name.slice(dot + 1);
  let candidate = name;
  let counter = 2;
  while (existing.has(candidate)) {
    candidate = `${base} ${counter}.${ext}`;
    counter += 1;
  }
  return candidate;
}
const when = new Date(2026, 8, 16, 10, 12, 3);
assertEqual(downloadFileName(when), "PasteNest 截图 2026-09-16 10.12.03.png", "download name carries a sortable timestamp");
assertEqual(uniqueName(new Set(), "a.png"), "a.png", "a free name is used as is");
assertEqual(uniqueName(new Set(["a.png"]), "a.png"), "a 2.png", "a taken name gets a suffix");
assertEqual(uniqueName(new Set(["a.png", "a 2.png"]), "a.png"), "a 3.png", "the suffix keeps counting");

// --- the action bar after a capture --------------------------------------------
// Mirrors ScreenshotActionBar.position: hang below the anchor, clamped on screen,
// flipping above the anchor when there is no room below.
function positionBar({ anchor, visible, size }) {
  let x = anchor.x - size.width / 2;
  let y = anchor.y - size.height - 14;
  x = Math.min(Math.max(x, visible.minX + 8), visible.maxX - size.width - 8);
  if (y < visible.minY + 8) {
    y = Math.min(anchor.y + 14, visible.maxY - size.height - 8);
  }
  return { x, y };
}
const screen = { minX: 0, minY: 0, maxX: 1440, maxY: 875 };
const barSize = { width: 372, height: 58 };
let pos = positionBar({ anchor: { x: 700, y: 400 }, visible: screen, size: barSize });
assertEqual(pos, { x: 514, y: 328 }, "bar hangs centered below the pointer");
pos = positionBar({ anchor: { x: 20, y: 400 }, visible: screen, size: barSize });
assertEqual(pos.x, 8, "bar is kept inside the left edge");
pos = positionBar({ anchor: { x: 1430, y: 400 }, visible: screen, size: barSize });
assertEqual(pos.x, 1440 - 372 - 8, "bar is kept inside the right edge");
pos = positionBar({ anchor: { x: 700, y: 30 }, visible: screen, size: barSize });
assertEqual(pos.y, 44, "no room below: bar sits above the pointer");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll screenshot service tests passed.");
