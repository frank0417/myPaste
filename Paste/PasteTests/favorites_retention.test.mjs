// Mirrors RetentionPolicy and FavoriteTagCatalog so CI / Linux agents can check the
// rules that decide what survives: favorites are the long-term library, everything
// else expires, and the folder's categories are normalized strings.

const DAY = 24 * 60 * 60 * 1000;

const RETENTION = { defaultDays: 3, minimumDays: 1, maximumDays: 30 };

function clampDays(days) {
  return Math.min(Math.max(days, RETENTION.minimumDays), RETENTION.maximumDays);
}

function isProtected(item) {
  return Boolean(item.isFavorite || item.isPinned);
}

function cutoff(days, now) {
  return now - clampDays(days) * DAY;
}

function expiry(lastUsed, days) {
  return lastUsed + clampDays(days) * DAY;
}

// Mirrors RetentionPolicy.isExpired and the store's sweep predicate.
function isExpired(item, days, now) {
  if (isProtected(item)) return false;
  return item.lastUsed < cutoff(days, now);
}

function statusText(item, days, now) {
  if (item.isFavorite) return "已收藏 · 长期保存";
  if (item.isPinned) return "已置顶 · 长期保存";
  const remaining = expiry(item.lastUsed, days) - now;
  if (remaining <= 0) return "已过期 · 即将自动清理";
  if (remaining < DAY) return "不到 1 天后自动清理，收藏可长期保存";
  return `${Math.floor(remaining / DAY)} 天后自动清理，收藏可长期保存`;
}

function isExpiringSoon(item, days, now) {
  if (isProtected(item)) return false;
  return expiry(item.lastUsed, days) - now < DAY;
}

// Mirrors ClipboardStore.enforceRetention: the sweep only ever removes unprotected,
// aged-out items.
function sweep(items, days, now) {
  return items.filter((item) => !isExpired(item, days, now));
}

// Mirrors ClipboardStore.enforceHistoryLimit: favorites and pins do not count against
// the cap, so keeping something can never push it out of the cap either.
function enforceLimit(items, limit) {
  const capped = items.filter((item) => !item.isPinned && !item.isFavorite);
  const dropped = new Set(
    capped
      .slice()
      .sort((a, b) => b.lastUsed - a.lastUsed)
      .slice(limit)
      .map((item) => item.id)
  );
  return items.filter((item) => !dropped.has(item.id));
}

const CATALOG = {
  maxTagsPerItem: 5,
  maxNameLength: 12,
  suggestions: ["工作", "灵感", "代码", "资料", "待办"],
  palette: ["#0D9488", "#EE6C4D", "#7C3AED", "#2563EB", "#F59E0B", "#059669", "#DB2777", "#3D5A80"]
};

// Mirrors FavoriteTagCatalog.normalize.
function normalize(raw) {
  const collapsed = raw.split(/\s+/u).filter(Boolean).join(" ");
  if (!collapsed) return null;
  return [...collapsed].slice(0, CATALOG.maxNameLength).join("");
}

function sanitize(tags) {
  const seen = new Set();
  const result = [];
  for (const tag of tags) {
    const name = normalize(tag);
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(name);
    if (result.length === CATALOG.maxTagsPerItem) break;
  }
  return result;
}

function adding(tag, tags) {
  const name = normalize(tag);
  return name ? sanitize([...tags, name]) : sanitize(tags);
}

function removing(tag, tags) {
  const name = normalize(tag);
  if (!name) return sanitize(tags);
  return sanitize(tags.filter((t) => normalize(t)?.toLowerCase() !== name.toLowerCase()));
}

function contains(tag, tags) {
  const name = normalize(tag)?.toLowerCase();
  if (!name) return false;
  return tags.some((t) => normalize(t)?.toLowerCase() === name);
}

function accentHex(tag) {
  const name = normalize(tag) ?? tag;
  const sum = [...name].reduce((total, c) => total + c.codePointAt(0), 0);
  return CATALOG.palette[Math.abs(sum) % CATALOG.palette.length];
}

