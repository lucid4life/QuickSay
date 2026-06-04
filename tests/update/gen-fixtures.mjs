// T2.5 update-signing test-fixture generator (Node ≥ 18).
// Produces tests/update/fixtures.json consumed by update-tests.ahk.
//
// Signs sample version.json manifests with the REAL qs-2026 private key
// (~/.quicksay-keys/qs-2026-ed25519-private.pem) so the AHK verifier is tested
// against the actual compiled-in trust anchor. The qs-2026 PRIVATE key never
// enters the repo; only PUBLIC keys + signatures (public data) land in
// fixtures.json. After M.1 deletes the local private key, regeneration is
// impossible — run-tests.ps1 falls back to the committed fixtures.json.
//
// Deterministic / idempotent: fixed seeds, fixed released_at, fixed dummy hashes,
// Ed25519 is deterministic — regenerating never produces a git diff.
//
// Run via run-tests.ps1, or:  node tests/update/gen-fixtures.mjs
import { createHash, createPublicKey, createPrivateKey, sign as edSign, verify as edVerify } from "node:crypto";
import { writeFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalManifest, signManifest } from "../../scripts/version-canonical.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const SPKI_ED25519_PREFIX  = Buffer.from("302a300506032b6570032100", "hex");
const PKCS8_ED25519_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");
function pubFromRaw(raw32) { return createPublicKey({ key: Buffer.concat([SPKI_ED25519_PREFIX, raw32]), format: "der", type: "spki" }); }
function spkiRawFromPub(pubObj) { const der = pubObj.export({ format: "der", type: "spki" }); return der.subarray(der.length - 32); }
function privFromSeed(seedHex) { return createPrivateKey({ key: Buffer.concat([PKCS8_ED25519_PREFIX, Buffer.from(seedHex, "hex")]), format: "der", type: "pkcs8" }); }

