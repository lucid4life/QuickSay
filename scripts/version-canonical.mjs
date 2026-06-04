// scripts/version-canonical.mjs — shared canonicalization for signed version.json
// (T2.5 spec §7.2). Imported by BOTH the release signer (sign-version-json.mjs)
// AND the test fixture generator (tests/update/gen-fixtures.mjs), so the signer,
// the test oracle, and (by the byte-identity test) the AHK verifier all agree on
// the exact bytes that get Ed25519-signed.
//
// Recipe (spec §7.2, finding F5/D20):
//   - object with EXACTLY the six signed keys
//   - keys in lexicographic order: changelog < download_url < installer_sha256
//                                   < keyId < released_at < version
//   - compact separators (no insignificant whitespace)
//   - minimal RFC 8259 escaping (no '/' escaping; non-ASCII emitted raw UTF-8)
//   - changelog array element order preserved
// Node's JSON.stringify(orderedObject) produces exactly this when keys are
// inserted in sorted order (insertion order is preserved for string keys, and
// JSON.stringify uses compact separators + the minimal escaping above).
import { sign as edSign } from "node:crypto";

const SIGNED_FIELDS = ["version", "download_url", "changelog", "installer_sha256", "released_at", "keyId"];

export function canonicalManifest(m) {
  for (const k of SIGNED_FIELDS) {
    if (!(k in m)) throw new Error(`canonicalManifest: missing field '${k}'`);
  }
  if (!Array.isArray(m.changelog)) throw new Error("canonicalManifest: changelog must be an array");
  // Insert in lexicographic key order — JSON.stringify preserves it.
  const ordered = {
    changelog: m.changelog,
    download_url: m.download_url,
    installer_sha256: m.installer_sha256,
    keyId: m.keyId,
    released_at: m.released_at,
    version: m.version,
  };
  return JSON.stringify(ordered);
}

// Sign a manifest. Returns { canonical, signature(base64url), signed(full object
// in display order incl. signature) }.
export function signManifest(privKeyObj, m) {
  const canonical = canonicalManifest(m);
  const sigBuf = edSign(null, Buffer.from(canonical, "utf8"), privKeyObj);
  const signature = sigBuf.toString("base64url");
  const signed = {
    version: m.version,
    download_url: m.download_url,
    changelog: m.changelog,
    installer_sha256: m.installer_sha256,
    released_at: m.released_at,
    keyId: m.keyId,
    signature,
  };
  return { canonical, signature, signed };
}