// Mirrors FavoriteTagCatalog.counts: most used first, ties by name.
function counts(tagLists) {
  const tally = new Map();
  const display = new Map();
  for (const list of tagLists) {
    for (const tag of sanitize(list)) {
      const key = tag.toLowerCase();
      tally.set(key, (tally.get(key) ?? 0) + 1);
      if (!display.has(key)) display.set(key, tag);
    }
  }
  return [...tally.entries()]
    .map(([key, count]) => ({ name: display.get(key), count }))
    .sort((a, b) => (a.count !== b.count ? b.count - a.count : a.name < b.name ? -1 : 1));
}

function unusedSuggestions(existing) {
  const used = new Set(existing.map((t) => normalize(t)?.toLowerCase()).filter(Boolean));
  return CATALOG.suggestions.filter((s) => !used.has(s.toLowerCase()));
}

// Mirrors ClipboardItemFilter.matchesHard for the folder: favorites only, then the
// active category chip.
function matchesFolder(item, scope) {
  if (!item.isFavorite) return false;
  if (scope.kind === "all") return true;
  if (scope.kind === "untagged") return sanitize(item.tags ?? []).length === 0;
  return contains(scope.name, item.tags ?? []);
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

const NOW = Date.parse("2026-09-15T12:00:00Z");
const plain = (lastUsedDaysAgo, extra = {}) => ({
  id: `i-${lastUsedDaysAgo}-${JSON.stringify(extra)}`,
  lastUsed: NOW - lastUsedDaysAgo * DAY,
  isFavorite: false,
  isPinned: false,
  ...extra
});

assertEqual(clampDays(0), 1, "a zero-day window is clamped to one day");
assertEqual(clampDays(365), 30, "an absurd window is clamped to a month");
assertEqual(clampDays(3), 3, "the default window passes through");

// The core promise: only favorites (and pins) outlive the window.
assertTrue(!isExpired(plain(2), 3, NOW), "a two-day-old record still fits in a three-day window");
assertTrue(isExpired(plain(4), 3, NOW), "a four-day-old record is out");
assertTrue(!isExpired(plain(400, { isFavorite: true }), 3, NOW), "favorites never expire");
assertTrue(!isExpired(plain(400, { isPinned: true }), 3, NOW), "pinned items never expire");
assertTrue(isExpired(plain(4, { isFavorite: false }), 3, NOW), "un-favoriting exposes an old record");
// Exactly at the boundary the item is kept — expiry is strictly older than the cutoff.
assertTrue(!isExpired(plain(3), 3, NOW), "the item is kept right at the boundary");

// Age counts from the last use, so re-pasting something keeps it alive.
const reused = plain(9, {});
reused.lastUsed = NOW - 0.5 * DAY;
assertTrue(!isExpired(reused, 3, NOW), "using an old record restarts its window");

const history = [
  plain(0),
  plain(2),
  plain(5),
  plain(10, { isFavorite: true }),
  plain(20, { isPinned: true }),
  plain(31, { isFavorite: true, isPinned: true })
];
const kept = sweep(history, 3, NOW);
assertEqual(kept.length, 5, "the sweep drops only the aged-out plain record");
assertTrue(
  kept.every((item) => isProtected(item) || item.lastUsed >= cutoff(3, NOW)),
  "everything left is protected or inside the window"
);

// A long window keeps everything; a one-day window keeps only today's copies.
assertEqual(sweep(history, 30, NOW).length, 6, "a 30-day window keeps the whole history");
assertEqual(sweep(history, 1, NOW).length, 4, "a one-day window keeps today plus the protected ones");

assertEqual(statusText(plain(1, { isFavorite: true }), 3, NOW), "已收藏 · 长期保存", "favorites report as kept");
assertEqual(statusText(plain(1, { isPinned: true }), 3, NOW), "已置顶 · 长期保存", "pins report as kept");
assertEqual(statusText(plain(0), 3, NOW), "3 天后自动清理，收藏可长期保存", "a fresh copy reports the full window");
assertEqual(statusText(plain(1.2), 3, NOW), "1 天后自动清理，收藏可长期保存", "a partial day floors down");
assertEqual(
  statusText(plain(2.5), 3, NOW),
  "不到 1 天后自动清理，收藏可长期保存",
  "the last day is called out"
);
assertEqual(statusText(plain(4), 3, NOW), "已过期 · 即将自动清理", "an expired record says so");
assertTrue(isExpiringSoon(plain(2.5), 3, NOW), "the last day flags the card");
assertTrue(!isExpiringSoon(plain(2.5, { isFavorite: true }), 3, NOW), "a favorite is never flagged");

// Keeping something must not let the count cap delete it.
const overflow = [
  plain(0),
  plain(1),
  plain(2, { isFavorite: true }),
  plain(3, { isPinned: true }),
  plain(4)
];
const capped = enforceLimit(overflow, 2);
assertEqual(capped.length, 4, "the cap only counts unprotected records");
assertTrue(
  capped.some((item) => item.isFavorite) && capped.some((item) => item.isPinned),
  "the cap never removes a favorite or a pin"
);

assertEqual(normalize("  工作  "), "工作", "a category name is trimmed");
assertEqual(normalize("客户\n资料"), "客户 资料", "inner whitespace collapses to one space");
assertEqual(normalize("   "), null, "a blank name is rejected");
assertEqual(normalize("一二三四五六七八九十十一十二"), "一二三四五六七八九十十一", "a long name is cut to 12");

assertEqual(sanitize(["工作", "工作", " 工作 "]), ["工作"], "duplicates collapse");
assertEqual(sanitize(["Work", "work"]), ["Work"], "duplicates are case-insensitive");
assertEqual(
  sanitize(["a", "b", "c", "d", "e", "f"]),
  ["a", "b", "c", "d", "e"],
  "an item carries at most five categories"
);
assertEqual(adding("灵感", ["工作"]), ["工作", "灵感"], "adding keeps the existing order");
assertEqual(adding("  ", ["工作"]), ["工作"], "adding nothing changes nothing");
assertEqual(removing("工作", ["工作", "灵感"]), ["灵感"], "removing drops just that category");
assertEqual(removing("WORK", ["Work", "灵感"]), ["灵感"], "removing ignores case");
assertTrue(contains("工作", ["工作"]), "contains matches");
assertTrue(!contains("工作", ["灵感"]), "contains rejects other categories");

assertEqual(accentHex("工作"), accentHex(" 工作 "), "a category keeps one stable color");
assertTrue(CATALOG.palette.includes(accentHex("任意分类")), "colors come from the palette");

assertEqual(
  counts([["工作"], ["工作", "灵感"], [], ["灵感"], ["资料"]]),
  [
    { name: "工作", count: 2 },
    { name: "灵感", count: 2 },
    { name: "资料", count: 1 }
  ],
  "categories are counted, most used first"
);
assertEqual(unusedSuggestions(["工作", "代码"]), ["灵感", "资料", "待办"], "used defaults drop out of the menu");

const folder = [
  { isFavorite: true, tags: ["工作"] },
  { isFavorite: true, tags: [] },
  { isFavorite: false, tags: ["工作"] }
];
assertEqual(
  folder.filter((item) => matchesFolder(item, { kind: "all" })).length,
  2,
  "the folder shows favorites only"
);
assertEqual(
  folder.filter((item) => matchesFolder(item, { kind: "tag", name: "工作" })).length,
  1,
  "a category chip shows only favorites with that tag"
);
assertEqual(
  folder.filter((item) => matchesFolder(item, { kind: "untagged" })).length,
  1,
  "未分类 shows the favorites nobody filed"
);

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll favorites / retention tests passed.");
