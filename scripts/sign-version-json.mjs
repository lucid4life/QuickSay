// scripts/sign-version-json.mjs — Ed25519-sign the auto-update manifest (T2.5).
//
// Invoked by release.ps1 STEP 6 AFTER the installer is built + code-signed (so
// installer_sha256 is final) and BEFORE the R2/website upload. Reads the manifest
// fields from --in <json>, signs the canonical payload (spec §7.2) with the
// qs-2026 Ed25519 PRIVATE key, and writes the full signed version.json to --out.
//
// Private key source (in priority order) — NEVER the repo:
//   1. env QUICKSAY_ED25519_PRIVATE_KEY        (PKCS#8 PEM contents, e.g. from a CI secret)
//   2. env QUICKSAY_ED25519_PRIVATE_KEY_PATH   (path to a PEM file outside the repo)
//   3. ~/.quicksay-keys/qs-2026-ed25519-private.pem   (local dev default)
//
// FAILS LOUDLY (non-zero exit) if no key is found or signing fails — release.ps1
// aborts so NO unsigned release ever ships.
//
// Exit codes: 0 ok · 2 bad args/input · 3 private key absent · 4 sign/verify failed
import { createPrivateKey, createPublicKey, createHash, verify as edVerify } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { canonicalManifest, signManifest } from "./version-canonical.mjs";

function die(code, msg) { console.error(`sign-version-json: ${msg}`); process.exit(code); }

// ── args ──────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let inPath = "", outPath = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--in")  inPath  = args[++i];
  else if (args[i] === "--out") outPath = args[++i];
}
if (!inPath || !outPath) die(2, "usage: node sign-version-json.mjs --in <fields.json> --out <version.json>");
if (!existsSync(inPath)) die(2, `input file not found: ${inPath}`);

let input;
try { input = JSON.parse(readFileSync(inPath, "utf8")); }
catch (e) { die(2, `could not parse input JSON: ${e.message}`); }

// Defensive: a single-element changelog can arrive as a scalar from ConvertTo-Json.
if (typeof input.changelog === "string") input.changelog = [input.changelog];
for (const k of ["version", "download_url", "changelog", "installer_sha256", "released_at", "keyId"]) {
  if (input[k] === undefined || input[k] === null) die(2, `input missing field '${k}'`);
}
if (!Array.isArray(input.changelog)) die(2, "input.changelog must be an array");
if (!/^[0-9a-f]{64}$/.test(String(input.installer_sha256))) die(2, "installer_sha256 must be 64 lowercase hex chars");

// ── load the PRIVATE key (never from the repo) ────────────────────────────────
function loadPrivateKey() {
  if (process.env.QUICKSAY_ED25519_PRIVATE_KEY) {
    return { obj: createPrivateKey({ key: process.env.QUICKSAY_ED25519_PRIVATE_KEY, format: "pem", type: "pkcs8" }), src: "env QUICKSAY_ED25519_PRIVATE_KEY" };
  }
  const p = process.env.QUICKSAY_ED25519_PRIVATE_KEY_PATH || join(homedir(), ".quicksay-keys", "qs-2026-ed25519-private.pem");
  if (!existsSync(p)) return null;
  return { obj: createPrivateKey({ key: readFileSync(p), format: "pem", type: "pkcs8" }), src: p };
}

let key;
try { key = loadPrivateKey(); }
catch (e) { die(3, `failed to load private key: ${e.message}`); }
if (!key) {
  die(3, "Ed25519 private key not found. Set QUICKSAY_ED25519_PRIVATE_KEY (PEM) or " +
        "QUICKSAY_ED25519_PRIVATE_KEY_PATH, or place ~/.quicksay-keys/qs-2026-ed25519-private.pem. " +
        "Refusing to ship an UNSIGNED version.json.");
}

// Confirm the loaded key is the qs-2026 trust anchor baked into the app.
const pubObj = createPublicKey(key.obj);
const rawPub = pubObj.export({ format: "der", type: "spki" }).subarray(-32);
const pubSha = createHash("sha256").update(rawPub).digest("hex");
const EXPECT_SHA = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b";
if (input.keyId === "qs-2026" && pubSha !== EXPECT_SHA) {
  die(4, `key mismatch: keyId 'qs-2026' but the loaded private key's public SHA-256 is ${pubSha}, ` +
        `expected ${EXPECT_SHA}. Wrong key — refusing to sign.`);
}

// ── sign ──────────────────────────────────────────────────────────────────────
let signed, canonical, signature;
try {
  ({ signed, canonical, signature } = signManifest(key.obj, input));
} catch (e) { die(4, `signing failed: ${e.message}`); }

// Self-check: the signature we just produced MUST verify against our own public key.
const sigBuf = Buffer.from(signature, "base64url");
if (!edVerify(null, Buffer.from(canonical, "utf8"), pubObj, sigBuf)) {
  die(4, "self-verify failed — produced signature does not verify. Aborting (no unsigned/broken release).");
}

writeFileSync(outPath, JSON.stringify(signed, null, 2), "utf8");
console.log(`OK signed version.json -> ${outPath}`);
console.log(`  keyId        : ${input.keyId}  (pubkey sha256 ${pubSha})`);
console.log(`  key source   : ${key.src}`);
console.log(`  version      : ${input.version}`);
console.log(`  installer_sha: ${input.installer_sha256}`);
console.log(`  signature    : ${signature.slice(0, 24)}… (base64url, 64-byte Ed25519)`);