// ─── RFC 8032 §7.1 TEST 2 (independent KAT, re-verified under Node) ────────────
const rfcPub = Buffer.from("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "hex");
const rfcMsg = Buffer.from("72", "hex");
const rfcSig = Buffer.from("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00", "hex");
if (!edVerify(null, rfcMsg, pubFromRaw(rfcPub), rfcSig)) { console.error("FATAL: RFC 8032 TEST 2 did not verify under Node."); process.exit(2); }

// ─── qs-2026 production key (signs the valid/tamper fixtures) ──────────────────
const keyDir = join(homedir(), ".quicksay-keys");
const qsPriv = createPrivateKey({ key: readFileSync(join(keyDir, "qs-2026-ed25519-private.pem")), format: "pem", type: "pkcs8" });
const qsRaw = spkiRawFromPub(createPublicKey(qsPriv));
const qsRawB64url = Buffer.from(qsRaw).toString("base64url");
const qsSha256 = createHash("sha256").update(qsRaw).digest("hex");
const EXPECT_RAW = "UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8";
const EXPECT_SHA = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b";
if (qsRawB64url !== EXPECT_RAW) { console.error(`FATAL: qs-2026 raw pubkey mismatch: ${qsRawB64url}`); process.exit(2); }
if (qsSha256 !== EXPECT_SHA)   { console.error(`FATAL: qs-2026 pubkey sha256 mismatch: ${qsSha256}`); process.exit(2); }

const wrongPriv = privFromSeed("5a".repeat(32)); // fixed-seed throwaway "wrong key"

// ─── Fixed manifest constants (deterministic) ─────────────────────────────────
const LOCAL = "1.9.0";                                  // matches CheckForUpdates() localVersion
const DUMMY_SHA = "a".repeat(64);                       // 64-hex stand-in for installer_sha256
const REL = "2026-06-02T00:00:00Z";
const URL = "https://quicksay.app/download";

// pretty-print a signed manifest to the exact string the app would fetch
const bodyOf = (signed) => JSON.stringify(signed, null, 2);

// valid newer manifest signed by qs-2026
const validM = { version: "9.9.9", download_url: URL, changelog: ["Bug fixes and improvements", "Faster startup"], installer_sha256: DUMMY_SHA, released_at: REL, keyId: "qs-2026" };
const valid = signManifest(qsPriv, validM);

// same-version manifest (== LOCAL) — verifies but is NOT offered (regression #11)
const sameM = { ...validM, version: LOCAL };
const same = signManifest(qsPriv, sameM);

// non-ASCII changelog (emoji astral + accented + slash) — byte-identity test #9
const nonAsciiM = { version: "9.9.9", download_url: URL, changelog: ["Added 🚀 rocket mode", "Fixed é accent / slash bug", "Plain ASCII line"], installer_sha256: DUMMY_SHA, released_at: REL, keyId: "qs-2026" };
const nonAscii = signManifest(qsPriv, nonAsciiM);

// tamper variants — mutate ONE signed field AFTER signing (signature goes stale)
const clone = (o) => JSON.parse(JSON.stringify(o));
const tamperedVersion = clone(valid.signed); tamperedVersion.version = "9.9.8";
const tamperedUrl     = clone(valid.signed); tamperedUrl.download_url = "https://evil.example.com/x.exe";
const tamperedSha     = clone(valid.signed); tamperedSha.installer_sha256 = "b".repeat(64);
const strippedSig     = clone(valid.signed); delete strippedSig.signature;

// wrong key: keyId still "qs-2026" but signed by wrongPriv → verify against qs-2026 fails
const wrongKey = signManifest(wrongPriv, validM);

// unknown keyId: properly self-signed by qs-2026 over a payload that says "qs-9999";
// verifier rejects at the keyId-trust gate (qs-9999 not in TRUSTED_UPDATE_KEYS)
const unknownM = { ...validM, keyId: "qs-9999" };
const unknownKid = signManifest(qsPriv, unknownM);

// F1 (security review): the nonAscii body but with the raw 🚀 (U+1F680) rewritten
// to its 🚀 escaped form in the FETCHED bytes. The signature is unchanged
// (it was computed over the raw-UTF-8 canonical). In UTF-16 the escaped surrogate
// pair is byte-identical to the raw emoji, so a correct verifier re-canonicalizes to
// the same bytes and ACCEPTS it as the same signed content; a verifier that mishandled
// surrogates would fail closed. Either way it can never mis-trust DIFFERENT content.
const escapedSurrogateBody = bodyOf(nonAscii.signed).replace("🚀", "\\uD83D\\uDE80");

const fixtures = {
  local: LOCAL,
  qs2026: { rawB64url: qsRawB64url, sha256: qsSha256 },
  rfc8032: { pubHex: rfcPub.toString("hex"), msgHex: rfcMsg.toString("hex"), sigHex: rfcSig.toString("hex") },
  valid:       { version: validM.version, body: bodyOf(valid.signed) },
  sameVersion: { version: sameM.version,  body: bodyOf(same.signed) },
  nonAscii:    { canonical: nonAscii.canonical, body: bodyOf(nonAscii.signed) },
  escapedSurrogate: escapedSurrogateBody,
  tamperedVersion: bodyOf(tamperedVersion),
  tamperedUrl:     bodyOf(tamperedUrl),
  tamperedSha:     bodyOf(tamperedSha),
  strippedSig:     bodyOf(strippedSig),
  wrongKey:        bodyOf(wrongKey.signed),
  unknownKid:      bodyOf(unknownKid.signed),
};

writeFileSync(join(__dirname, "fixtures.json"), JSON.stringify(fixtures, null, 2));
console.log("OK tests/update/fixtures.json written");
console.log(`  qs-2026 raw b64url : ${qsRawB64url}`);
console.log(`  valid canonical    : ${valid.canonical}`);
console.log(`  nonAscii canonical : ${nonAscii.canonical}`);
