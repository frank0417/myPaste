// Mirrors ScreenshotService so CI / Linux agents can check the capture rules without
// Xcode: which screencapture flags each mode passes, how an exit status plus the
// output file classify the attempt, and what the history payload looks like.

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

// Mirrors ScreenshotService.payload(mode:pngData:).
function payload(mode, { width, height, bytes }) {
  return {
    contentType: "image",
    previewTitle: `截图 ${width}×${height}`,
    previewSubtitle: SUBTITLE[mode],
    sourceAppName: "截图",
    sourceAppBundleID: null,
    hasThumbnail: bytes > 0
  };
}

// Mirrors ClipboardItem.searchableText for a screenshot: no plain text, so the title
// and source label are the only things a query can hit.
function searchableText(p) {
  return [p.previewTitle, p.previewSubtitle, p.sourceAppName, "图片"].join("\n");
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

const OUT = "/tmp/ClipStack-Screenshot-ABC.png";

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

const shot = payload("region", { width: 1920, height: 1080, bytes: 52_480 });
assertEqual(shot.contentType, "image", "screenshots are image items");
assertEqual(shot.previewTitle, "截图 1920×1080", "title carries the pixel size");
assertEqual(shot.previewSubtitle, "区域截图", "subtitle names the mode");
assertEqual(shot.sourceAppName, "截图", "source label marks it as a capture");
assertEqual(
  payload("fullScreen", { width: 3456, height: 2234, bytes: 1 }).previewSubtitle,
  "整屏截图",
  "full screen subtitle"
);
assertTrue(shot.hasThumbnail, "captures get a shelf thumbnail");

// Typing either word has to find a screenshot, since it has no text content at all.
const text = searchableText(shot);
assertTrue(text.includes("截图"), "searchable by 截图");
assertTrue(text.includes("图片"), "searchable by 图片");
assertTrue(text.includes("1920"), "searchable by pixel size");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll screenshot service tests passed.");
