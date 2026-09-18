// Mirrors TextRecognizer's post-processing so CI / Linux agents can check it without
// Vision: Vision hands back unordered line observations in normalized coordinates
// (origin bottom-left), and we rebuild reading order from them.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const lineTolerance = 0.014;

const CJK_RANGES = [
  [0x3000, 0x303f],
  [0x3400, 0x4dbf],
  [0x4e00, 0x9fff],
  [0xf900, 0xfaff],
  [0xff00, 0xffef]
];

function isCJK(character) {
  if (!character) return false;
  const code = character.codePointAt(0);
  return CJK_RANGES.some(([low, high]) => code >= low && code <= high);
}

function joinFragments(pieces) {
  if (!pieces.length) return "";
  let result = pieces[0];
  for (const piece of pieces.slice(1)) {
    const bothCJK = isCJK(result[result.length - 1]) && isCJK(piece[0]);
    result += bothCJK ? piece : ` ${piece}`;
  }
  return result;
}

function assemble(fragments) {
  if (!fragments.length) return null;

  const ordered = [...fragments].sort((a, b) => {
    // Larger y is higher on screen, so descending y is top to bottom.
    if (Math.abs(a.midY - b.midY) > lineTolerance) return b.midY - a.midY;
    return a.minX - b.minX;
  });

  const lines = [];
  for (const fragment of ordered) {
    const current = lines[lines.length - 1];
    const last = current && current[current.length - 1];
    if (last && Math.abs(last.midY - fragment.midY) <= lineTolerance) {
      current.push(fragment);
    } else {
      lines.push([fragment]);
    }
  }

  const text = lines
    .map((line) => joinFragments(line.map((f) => f.text)))
    .join("\n")
    .trim();
  return text === "" ? null : text;
}

