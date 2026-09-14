import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import worker from "../dist/server/index.js";

async function render(path = "/") {
  return worker.fetch(new Request(`http://localhost${path}`, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} });
}

test("home serves the redesign with working destinations and production styles", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /text\/html/);
  const html = await response.text();
  assert.match(html, /Good clips\./);
  assert.match(html, /Great content\./);
  assert.match(html, /https:\/\/contentmaker\.site\/downloads\/ContentMakerSetup\.exe/);
  assert.match(html, /href="\/privacy"/);
  assert.doesNotMatch(html, /Your site is taking shape|<iframe/);
  const styles = [...html.matchAll(/<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)].map(m => m[1]);
  assert.ok(styles.length >= 2, "Shared and homepage CSS must be included in SSR");
  for (const href of styles) {
    const content = await readFile(new URL(`../dist/client${href}`, import.meta.url), "utf8");
    assert.ok(content.length > 1000, `Production stylesheet exists: ${href}`);
  }
  assert.match(html, /aria-label="Scrub preview timeline"/);
  assert.match(html, /aria-controls="faq-answer-0"/);
  assert.match(html, /Pause animations/);
});

test("privacy remains available with the existing policy content", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Privacy Policy/);
  assert.match(html, /Google and YouTube data/);
  assert.match(html, /Your choices and deletion/);
});
