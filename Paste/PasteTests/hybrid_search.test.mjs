const STOPWORDS = new Set([
  "the", "and", "or", "of", "to", "in", "for", "a", "an", "is", "it", "on", "at",
  "的", "了", "和", "与", "在", "是"
]);

function isCJK(ch) {
  const code = ch.codePointAt(0);
  return (
    (code >= 0x3040 && code <= 0x30ff) ||
    (code >= 0x3400 && code <= 0x4dbf) ||
    (code >= 0x4e00 && code <= 0x9fff) ||
    (code >= 0xac00 && code <= 0xd7af) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0x20000 && code <= 0x2a6df)
  );
}

function isPunctOrSymbol(ch) {
  if (ch === "_") return false;
  return /[\s\p{P}\p{S}]/u.test(ch);
}

function tokens(raw) {
  const trimmed = raw.trim();
  if (!trimmed) return [];
  const out = [];
  let latin = "";
  let cjk = "";
  const flushLatin = () => {
    const token = latin.toLowerCase();
    latin = "";
    if (token) out.push(token);
  };
  const flushCJK = () => {
    const token = cjk.toLowerCase();
    cjk = "";
    if (token) out.push(token);
  };
  for (const ch of trimmed) {
    if (ch === "_") {
      flushCJK();
      latin += ch;
    } else if (isPunctOrSymbol(ch)) {
      flushLatin();
      flushCJK();
    } else if (isCJK(ch)) {
      flushLatin();
      cjk += ch;
    } else {
      flushCJK();
      latin += ch;
    }
  }
  flushLatin();
  flushCJK();
  if (out.length > 1) {
    const filtered = out.filter((t) => !STOPWORDS.has(t));
    if (filtered.length) return filtered;
  }
  return out.length ? out : [trimmed.toLowerCase()];
}

function score(query, doc) {
  const folded = query.trim().toLowerCase();
  if (!folded) return 0;
  const queryTokens = tokens(folded);
  if (!queryTokens.length) return 0;
  const fields = [
    [doc.title.toLowerCase(), 1.3],
    [(doc.subtitle ?? "").toLowerCase(), 0.9],
    [(doc.body ?? "").toLowerCase(), 1.0],
    [(doc.source ?? "").toLowerCase(), 0.6],
    [(doc.tag ?? "").toLowerCase(), 0.8]
  ];
  const haystack = fields.map(([text]) => text).filter(Boolean).join(" ");
  let total = 0;
  let hits = 0;
  for (const token of queryTokens) {
    let tokenScore = 0;
    for (const [text, weight] of fields) {
      if (text && text.includes(token)) tokenScore += weight;
    }
    if (tokenScore > 0) {
      hits += 1;
      total += tokenScore;
    }
  }
  if (hits === 0) return 0;
  if (hits === queryTokens.length) total *= 1.4;
  if (haystack.includes(folded)) total += 2.0;
  if (isIdentifier(folded)) {
    const words = haystack.split(/[\s\p{P}]+/u).filter(Boolean);
    if (words.includes(folded)) total += 3.0;
  }
  return total;
}

function isIdentifier(query) {
  return query.length >= 2 && !/\s/.test(query) && /^[0-9a-z_]+$/i.test(query);
}

const SECRET_MARKERS = [
  "password", "passwd", "secret", "api_key", "apikey", "auth_token",
  "access_token", "private_key", "-----begin", "bearer ", "otpauth", "totp"
];

function shouldSkipEmbedding(text) {
  const trimmed = text.trim();
  if (!trimmed) return true;
  const lowered = trimmed.toLowerCase();
  if (SECRET_MARKERS.some((m) => lowered.includes(m))) return true;
  if (looksLikeJWT(trimmed)) return true;
  if (looksLikeHighEntropySecret(trimmed)) return true;
  return false;
}

function looksLikeJWT(text) {
  return text.split(".").length === 3 && (text.startsWith("eyJ") || text.startsWith("eyj"));
}

function looksLikeHighEntropySecret(text) {
  const compact = text.replace(/\s+/g, "");
  if (compact.length < 40 || compact.length > 512) return false;
  if (!/^[A-Za-z0-9_=-]+$/.test(compact)) return false;
  if (compact.includes("://")) return false;
  return new Set(compact.toLowerCase()).size >= 16;
}

function fuse(hits) {
  const maxKeyword = Math.max(0, ...hits.map((h) => h.keyword));
  return hits
    .map((h) => {
      const keyword = maxKeyword > 0 ? h.keyword / maxKeyword : 0;
      return { id: h.id, score: keyword + h.semantic + (h.phrase ? 2 : 0) };
    })
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id))
    .map((h) => h.id);
}

let failed = 0;
function assertEqual(actual, expected, name) {
  if (actual !== expected) {
    console.error(`FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    failed += 1;
  } else {
    console.log(`PASS ${name}`);
  }
}

function assertTrue(cond, name) {
  assertEqual(Boolean(cond), true, name);
}

assertEqual(tokens("zoom 会议").join(","), "zoom,会议", "tokenize mixed query");
assertEqual(tokens("the meeting link").join(","), "meeting,link", "drop english stopwords");
assertEqual(tokens("content_hash").join(","), "content_hash", "keep underscore identifiers");

const codeDoc = {
  title: "func greet(_ name: String)",
  subtitle: "4 行 · Xcode",
  body: "import Foundation\nfunc greet(_ name: String) {\n  print(\"Hello\")\n}",
  source: "Xcode",
  tag: "代码"
};
const meetingDoc = {
  title: "明天下午三点同步剪贴板方案",
  subtitle: "Notes",
  body: "明天下午三点同步剪贴板方案，优先做搜索与置顶。",
  source: "Notes",
  tag: "文本"
};
const linkDoc = {
  title: "developer.apple.com/documentation/swiftdata",
  subtitle: "Safari",
  body: "https://developer.apple.com/documentation/swiftdata",
  source: "Safari",
  tag: "链接"
};

assertTrue(score("greet", codeDoc) > 0, "keyword hits function name");
assertTrue(score("zoom 会议", meetingDoc) === 0, "AND requires every token");
assertTrue(score("同步 置顶", meetingDoc) > 0, "Chinese tokens all present");
assertTrue(score("Safari", linkDoc) > score("Safari", codeDoc), "source field can rank");
assertTrue(score("func greet", codeDoc) > score("Xcode", codeDoc), "phrase bonus beats source-only");

assertTrue(shouldSkipEmbedding("password=hunter2"), "skip password marker");
assertTrue(shouldSkipEmbedding("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaa.bbb"), "skip jwt");
assertTrue(
  shouldSkipEmbedding("n1K9sP2vQ8wX4yZ7aB3cD6eF0gH5jL1mN8pR2tU4vW6xY"),
  "skip high-entropy token"
);
assertTrue(!shouldSkipEmbedding("https://developer.apple.com/documentation/swiftdata"), "keep urls");
assertTrue(!shouldSkipEmbedding(codeDoc.body), "keep code");

const fused = fuse([
  { id: "exact", keyword: 5, semantic: 0.2, phrase: true },
  { id: "semantic", keyword: 0, semantic: 0.82, phrase: false },
  { id: "weak", keyword: 0.1, semantic: 0.4, phrase: false }
]);
assertEqual(fused[0], "exact", "exact phrase stays first");
assertTrue(fused.indexOf("semantic") < fused.indexOf("weak"), "strong semantic outranks weak keyword");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll hybrid search tests passed.");
