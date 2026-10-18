// Opt-in live checks. Uses a temporary account, or the dedicated reviewer account without admin credentials; never logs credentials.
import { chromium } from '@playwright/test';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const env = {};
for (const filename of ['.env.local', '.env.qa.local', '.env.review.local']) {
  try {
    for (const line of (await readFile(path.resolve(root, filename), 'utf8')).split(/\r?\n/)) {
      if (!line.trim() || line.trimStart().startsWith('#')) continue;
      const match = /^\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*?)\s*$/.exec(line);
      if (match) env[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2');
    }
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
Object.assign(env, process.env);
const base = env.WXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL;
const anon = env.WXT_PUBLIC_SUPABASE_ANON_KEY || env.SUPABASE_ANON_KEY;
const service = env.IMMERSION_QA_SERVICE_KEY || env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SECRET_KEY;
const useReviewer = !service && env.IMMERSION_REVIEW_EMAIL && env.IMMERSION_REVIEW_PASSWORD;
assert(base && anon && (service || useReviewer), 'Local public and test-account configuration required');
const id = 'ijclgmkoljddlalgcnpodeemcmcipolb';
let userId;
let createdUser = false;
let context;
async function admin(route, body, method = 'POST') {
  const response = await fetch(`${base}/auth/v1/admin/${route}`, {
    method, headers: { apikey: service, Authorization: `Bearer ${service}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000),
  });
  assert(response.ok, `Temporary-account admin operation failed (${response.status})`);
  return response.json();
}
try {
  const email = useReviewer ? env.IMMERSION_REVIEW_EMAIL : `immersion-browser-qa-${randomBytes(8).toString('hex')}@example.com`;
  const password = useReviewer ? env.IMMERSION_REVIEW_PASSWORD : randomBytes(30).toString('base64url');
  if (useReviewer) userId = env.IMMERSION_REVIEW_USER_ID;
  else {
    const user = await admin('users', { email, password, email_confirm: true });
    userId = user.id;
    createdUser = true;
  }
  assert(typeof userId === 'string', 'Test account missing ID');
  const extension = path.join(root, '.output/chrome-mv3');
  context = await chromium.launchPersistentContext('', {
    channel: 'chromium', headless: true,
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
    viewport: { width: 1280, height: 800 },
  });
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent('serviceworker', { timeout: 15000 });
  assert(worker.url().includes(id), 'Unexpected loaded extension identity');
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await popup.getByRole('tab', { name: 'Account', exact: true }).click();
  await popup.getByLabel('Email', { exact: true }).fill(email);
  await popup.getByLabel('Password', { exact: true }).fill(password);
  await popup.getByRole('button', { name: 'Connect existing account', exact: true }).click();
  await popup.getByText('Connected for explanations', { exact: true }).waitFor({ timeout: 25000 });
  const identity = await popup.evaluate(() => chrome.runtime.sendMessage({ type: 'auth-status' }));
  assert.equal(identity.linked, true);
  assert.equal(identity.account.email, email);
  assert.equal(identity.account.id, userId);
  await worker.evaluate(async () => {
    const { prefs } = await chrome.storage.local.get('prefs');
    await chrome.storage.local.set({ prefs: { ...prefs, aiConsent: true } });
  });
  const message = { type: 'explain', text: "J'en ai marre", sentence: "J'en ai marre d'attendre sous la pluie.", level: 'A2' };
  const result = await popup.evaluate(message => chrome.runtime.sendMessage(message), message);
  assert(!result.error, `Background explanation returned error: ${result.error || ''}`);
  for (const field of ['meaning', 'grammar', 'example', 'exampleTranslation']) {
    assert(typeof result.explanation?.[field] === 'string' && result.explanation[field].length > 0, `Missing explanation field: ${field}`);
  }
  const key = JSON.stringify([3, message.text, message.sentence, message.level]);
  const cached = await worker.evaluate(async key => {
    const { explanationCache } = await chrome.storage.local.get('explanationCache');
    return explanationCache?.[key];
  }, key);
  assert.deepEqual(cached, result.explanation, 'Background did not persist explanation cache');
  await context.setOffline(true);
  const offline = await popup.evaluate(message => chrome.runtime.sendMessage(message), message);
  assert.deepEqual(offline.explanation, result.explanation, 'Cached explanation unavailable offline');
  await context.setOffline(false);
  // Real learner UI with a clearly labeled, local video fixture. AI is live.
  await worker.evaluate(async () => {
    const { prefs } = await chrome.storage.local.get('prefs');
    await chrome.storage.local.set({ prefs: { ...prefs, aiConsent: false } });
  });
  const page = await context.newPage();
  const video = await readFile(path.join(root, 'tests/fixtures/timing.webm'));
  await page.route('https://www.youtube.com/test-video.webm', route => {
    const match = /bytes=(\d+)-(\d*)/.exec(route.request().headers().range ?? '');
    const start = match ? Number(match[1]) : 0;
    const end = match?.[2] ? Number(match[2]) : video.length - 1;
    return route.fulfill({ status: match ? 206 : 200, contentType: 'video/webm',
      headers: { 'Accept-Ranges': 'bytes', ...(match ? { 'Content-Range': `bytes ${start}-${end}/${video.length}` } : {}) },
      body: video.subarray(start, end + 1) });
  });
  await page.route('https://www.youtube.com/watch?*', route => route.fulfill({ contentType: 'text/html',
    body: `<!doctype html><html><head><meta charset="utf-8"><title>ParleSprint · Live explanation test</title></head><body style="margin:0;background:#f2f3ed;font:18px/1.6 system-ui;color:#273d33"><main style="padding:40px;max-width:720px"><small>PARLESPRINT · LOCAL DEMO FIXTURE</small><h1>French subtitle practice</h1><p>Imported French subtitles. Real AI explanation.</p><video style="width:680px;max-width:100%" controls src="/test-video.webm"></video><p>Illustrative captions for interface testing.<br>This local video does not contain spoken French.</p></main></body></html>` }));
  await page.goto('https://www.youtube.com/watch?v=live-ai-fixture');
  await page.waitForFunction(() => document.querySelector('video')?.readyState > 0);
  const panel = page.getByRole('complementary', { name: 'ParleSprint Immersion' });
  await panel.getByText('Optional subtitle alternatives', { exact: true }).click();
  await panel.getByLabel('Import French subtitles').setInputFiles(path.join(root, 'public/demo-fr.srt'));
  await page.locator('video').evaluate(video => { video.currentTime = 1; video.dispatchEvent(new Event('timeupdate')); });
  await panel.getByRole('button', { name: 'Study Bonjour', exact: true }).click();
  await panel.getByRole('button', { name: 'Allow explanations', exact: true }).click();
  await panel.getByRole('button', { name: 'Explain in context', exact: true }).click();
  await panel.getByRole('button', { name: 'Hide meaning', exact: true }).waitFor({ timeout: 30000 });
  const uiKey = JSON.stringify([3, 'Bonjour', "Bonjour ! Aujourd'hui, je prépare mon premier voyage au Québec.", 'A1']);
  const uiExplanation = await worker.evaluate(async key => (await chrome.storage.local.get('explanationCache')).explanationCache?.[key], uiKey);
  assert(uiExplanation, 'Learner UI explanation was not cached');
  const selected = panel.getByRole('region', { name: 'Selected phrase' });
  for (const field of ['meaning', 'grammar', 'example', 'exampleTranslation']) {
    await selected.getByText(uiExplanation[field], { exact: true }).waitFor();
  }
  await selected.scrollIntoViewIfNeeded();
  await mkdir(path.join(root, 'artifacts'), { recursive: true });
  await page.screenshot({ path: path.join(root, 'artifacts/explanation-ui.png') });
  console.log('PASS: real learner caption UI → consent → Gemini → meaning, grammar, French example and translation; screenshot saved.');
  await popup.getByRole('button', { name: 'Sign out', exact: true }).click();
  await popup.getByRole('button', { name: 'Connect existing account', exact: true }).waitFor();
  assert.deepEqual(await popup.evaluate(() => chrome.runtime.sendMessage({ type: 'auth-status' })), { linked: false });
  const cleared = await worker.evaluate(async () => {
    const values = await chrome.storage.local.get(['session', 'explanationCache']);
    return !values.session && !values.explanationCache;
  });
  assert(cleared, 'Sign-out did not clear session and AI cache');
  console.log('PASS: real MV3 popup password sign-in → background → Supabase → Gemini; structured response, persisted/offline cache, sign-out.');
} catch (error) {
  console.error(`Live AI test failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await context?.close();
  if (createdUser && userId) {
    try { await admin(`users/${encodeURIComponent(userId)}`, undefined, 'DELETE'); console.log('PASS: temporary test account removed.'); }
    catch { console.error('Temporary account cleanup failed; remove the immersion-browser-qa test account through admin tooling.'); process.exitCode = 1; }
  }
}