function characterCount(text) {
  return [...text].filter((c) => !/\s/u.test(c)).length;
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

const frag = (text, midY, minX) => ({ text, midY, minX });

assertEqual(assemble([]), null, "no observations means no text");

// Vision's order is not guaranteed, so a bottom line handed to us first must still
// come out last.
assertEqual(
  assemble([frag("第二行", 0.3, 0.1), frag("第一行", 0.7, 0.1)]),
  "第一行\n第二行",
  "lines are ordered top to bottom"
);

// Two observations on one visual line join into that line, left to right.
assertEqual(
  assemble([frag("好用的 Mac 工具。", 0.5, 0.45), frag("安静、", 0.502, 0.1)]),
  "安静、好用的 Mac 工具。",
  "same-line fragments join left to right without a CJK space"
);
assertEqual(
  assemble([frag("world", 0.5, 0.4), frag("hello", 0.5, 0.1)]),
  "hello world",
  "latin fragments keep their space"
);
assertEqual(
  joinFragments(["岸上", "PasteStack"]),
  "岸上 PasteStack",
  "a CJK/latin boundary keeps a space"
);
assertEqual(joinFragments(["单独一段"]), "单独一段", "a lone fragment is unchanged");

// Just inside and just outside the tolerance.
assertEqual(
  assemble([frag("B", 0.5, 0.5), frag("A", 0.51, 0.1)]),
  "A B",
  "a 0.01 gap is still one line"
);
assertEqual(
  assemble([frag("B", 0.5, 0.5), frag("A", 0.53, 0.1)]),
  "A\nB",
  "a 0.03 gap splits into two lines"
);

// Three lines arriving shuffled, each with two fragments.
assertEqual(
  assemble([
    frag("iCloud 里。", 0.30, 0.55),
    frag("我们做常驻菜单栏", 0.62, 0.30),
    frag("数据留在你自己的设备和", 0.30, 0.10),
    frag("岸上是一家独立工作室。", 0.62, 0.10),
    frag("第一款应用是", 0.10, 0.10)
  ]),
  "岸上是一家独立工作室。我们做常驻菜单栏\n数据留在你自己的设备和 iCloud 里。\n第一款应用是",
  "shuffled multi-line block rebuilds in reading order"
);

assertTrue(isCJK("安"), "han character is CJK");
assertTrue(isCJK("。"), "fullwidth punctuation is CJK");
assertTrue(!isCJK("M"), "latin letter is not CJK");
assertTrue(!isCJK(undefined), "missing character is not CJK");

assertEqual(characterCount("安静、好用的 Mac 工具。"), 12, "whitespace is not counted");
assertEqual(characterCount("a\nb c"), 3, "newlines are not counted");

function preparedScale(minSide, target = 320) {
  if (!(minSide > 0) || minSide >= target) return 1;
  return Math.min(4, Math.max(2, Math.ceil(target / minSide)));
}
assertEqual(preparedScale(966), 1, "a Retina UI crop is not upscaled");
assertEqual(preparedScale(442), 1, "a tall Retina crop stays 1x");
assertEqual(preparedScale(80), 4, "a tiny crop is scaled up to the 320px target, capped at 4x");
assertEqual(preparedScale(184), 2, "a 159×92@2x crop (184px tall) is doubled");
assertEqual(preparedScale(320), 1, "a crop on the minimum side is left as-is");

function cjkCount(text) {
  return [...text].filter((c) => isCJK(c)).length;
}

function isGarbled(text, confidence) {
  const letters = [...text].filter((c) => !/\s/.test(c));
  if (!letters.length) return true;
  const cjk = cjkCount(text);
  if (cjk >= 3) return false;
  if (cjk === 0 && confidence >= 0.55) return false;
  if (cjk === 0 && confidence < 0.4) return true;
  const allowed = ".,:;/\\-_()[]（）【】「」\"'、。";
  const weird = letters.filter((c) => {
    if (isCJK(c)) return false;
    if (/^[A-Za-z0-9]$/.test(c)) return false;
    return !allowed.includes(c);
  }).length;
  if (cjk === 0 && weird >= 2 && confidence < 0.55) return true;
  if (cjk === 0 && letters.length >= 6 && weird / letters.length >= 0.15) return true;
  return false;
}

function scoreCandidate(text, confidence) {
  return confidence * 10 + cjkCount(text) * 2 + Math.min(characterCount(text), 40) * 0.1;
}

function pickBest(candidates) {
  const ok = candidates.filter((c) => !isGarbled(c.text, c.confidence));
  if (!ok.length) return null;
  ok.sort((a, b) => scoreCandidate(b.text, b.confidence) - scoreCandidate(a.text, a.confidence));
  return ok[0].text;
}

assertTrue(isGarbled("iA5F;XfflIJ# (¥", 0.32), "fast Latin soup on a Chinese crop is garbled");
assertTrue(!isGarbled("零售服务体验印象\n调研激励券（总部使用）", 0.51), "real CJK is not garbled");
assertTrue(!isGarbled("Hello world", 0.72), "confident English is not garbled");
assertTrue(!isGarbled("OK", 0.8), "a short confident token is kept");
assertEqual(
  pickBest([
    { text: "iA5F;XfflIJ# (¥", confidence: 0.32 },
    { text: "零售服务体验印象\n调研激励券（总部使用）", confidence: 0.51 }
  ]),
  "零售服务体验印象\n调研激励券（总部使用）",
  "a later accurate CJK pass wins over fast garbage"
);
assertEqual(
  pickBest([{ text: "iA5F;XfflIJ# (¥", confidence: 0.32 }]),
  null,
  "garbage-only results are discarded rather than shown"
);

const DARK_LUMINANCE_THRESHOLD = 0.45;

function luminance(r, g, b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

function meanLuminance(pixels) {
  if (!pixels.length) return 0;
  return pixels.reduce((sum, p) => sum + luminance(p.r, p.g, p.b), 0) / pixels.length;
}

function isDark(mean) {
  return mean < DARK_LUMINANCE_THRESHOLD;
}

function invertRGB(pixel) {
  return { r: 255 - pixel.r, g: 255 - pixel.g, b: 255 - pixel.b, a: pixel.a };
}

function ocrCandidateOrder(dark) {
  return dark ? ["inverted", "original"] : ["original", "inverted"];
}

assertTrue(isDark(luminance(20, 20, 24)), "a terminal-dark pixel is dark");
assertTrue(!isDark(luminance(245, 245, 247)), "a paper-white pixel is not dark");
assertTrue(
  isDark(meanLuminance(Array.from({ length: 16 }, () => ({ r: 30, g: 30, b: 32 })))),
  "a dark 16-sample probe is dark"
);
assertTrue(
  !isDark(meanLuminance(Array.from({ length: 16 }, () => ({ r: 242, g: 244, b: 247 })))),
  "a light 16-sample probe is not dark"
);
assertEqual(
  invertRGB({ r: 0, g: 0, b: 0, a: 255 }),
  { r: 255, g: 255, b: 255, a: 255 },
  "black inverts to white and keeps alpha"
);
assertEqual(
  invertRGB({ r: 200, g: 200, b: 200, a: 255 }),
  { r: 55, g: 55, b: 55, a: 255 },
  "light glyphs invert to dark ink and keep alpha"
);
assertEqual(ocrCandidateOrder(true), ["inverted", "original"], "dark UI tries inverted first");
assertEqual(ocrCandidateOrder(false), ["original", "inverted"], "light UI tries the freeze first");

const swift = fs.readFileSync(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste/Services/TextRecognizer.swift"),
  "utf8"
);
assertTrue(/func recognize\(cgImage: CGImage\)/.test(swift), "overlay OCR can skip the PNG round-trip");
assertTrue(/func recognize\(preparedCGImage: CGImage\)/.test(swift), "Vision can run on a bitmap copied off the freeze");
assertTrue(/func preparedImage\(from image: CGImage\)/.test(swift), "ScreenCaptureKit crops are copied into a disconnected sRGB bitmap");
assertTrue(/CGColorSpace\.sRGB/.test(swift) && /premultipliedLast/.test(swift), "prepared OCR bitmaps are 8-bit sRGB RGBA");
assertTrue(/byteOrder32Big/.test(swift), "RGBA byte order is explicit so invert does not flip alpha");
assertTrue(/minimumPreparedSide = 320/.test(swift), "tiny UI crops are upscaled toward 320px before Vision");
assertTrue(/minimumFragmentConfidence: Float = 0\.3/.test(swift), "low-confidence Vision guesses are dropped");
assertTrue(/func isGarbled/.test(swift), "Latin soup from .fast is classified as garbled");
assertTrue(/func preparedScale\(minSide:/.test(swift), "upscale factor is derived from the short side");
assertTrue(/func cjkCount\(of text: String\)/.test(swift), "garbled detection counts Han characters");
assertTrue(/\.accurate, languages/.test(swift), "accurate CJK recognition is tried before .fast");
assertTrue(/candidate\.confidence >= minimumFragmentConfidence/.test(swift), "each line keeps its Vision confidence");
assertTrue(/best\.isGarbled/.test(swift), "a garbled winner is discarded");
assertTrue(/darkLuminanceThreshold: CGFloat = 0\.45/.test(swift), "dark UI is anything dimmer than mid-gray");
assertTrue(/func invertedImage\(from image: CGImage\)/.test(swift), "light-on-dark crops can be inverted for Vision");
assertTrue(/func isDark\(_ image: CGImage\)/.test(swift), "darkness is measured from the freeze itself");
assertTrue(/invertRGBKeepingAlpha/.test(swift), "inversion keeps alpha so the bitmap stays opaque");
assertTrue(/255 &- pixel\[0\]/.test(swift), "each RGB channel is inverted independently");
assertTrue(/isDark\(preparedCGImage\), let inverted/.test(swift), "a dark freeze tries the inverted bitmap first");
assertTrue(/images = \[preparedCGImage, inverted\]/.test(swift), "a light freeze still falls back to inverted");
assertTrue(/VNImageRequestHandler\(cgImage:/.test(swift), "Vision reads the cropped CGImage directly");
assertTrue(/recognitionLevel = level/.test(swift) && /\.accurate/.test(swift), "accurate recognition is in the overlay OCR loop");
assertTrue(/minimumTextHeight = \(level == \.fast\) \? 0 : 0\.008/.test(swift), "fast OCR does not drop small UI labels");
assertTrue(/automaticallyDetectsLanguage = true/.test(swift), "a language-pack miss still falls back to auto-detect");
assertTrue(/import ImageIO/.test(swift), "PNG history items decode through ImageIO before Vision");

const overlay = fs.readFileSync(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste/Views/ScreenshotOverlay.swift"),
  "utf8"
);
assertTrue(
  /TextRecognizer\.preparedImage\(from: cropped\)/.test(overlay),
  "the overlay copies the crop off the IOSurface before leaving the main thread"
);
assertTrue(
  /TextRecognizer\.recognize\(preparedCGImage: prepared\)/.test(overlay),
  "the overlay recognizes the prepared freeze pixels, not a re-encoded PNG"
);
assertTrue(
  !/TextRecognizer\.recognize\(cgImage: cropped\)/.test(overlay),
  "overlay OCR no longer hands Vision the live freeze crop"
);
assertTrue(
  !/TextRecognizer\.recognize\(imageData: data\)/.test(overlay),
  "overlay OCR no longer PNG-encodes the crop first"
);
assertTrue(/ocrPanelUsesLightAppearance/.test(overlay), "OCR card forces aqua so text is not white-on-white");
assertTrue(/ocrPanelTextColorHex/.test(overlay), "OCR ink is an explicit dark color, not labelColor");
assertTrue(/preferredColorScheme\(\.light\)/.test(overlay), "OCR card stays in light color scheme");
assertTrue(/ScreenshotL10n\.string\(\.ocrWorking\)/.test(overlay), "recognizing state has visible copy, not only a spinner");
assertTrue(/\.textSelection\(\.enabled\)/.test(overlay), "recognized text is selectable SwiftUI Text, not NSTextView");
assertTrue(/onCopy\(session\.ocrResult \?\? ""\)/.test(overlay), "the Copy button copies the full recognized string");
assertTrue(/onCancel\?\(\)\n        ScreenshotHUD/.test(overlay), "copying recognized text closes the overlay then shows a HUD");
assertTrue(!/copyOCRText[\s\S]{0,400}onConfirm/.test(overlay), "OCR copy does not confirm a PNG that would overwrite the text");
assertTrue(!/class ScreenshotOCRScrollView/.test(overlay), "OCR no longer hosts an AppKit text view on the flipped freeze");
assertTrue(!/struct ScreenshotOCRTextView/.test(overlay), "OCR result is not an NSViewRepresentable");
assertTrue(!/textColor = \.labelColor/.test(overlay), "OCR text view does not use appearance-adaptive labelColor");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll text recognizer tests passed.");
