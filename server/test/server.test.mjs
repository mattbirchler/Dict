import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createStore } from "../server.mjs";

let server, base;
before(async () => {
  delete process.env.STRIPE_SECRET_KEY;
  delete process.env.DICT_PAYMENT_LINK_URL;
  server = createStore();
  await new Promise((resolve) => server.listen(0, resolve));
  base = `http://localhost:${server.address().port}`;
});
after(() => server.close());

test("pages are served with and without .html", async () => {
  for (const path of ["/", "/thanks", "/thanks.html", "/style.css"]) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  }
  assert.match((await fetch(base + "/thanks")).headers.get("content-type"), /text\/html/);
  assert.match((await fetch(base + "/style.css")).headers.get("content-type"), /text\/css/);
});

test("only files in public/ are served", async () => {
  for (const path of ["/server.mjs", "/../package.json", "/%2e%2e/package.json", "/api/license.mjs", "/nope"]) {
    assert.equal((await fetch(base + path)).status, 404, path);
  }
});

test("the license API answers through the server", async () => {
  const bad = await fetch(base + "/api/license?session_id=nope");
  assert.equal(bad.status, 400);
  const closed = await fetch(base + "/api/license?session_id=cs_test_abc");
  assert.equal(closed.status, 503);
  assert.deepEqual(await closed.json(), { error: "The store isn't open yet." });
});

test("/buy redirects once a payment link is set", async () => {
  assert.equal((await fetch(base + "/buy", { redirect: "manual" })).status, 503);
  process.env.DICT_PAYMENT_LINK_URL = "https://buy.stripe.com/test_123";
  const response = await fetch(base + "/buy", { redirect: "manual" });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://buy.stripe.com/test_123");
});

test("health check and methods", async () => {
  assert.equal(await (await fetch(base + "/healthz")).text(), "ok");
  assert.equal((await fetch(base + "/", { method: "POST" })).status, 405);
});
