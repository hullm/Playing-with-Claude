import { chromium } from "playwright";
import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const types = { ".html": "text/html", ".js": "text/javascript", ".webmanifest": "application/manifest+json", ".png": "image/png" };

const missed = [];
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/index.html";
  const fp = path.join(root, p);
  if (!fp.startsWith(root) || !fs.existsSync(fp)) { missed.push(p); res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "Content-Type": types[path.extname(fp)] || "application/octet-stream" });
  fs.createReadStream(fp).pipe(res);
});

await new Promise((r) => server.listen(0, r));
const port = server.address().port;
const base = `http://localhost:${port}/`;

const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
// iPhone-ish viewport
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
page.on("console", (m) => {
  if (m.type() === "error" && !/favicon\.ico/.test(m.location()?.url || "")) errors.push("console: " + m.text());
});

await page.goto(base, { waitUntil: "networkidle" });
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(root, "scripts", "shot-start.png") });

// Start the game
await page.click("#startBtn");
await page.waitForTimeout(300);
console.log("after start:", await page.evaluate(() => ({ state: window.NEONSTACK.state, height: window.NEONSTACK.height })));

// Read internal state by dropping several blocks. Tap the canvas repeatedly.
async function readState() {
  return await page.evaluate(() => {
    return { score: document.getElementById("score").textContent, over: !document.getElementById("overScreen").classList.contains("hidden") };
  });
}

// Drop ~15 blocks, aiming: wait until the moving block overlaps the tower.
async function dropWhenAligned() {
  // Fire when the block is predicted to be near-centered on the next frame.
  for (let t = 0; t < 400; t++) {
    const off = await page.evaluate(() => window.NEONSTACK.offset());
    if (Math.abs(off) < 12) { await page.mouse.click(195, 500); return true; }
    await page.waitForTimeout(6);
  }
  await page.mouse.click(195, 500);
  return false;
}
let placed = 0;
for (let i = 0; i < 18; i++) {
  await dropWhenAligned();
  await page.waitForTimeout(120);
  const s = await readState();
  if (parseInt(s.score, 10) > placed) placed = parseInt(s.score, 10);
  if (s.over) { console.log(`game over after ${i + 1} drops, score=${s.score}`); break; }
}
console.log("blocks stacked (score):", placed);
const mid = await readState();
console.log("mid-game score:", mid.score, "gameOver:", mid.over);
await page.screenshot({ path: path.join(root, "scripts", "shot-play.png") });

// Force a game over by dropping far off (rapid taps to eventually miss) if not already
if (!mid.over) {
  for (let i = 0; i < 40 && !(await readState()).over; i++) {
    await page.mouse.click(195, 500);
    await page.waitForTimeout(40);
  }
}
await page.waitForTimeout(800);
const end = await readState();
console.log("final gameOver:", end.over);
await page.screenshot({ path: path.join(root, "scripts", "shot-over.png") });

// Verify best score persisted
const best = await page.evaluate(() => localStorage.getItem("neonstack_best"));
console.log("persisted best:", best);

const realMissed = missed.filter((m) => m !== "/favicon.ico");
console.log("404s:", realMissed.length ? realMissed : "none (favicon ignored)");
console.log("JS ERRORS:", errors.length ? errors : "none");
await browser.close();
server.close();

// ---- Assertions ----
const failures = [];
if (errors.length) failures.push("JS errors occurred");
if (realMissed.length) failures.push("missing assets: " + realMissed.join(", "));
if (placed < 5) failures.push(`only ${placed} blocks stacked (expected >= 5)`);
if (!end.over) failures.push("game never reached game-over state");
if (!best || parseInt(best, 10) < 1) failures.push("best score not persisted");

if (failures.length) {
  console.error("\nFAIL:\n - " + failures.join("\n - "));
  process.exit(1);
}
console.log("\nPASS: game starts, stacks, scores, ends, and persists best.");
