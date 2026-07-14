#!/usr/bin/env node
// mine-history.mjs — E.2 Phase 1: stream QuickSay history files and mine raw-vs-cleaned divergences.
//
// Streams arbitrarily large history.json files (the legacy file is 1.6 GB) with a
// string-aware brace-depth scanner, so both formats parse: one-entry-per-line
// (legacy writer) and pretty-printed multi-line (history-core writer).
//
// Usage:
//   node mine-history.mjs --out <dir> <file1> [file2 ...]
//
// Privacy: output files contain raw dictation content. Write them ONLY to a
// local non-repo directory (--out). Never commit them.

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const outIdx = args.indexOf('--out');
if (outIdx === -1 || args.length < outIdx + 2) {
  console.error('usage: node mine-history.mjs --out <dir> <file...>');
  process.exit(1);
}
const outDir = args[outIdx + 1];
const files = args.filter((a, i) => i !== outIdx && i !== outIdx + 1);
fs.mkdirSync(outDir, { recursive: true });

// ---------------------------------------------------------------------------
// Streaming top-level-object extractor
// ---------------------------------------------------------------------------
class ObjectScanner {
  constructor(onObject) {
    this.onObject = onObject;
    this.depth = 0;
    this.inString = false;
    this.escape = false;
    this.buf = '';
    this.collecting = false;
    this.parseFailures = 0;
  }
  feed(chunk) {
    for (let i = 0; i < chunk.length; i++) {
      const c = chunk[i];
      if (this.collecting) this.buf += c;
      if (this.inString) {
        if (this.escape) { this.escape = false; }
        else if (c === '\\') { this.escape = true; }
        else if (c === '"') { this.inString = false; }
        continue;
      }
      if (c === '"') { this.inString = true; continue; }
      if (c === '{') {
        if (this.depth === 0) { this.collecting = true; this.buf = '{'; }
        this.depth++;
      } else if (c === '}') {
        this.depth--;
        if (this.depth === 0 && this.collecting) {
          this.collecting = false;
          try { this.onObject(JSON.parse(this.buf)); }
          catch { this.parseFailures++; }
          this.buf = '';
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Text normalization helpers
// ---------------------------------------------------------------------------
const CONTRACTIONS = new Map(Object.entries({
  "don't": 'do not', "doesn't": 'does not', "didn't": 'did not', "can't": 'can not',
  "cannot": 'can not', "won't": 'will not', "wouldn't": 'would not', "couldn't": 'could not',
  "shouldn't": 'should not', "isn't": 'is not', "aren't": 'are not', "wasn't": 'was not',
  "weren't": 'were not', "hasn't": 'has not', "haven't": 'have not', "hadn't": 'had not',
  "i'm": 'i am', "i've": 'i have', "i'll": 'i will', "i'd": 'i would',
  "you're": 'you are', "you've": 'you have', "you'll": 'you will', "you'd": 'you would',
  "we're": 'we are', "we've": 'we have', "we'll": 'we will', "we'd": 'we would',
  "they're": 'they are', "they've": 'they have', "they'll": 'they will',
  "it's": 'it is', "that's": 'that is', "there's": 'there is', "what's": 'what is',
  "let's": 'let us', "he's": 'he is', "she's": 'she is', "who's": 'who is',
  "gonna": 'going to', "wanna": 'want to', "gotta": 'got to', "kinda": 'kind of',
  "sorta": 'sort of', "'cause": 'because', "cuz": 'because',
}));
const NUMBER_WORDS = new Map(Object.entries({
  zero: '0', one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7',
  eight: '8', nine: '9', ten: '10', eleven: '11', twelve: '12', thirteen: '13',
  fourteen: '14', fifteen: '15', sixteen: '16', seventeen: '17', eighteen: '18',
  nineteen: '19', twenty: '20', thirty: '30', forty: '40', fifty: '50', sixty: '60',
  seventy: '70', eighty: '80', ninety: '90', hundred: '100', thousand: '1000',
}));

function tokenize(text) {
  let t = ' ' + String(text).toLowerCase() + ' ';
  for (const [k, v] of CONTRACTIONS) t = t.split(k).join(v);
  t = t.replace(/[^a-z0-9' ]+/g, ' ');
  const toks = [];
  for (let w of t.split(/\s+/)) {
    if (!w) continue;
    w = w.replace(/'/g, '');
    if (!w) continue;
    toks.push(NUMBER_WORDS.get(w) || w);
  }
  return toks;
}

// Filler bigrams removed as units before diffing; strict unigram fillers after.
const FILLER_BIGRAMS = [['you', 'know'], ['i', 'mean'], ['sort', 'of'], ['kind', 'of'], ['all', 'right']];
const FILLERS = new Set(['um', 'uh', 'uhm', 'er', 'ah', 'hmm', 'mhm', 'like', 'basically',
  'so', 'well', 'okay', 'ok', 'right', 'actually', 'yeah', 'alright', 'just', 'literally', 'and']);

function removeFillerBigrams(rawToks, cleanCounts) {
  // remove a filler bigram from raw only when the bigram doesn't survive in cleaned
  const out = [];
  for (let i = 0; i < rawToks.length; i++) {
    let matched = false;
    for (const [a, b] of FILLER_BIGRAMS) {
      if (rawToks[i] === a && rawToks[i + 1] === b &&
          !((cleanCounts.get(a) || 0) > 0 && (cleanCounts.get(b) || 0) > 0)) {
        i++; matched = true; break;
      }
    }
    if (!matched) out.push(rawToks[i]);
  }
  return out;
}

function counts(toks) {
  const m = new Map();
  for (const t of toks) m.set(t, (m.get(t) || 0) + 1);
  return m;
}
function multisetDiff(a, b) { // tokens in a beyond b
  const out = [];
  for (const [t, n] of a) { const d = n - (b.get(t) || 0); for (let i = 0; i < d; i++) out.push(t); }
  return out;
}

const ANSWER_LEAD = /^(yes|no|nope|yep|sure|okay|ok|of course|absolutely|certainly|definitely|great question|it depends|i (think|believe|would|will|can)('|\b))/i;
const TRAILING_ACK = /(^|[.!?]\s+)(yes|no|sure|okay|ok|yeah)[.!]?\s*$/i;
const QUESTION_LEAD = /^(who|what|when|where|why|how|which|is|are|am|was|were|can|could|should|would|will|shall|do|does|did|may|might|have|has)\b/i;
const GREETING_TOKENS = new Set(['hi', 'hello', 'hey', 'dear', 'best', 'regards', 'sincerely',
  'thanks', 'thank', 'you', 'cheers', 'team', 'kind', 'warm']);

const RAW_ARTIFACTS = [
  'thanks for watching', 'thank you for watching', 'thanks for listening',
  'thank you for listening', 'please subscribe', 'like and subscribe',
  "please like and subscribe", "don't forget to subscribe",
  'see you in the next video', 'see you next time',
];

function lastSentence(text) {
  const parts = String(text).trim().split(/(?<=[.!?])\s+/);
  return parts[parts.length - 1] || '';
}

function classify(raw, cleaned) {
  const rawTrim = raw.trim(), cleanTrim = cleaned.trim();
  if (rawTrim === cleanTrim) return { cls: 'identical' };

  const norm = (s) => tokenize(s).join(' ');
  const rawNorm = norm(rawTrim), cleanNorm = norm(cleanTrim);
  if (rawNorm === cleanNorm) return { cls: 'benign-punct-case' };

  const cleanToks = tokenize(cleanTrim);
  const cleanCnt = counts(cleanToks);
  const rawToks = removeFillerBigrams(tokenize(rawTrim), cleanCnt);
  const rawCnt = counts(rawToks);

  const injected = multisetDiff(cleanCnt, rawCnt);
  const dropped = multisetDiff(rawCnt, cleanCnt);
  const injectedNonFiller = injected.filter((t) => !FILLERS.has(t));
  const droppedNonFiller = dropped.filter((t) => !FILLERS.has(t));

  const rawHasQ = rawTrim.includes('?') || QUESTION_LEAD.test(lastSentence(rawTrim));
  const cleanHasQ = cleanTrim.includes('?');

  const flags = [];
  // (a) answered the question
  if (rawHasQ && ANSWER_LEAD.test(cleanTrim) && !ANSWER_LEAD.test(rawTrim)) flags.push('answered-question');
  if (rawHasQ && !cleanHasQ && injectedNonFiller.length >= 3) flags.push('question-lost-content-added');
  // (b) injected trailing ack ("random yes")
  if (TRAILING_ACK.test(cleanTrim)) {
    const m = cleanTrim.match(TRAILING_ACK);
    const tok = m[2].toLowerCase();
    if ((cleanCnt.get(tok) || 0) > (rawCnt.get(tok) || 0)) flags.push('injected-trailing-ack');
  }
  // (b2) any injected content
  if (injectedNonFiller.length >= 3) {
    if (injectedNonFiller.every((t) => GREETING_TOKENS.has(t))) flags.push('email-scaffold-added');
    else flags.push('injected-content');
  }
  // (c) dropped meaningful content
  const rawNF = rawToks.filter((t) => !FILLERS.has(t)).length;
  if (droppedNonFiller.length >= 5 && rawNF > 0 && droppedNonFiller.length / rawNF >= 0.3) flags.push('dropped-content');
  // length explosion
  if (cleanToks.length > rawToks.length * 1.3 + 3) flags.push('length-explosion');

  if (flags.length > 0) return { cls: 'harmful-candidate', flags, injected: injectedNonFiller.slice(0, 20), dropped: droppedNonFiller.slice(0, 20) };

  if (injectedNonFiller.length === 0 && dropped.every((t) => FILLERS.has(t))) return { cls: 'benign-filler-removal' };
  if (injectedNonFiller.length === 0 && droppedNonFiller.length <= 2) return { cls: 'benign-minor-edit' };
  if (injectedNonFiller.length <= 2 && droppedNonFiller.length <= 2) return { cls: 'ambiguous-small-edit', injected: injectedNonFiller, dropped: droppedNonFiller };
  return { cls: 'ambiguous', injected: injectedNonFiller.slice(0, 20), dropped: droppedNonFiller.slice(0, 20) };
}

function rawWeirdness(raw) {
  const w = [];
  const lower = raw.toLowerCase();
  for (const a of RAW_ARTIFACTS) if (lower.trimEnd().endsWith(a) || lower.trimEnd().endsWith(a + '.')) { w.push('trailing-artifact'); break; }
  if (/(^|[.!?]\s+)(thank you|thanks|goodbye|bye)[.!]?\s*$/i.test(raw.trim()) && tokenize(raw).length > 4) w.push('trailing-thankyou');
  if (/\b(\w+)([ ,.]+\1){3,}\b/i.test(raw)) w.push('repeated-token-loop');
  if (/(.{4,60}?)[\s,.!?]*(\1[\s,.!?]*){2,}$/i.test(raw.trim())) w.push('repeated-phrase-loop');
  if (TRAILING_ACK.test(raw.trim()) && tokenize(raw).length > 3) w.push('raw-trailing-ack');
  return w;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
// FNV-1a 64-bit (as 2x32-bit) — memory-lean dedup keys; collisions negligible here
function fnv64(str) {
  let h1 = 0x811c9dc5, h2 = 0xcbf29ce4;
  for (let i = 0; i < str.length; i++) {
    const c = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0;
    h2 = Math.imul(h2 ^ (c + 7), 0x01000197) >>> 0;
  }
  return h1.toString(36) + h2.toString(36);
}
const seenIds = new Set();     // hashed entry ids
const seenPairs = new Set();   // hashed (raw,cleaned) pairs (dedup for LLM stage)
let pairDupCount = 0;
const stats = {
  files: {}, total: 0, unique: 0, dupSkipped: 0, noRawField: 0,
  byClass: {}, byMonth: {}, harmfulByMonth: {}, byFlag: {}, flagByEra: {},
  byAppContextHarmful: {}, rawWeird: {}, rawWeirdByMonth: {},
  eras: {},
};
const outDivergent = fs.createWriteStream(path.join(outDir, 'divergent-all.jsonl'));
const outHarmful = fs.createWriteStream(path.join(outDir, 'harmful-candidates.jsonl'));
const outAmbiguous = fs.createWriteStream(path.join(outDir, 'needs-llm.jsonl'));
const outWeird = fs.createWriteStream(path.join(outDir, 'raw-weirdness.jsonl'));

// Backpressure: processEntry queues writes; the stream loop flushes with drain-awaits.
const pendingWrites = [];
function queueWrite(stream, line) { pendingWrites.push([stream, line]); }
async function flushPending() {
  while (pendingWrites.length) {
    const [stream, line] = pendingWrites.shift();
    if (!stream.write(line)) {
      await new Promise((res) => stream.once('drain', res));
    }
  }
}

function bump(obj, key, n = 1) { obj[key] = (obj[key] || 0) + n; }

function processEntry(e, era) {
  stats.total++;
  const raw = e.rawText, cleaned = e.cleanedText;
  if (typeof raw !== 'string' || typeof cleaned !== 'string') { stats.noRawField++; return; }
  const id = fnv64(e.id || `${e.timestamp}|${String(raw).slice(0, 80)}`);
  if (seenIds.has(id)) { stats.dupSkipped++; return; }
  seenIds.add(id);
  stats.unique++;
  bump(stats.eras, era);
  if (stats.unique % 100000 === 0) console.error(`  ... ${stats.unique} unique entries (${stats.total} total)`);

  const month = String(e.timestamp || '').slice(0, 7) || 'unknown';
  bump(stats.byMonth, month);

  // Legacy entries can carry pathologically large appContext fields (repeated
  // UTF-8 re-encoding blew one to 148 MB) — truncate before using anywhere.
  const app = String(e.appContext || 'unknown').slice(0, 120);
  stats.maxRawLen = Math.max(stats.maxRawLen || 0, raw.length);
  stats.maxCleanedLen = Math.max(stats.maxCleanedLen || 0, cleaned.length);
  stats.maxAppLen = Math.max(stats.maxAppLen || 0, String(e.appContext || '').length);

  const weird = rawWeirdness(raw);
  if (weird.length) {
    for (const w of weird) bump(stats.rawWeird, w);
    bump(stats.rawWeirdByMonth, month);
    queueWrite(outWeird, JSON.stringify({ id, era, ts: e.timestamp, app, weird, raw }) + '\n');
  }

  const r = classify(raw, cleaned);
  bump(stats.byClass, r.cls);
  if (r.cls === 'identical') return;

  const rec = { id, era, ts: e.timestamp, app, cls: r.cls, flags: r.flags, injected: r.injected, dropped: r.dropped, raw, cleaned };
  queueWrite(outDivergent, JSON.stringify(rec) + '\n');

  const pairKey = fnv64(raw.trim() + '|' + cleaned.trim());
  const dupPair = seenPairs.has(pairKey);
  if (dupPair) pairDupCount++; else seenPairs.add(pairKey);

  if (r.cls === 'harmful-candidate') {
    bump(stats.harmfulByMonth, month);
    for (const f of r.flags) {
      bump(stats.byFlag, f);
      bump(stats.flagByEra, `${era}:${f}`);
    }
    bump(stats.byAppContextHarmful, app);
    if (!dupPair) queueWrite(outHarmful, JSON.stringify(rec) + '\n');
  } else if (r.cls.startsWith('ambiguous')) {
    if (!dupPair) queueWrite(outAmbiguous, JSON.stringify(rec) + '\n');
  }
}

async function streamFile(file, era) {
  const scanner = new ObjectScanner((obj) => processEntry(obj, era));
  const before = stats.total;
  await new Promise((resolve, reject) => {
    const rs = fs.createReadStream(file, { encoding: 'utf8', highWaterMark: 1 << 20 });
    rs.on('data', (chunk) => {
      scanner.feed(chunk);
      if (pendingWrites.length) {
        rs.pause();
        flushPending().then(() => rs.resume(), reject);
      }
    });
    rs.on('end', () => flushPending().then(resolve, reject));
    rs.on('error', reject);
  });
  stats.files[file] = { entries: stats.total - before, parseFailures: scanner.parseFailures };
}

const t0 = Date.now();
for (const f of files) {
  const era = f.toLowerCase().includes('quicksay beta') ? 'legacy' : 'live';
  console.error(`scanning ${f} (era=${era}) ...`);
  await streamFile(f, era);
}
stats.elapsedSec = (Date.now() - t0) / 1000;
stats.uniqueDivergentPairs = seenPairs.size;
stats.duplicatePairsSkipped = pairDupCount;

for (const s of [outDivergent, outHarmful, outAmbiguous, outWeird]) s.end();
fs.writeFileSync(path.join(outDir, 'stats.json'), JSON.stringify(stats, null, 2));
console.log(JSON.stringify({ ...stats, byMonth: undefined, harmfulByMonth: undefined }, null, 2));
