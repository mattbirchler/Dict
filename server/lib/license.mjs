// Makes Dict license keys. The app checks them offline with the matching
// public key (Dict-app/License.swift), so this file and that one must agree
// on the format:
//
//   DICT1-<payload>.<signature>
//
// payload is base64url JSON, signature is the base64url Ed25519 signature of
// the payload's bytes. Signing is deterministic, so the same purchase always
// gets the same key.
import { createPrivateKey, createPublicKey, sign } from "node:crypto";

export const PREFIX = "DICT1-";

// Ed25519 private keys are stored as their raw 32-byte seed in base64.
// Node wants PKCS#8, which for Ed25519 is this fixed header plus the seed.
const PKCS8_HEADER = Buffer.from("302e020100300506032b657004220420", "hex");

export function privateKeyFromSeed(seedBase64) {
  const seed = Buffer.from(String(seedBase64).trim(), "base64");
  if (seed.length !== 32) throw new Error("The license signing key must be a 32-byte base64 seed.");
  return createPrivateKey({ key: Buffer.concat([PKCS8_HEADER, seed]), format: "der", type: "pkcs8" });
}

export function publicKeyBase64(privateKey) {
  const { x } = createPublicKey(privateKey).export({ format: "jwk" });
  return Buffer.from(x, "base64url").toString("base64");
}

/** issued is a YYYY-MM-DD date string. */
export function issueLicense({ email, purchase, issued }, privateKey) {
  if (!email || !purchase || !/^\d{4}-\d{2}-\d{2}$/.test(issued ?? "")) {
    throw new Error("A license needs an email, a purchase id and an issued date (YYYY-MM-DD).");
  }
  const payload = Buffer.from(JSON.stringify({ v: 1, product: "dict", email, purchase, issued }));
  const signature = sign(null, payload, privateKey);
  return PREFIX + payload.toString("base64url") + "." + signature.toString("base64url");
}

/** The link that opens Dict and activates the key in one click. */
export function activationURL(key) {
  return "dictapp://activate?key=" + encodeURIComponent(key);
}
