// T2.3 test-fixture generator (Node ≥ 18, uses built-in crypto + jose if available).
// Produces tests/license/fixtures.json consumed by the AHK unit drivers.
//
// What it emits:
//   - rfc8032 : RFC 8032 §7.1 TEST 2 Ed25519 known-answer vector (independent ground truth),
//               re-verified here under Node's crypto so the bytes are proven correct.
//   - interop : a freshly generated keypair + signature (verifier↔Node interop check).
//   - qs2026  : the production qs-2026 raw-32 public key + its SHA-256 (must equal 761d22df…).
//   - jwts    : real Ed25519-signed license JWTs minted with the qs-2026 private key, for the
//               license.ahk verify-path tests (valid / tampered-claim / wrong-key / expired / grace…).
//
// Run via run-tests.ps1; or:  node tests/license/gen-fixtures.mjs
import { createHash, createPublicKey, createPrivateKey, sign as edSign, verify as edVerify, generateKeyPairSync } from "node:crypto";
import { writeFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SPKI_ED25519_PREFIX = Buffer.from("302a300506032b6570032100", "hex"); // DER SPKI header for Ed25519

function rawToSpki(raw32) { return Buffer.concat([SPKI_ED25519_PREFIX, raw32]); }
function pubFromRaw(raw32) { return createPublicKey({ key: rawToSpki(raw32), format: "der", type: "spki" }); }
function spkiRawFromPub(pubKeyObj) {
  const der = pubKeyObj.export({ format: "der", type: "spki" });
  return der.subarray(der.length - 32); // last 32 bytes = raw key
}
const b64url = (buf) => Buffer.from(buf).toString("base64url");

// ─── 1. RFC 8032 §7.1 TEST 2 (independent KAT) ────────────────────────────────
const rfcPub = Buffer.from("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "hex");
const rfcMsg = Buffer.from("72", "hex");
const rfcSig = Buffer.from("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00", "hex");
const rfcValid = edVerify(null, rfcMsg, pubFromRaw(rfcPub), rfcSig);
if (!rfcValid) { console.error("FATAL: RFC 8032 TEST 2 vector did NOT verify under Node — wrong bytes."); process.exit(2); }

// Deterministic Ed25519 private key from a fixed 32-byte seed (PKCS#8 DER wrapper),
// so this generator is idempotent — regenerating never produces a git diff.
const PKCS8_ED25519_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");
function privFromSeed(seedHex) {
  const der = Buffer.concat([PKCS8_ED25519_PREFIX, Buffer.from(seedHex, "hex")]);
  return createPrivateKey({ key: der, format: "der", type: "pkcs8" });
}

// ─── 2. Interop: fixed-seed keypair + signature ───────────────────────────────
const ipPriv = privFromSeed("42".repeat(32));
const ipPub = createPublicKey(ipPriv);
const ipRaw = spkiRawFromPub(ipPub);
const ipMsg = Buffer.from("QuickSay ed25519 interop é✅/test", "utf8"); // includes non-ASCII + slash
const ipSig = edSign(null, ipMsg, ipPriv);

// ─── 3. qs-2026 production key ─────────────────────────────────────────────────
const keyDir = join(homedir(), ".quicksay-keys");
const qsPriv = createPrivateKey({ key: readFileSync(join(keyDir, "qs-2026-ed25519-private.pem")), format: "pem", type: "pkcs8" });
const qsPubObj = createPublicKey(qsPriv);
const qsRaw = spkiRawFromPub(qsPubObj);
const qsRawB64url = b64url(qsRaw);
const qsRawSha256 = createHash("sha256").update(qsRaw).digest("hex");
const EXPECT_RAW_B64URL = "UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8";
const EXPECT_SHA256 = "761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b";
if (qsRawB64url !== EXPECT_RAW_B64URL) { console.error(`FATAL: qs-2026 raw pubkey mismatch: ${qsRawB64url}`); process.exit(2); }
if (qsRawSha256 !== EXPECT_SHA256) { console.error(`FATAL: qs-2026 pubkey sha256 mismatch: ${qsRawSha256}`); process.exit(2); }

// ─── 4. Mint license JWTs with qs-2026 ────────────────────────────────────────
const ISS = "license.quicksay.app";
const KID = "qs-2026";
const TEST_MACHINE = "0123456789abcdef0123456789abcdef"; // matches license-tests.ahk override
const sha256hex = (s) => createHash("sha256").update(s, "utf8").digest("hex");

function mintJWT({ machine = TEST_MACHINE, iat, exp, iss = ISS, kid = KID, alg = "EdDSA", signer = qsPriv,
                   email = "buyer@example.com", plan = "lifetime", sub = sha256hex("QS-TEST-LICENSE-KEY-0001") }) {
  const header = { alg, typ: "JWT", kid };
  const payload = { iss, sub, machine, email, plan, iat, exp };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = b64url(edSign(null, Buffer.from(signingInput, "ascii"), signer));
  return `${signingInput}.${sig}`;
}

const NOW = 1748736000; // fixed reference "now" = 2025-06-01T00:00:00Z (tests pass this as nowOverride)
const DAY = 86400, YEAR14 = 1209600;
const wrongPriv = privFromSeed("37".repeat(32)); // fixed-seed "wrong key" for determinism

const jwts = {
  // valid, exp 10 days in the future → LICENSED
  valid:        mintJWT({ iat: NOW - 4 * DAY, exp: NOW + 10 * DAY }),
  // exp 3 days ago → within 7-day grace → GRACE_PERIOD
  grace:        mintJWT({ iat: NOW - 17 * DAY, exp: NOW - 3 * DAY }),
  // exp 10 days ago → past grace, within revalidation window → RE_VALIDATION_NEEDED
  revalidate:   mintJWT({ iat: NOW - 24 * DAY, exp: NOW - 10 * DAY }),
  // valid signature but machine claim is some other machine → LICENSE_REVOKED
  wrongMachine: mintJWT({ iat: NOW - 4 * DAY, exp: NOW + 10 * DAY, machine: "ffffffffffffffffffffffffffffffff" }),
  // signed by a different key → LICENSE_REVOKED
  wrongKey:     mintJWT({ iat: NOW - 4 * DAY, exp: NOW + 10 * DAY, signer: wrongPriv }),
  // wrong issuer → LICENSE_REVOKED
  wrongIss:     mintJWT({ iat: NOW - 4 * DAY, exp: NOW + 10 * DAY, iss: "evil.example.com" }),
  // unknown kid → LICENSE_REVOKED
  wrongKid:     mintJWT({ iat: NOW - 4 * DAY, exp: NOW + 10 * DAY, kid: "qs-9999" }),
};

const fixtures = {
  now: NOW,
  testMachineId: TEST_MACHINE,
  iss: ISS, kid: KID,
  rfc8032: { pubHex: rfcPub.toString("hex"), msgHex: rfcMsg.toString("hex"), sigHex: rfcSig.toString("hex") },
  interop: { pubHex: ipRaw.toString("hex"), msgUtf8: ipMsg.toString("utf8"), msgHex: ipMsg.toString("hex"), sigHex: ipSig.toString("hex") },
  qs2026: { rawB64url: qsRawB64url, rawHex: qsRaw.toString("hex"), sha256: qsRawSha256 },
  jwts,
};
writeFileSync(join(__dirname, "fixtures.json"), JSON.stringify(fixtures, null, 2));
console.log("OK fixtures.json written");
console.log(`  RFC 8032 TEST 2 verified under Node: ${rfcValid}`);
console.log(`  qs-2026 raw b64url: ${qsRawB64url}`);
console.log(`  qs-2026 sha256    : ${qsRawSha256}`);
console.log(`  minted JWTs       : ${Object.keys(jwts).join(", ")}`);
