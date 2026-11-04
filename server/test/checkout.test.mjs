import { test } from "node:test";
import assert from "node:assert/strict";
import { verify, createPublicKey } from "node:crypto";
import { privateKeyFromSeed, publicKeyBase64, PREFIX } from "../lib/license.mjs";
import { licenseForSession, fetchStripeSession, CheckoutError } from "../lib/checkout.mjs";

// Same test seed as Dict-appTests/LicenseTests.swift.
const seed = Buffer.from(Array.from({ length: 32 }, (_, i) => i + 1)).toString("base64");
const privateKey = privateKeyFromSeed(seed);
const options = { paymentLink: "plink_dict", privateKey };
const paid = {
  id: "cs_test_123",
  created: Date.UTC(2026, 10, 4, 15) / 1000,
  status: "complete",
  payment_status: "paid",
  payment_link: "plink_dict",
  customer_details: { email: "buyer@example.com" },
};

test("the test seed matches the Swift tests' public key", () => {
  assert.equal(publicKeyBase64(privateKey), "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=");
});

test("a paid Dict checkout gets the same key the Swift tests verify", () => {
  const { key, activate, email } = licenseForSession(paid, options);
  assert.equal(email, "buyer@example.com");
  assert.equal(key, "DICT1-eyJ2IjoxLCJwcm9kdWN0IjoiZGljdCIsImVtYWlsIjoiYnV5ZXJAZXhhbXBsZS5jb20iLCJwdXJjaGFzZSI6ImNzX3Rlc3RfMTIzIiwiaXNzdWVkIjoiMjAyNi0xMS0wNCJ9.6-tumXTcaevaLpsXrXm7ulAM8H5E7kVf0CM91P870_bI16cGUKn3o7XZO953dpmJ-RLqxg2lW4YXwHqHfGH1CA");
  assert.equal(activate, "dictapp://activate?key=" + key);
});

test("the signature checks out with the public key", () => {
  const { key } = licenseForSession(paid, options);
  const [payload, signature] = key.slice(PREFIX.length).split(".");
  const ok = verify(null, Buffer.from(payload, "base64url"), createPublicKey(privateKey), Buffer.from(signature, "base64url"));
  assert.ok(ok);
  assert.equal(signature.length, 86);
});

test("reloading the page gives the same key", () => {
  assert.equal(licenseForSession(paid, options).key, licenseForSession({ ...paid }, options).key);
});

test("other products on the Stripe account don't get Dict keys", () => {
  assert.throws(() => licenseForSession({ ...paid, payment_link: "plink_other" }, options), { status: 403 });
  assert.throws(() => licenseForSession({ ...paid, payment_link: null }, options), { status: 403 });
});

test("unpaid or open checkouts don't get keys", () => {
  assert.throws(() => licenseForSession({ ...paid, payment_status: "unpaid" }, options), { status: 402 });
  assert.throws(() => licenseForSession({ ...paid, status: "open" }, options), { status: 402 });
});

test("a 100% coupon still gets a key", () => {
  assert.ok(licenseForSession({ ...paid, payment_status: "no_payment_required" }, options).key.startsWith(PREFIX));
});

test("a missing payment link setting fails closed", () => {
  assert.throws(() => licenseForSession(paid, { privateKey }), { status: 500 });
});

test("Stripe's 404 becomes a readable error", async () => {
  const fake = async () => new Response("{}", { status: 404 });
  await assert.rejects(fetchStripeSession("cs_test_x", "sk", fake), (e) => e instanceof CheckoutError && e.status === 404);
});

test("the session is read with the secret key", async () => {
  let seen;
  const fake = async (url, init) => { seen = { url, init }; return Response.json(paid); };
  assert.deepEqual(await fetchStripeSession("cs_test_123", "sk_test_abc", fake), paid);
  assert.equal(seen.url, "https://api.stripe.com/v1/checkout/sessions/cs_test_123");
  assert.equal(seen.init.headers.Authorization, "Bearer sk_test_abc");
});
