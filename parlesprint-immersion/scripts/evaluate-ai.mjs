// Serial opt-in live evaluation. Maximum 20 calls. Never print credentials.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const env = {};
for (const name of ['.env.local', '.env.qa.local']) {
  try { for (const line of (await readFile(path.join(root, name), 'utf8')).split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (m) env[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  } } catch (e) { if (e.code !== 'ENOENT') throw e; }
}
Object.assign(env, process.env);
const base = env.WXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL;
const anon = env.WXT_PUBLIC_SUPABASE_ANON_KEY || env.SUPABASE_ANON_KEY;
const service = env.IMMERSION_QA_SERVICE_KEY || env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SECRET_KEY;
assert(base && anon && service, 'Supply public Supabase config and a QA service key');
const regression = process.argv.includes('--regression');
const fixture = regression ? 'explanation-regressions.json' : 'explanation-cases.json';
const cases = JSON.parse(await readFile(path.join(root, 'tests/fixtures', fixture), 'utf8'));
assert(cases.length > 0 && cases.length <= 20, 'Evaluation must contain 1–20 cases');
async function request(route, body, key, bearer, method = 'POST') {
  const response = await fetch(base + route, {
    method, headers: { apikey: key, Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(35000),
  });
  return { status: response.status, body: await response.json() };
}
let userId;
const results = [];
try {
  const email = `immersion-eval-${randomBytes(8).toString('hex')}@example.com`;
  const password = randomBytes(30).toString('base64url');
  const created = await request('/auth/v1/admin/users', { email, password, email_confirm: true }, service, service);
  assert(created.status < 300, `Account creation failed (${created.status})`);
  userId = created.body.id;
  const signed = await request('/auth/v1/token?grant_type=password', { email, password }, anon, anon);
  assert(signed.status === 200, `Sign-in failed (${signed.status})`);
  for (const item of cases) {
    const started = performance.now();
    try {
      const response = await request('/functions/v1/immersion-explain', { text: item.text, sentence: item.sentence, level: item.level }, anon, signed.body.access_token);
      const valid = response.status === 200 && ['meaning', 'grammar', 'example', 'exampleTranslation'].every(k => typeof response.body[k] === 'string' && response.body[k].trim().length > 0 && response.body[k].length <= 2000);
      results.push({ ...item, latencyMs: Math.round(performance.now() - started), status: response.status, schemaValid: valid, explanation: valid ? response.body : undefined, error: valid ? undefined : response.body.error });
    } catch { results.push({ ...item, latencyMs: Math.round(performance.now() - started), status: 0, schemaValid: false, error: 'request_failed' }); }
    console.log(`${item.id}: ${results.at(-1).status} / ${results.at(-1).latencyMs} ms`);
  }
} finally {
  if (userId) {
    const cleanup = await request(`/auth/v1/admin/users/${encodeURIComponent(userId)}`, undefined, service, service, 'DELETE');
    assert(cleanup.status < 300, `Temporary-user cleanup failed (${cleanup.status})`);
    console.log('Temporary evaluation account removed.');
  }
  await mkdir(path.join(root, 'artifacts'), { recursive: true });
  await writeFile(path.join(root, regression ? 'artifacts/ai-regression-v3.json' : 'artifacts/ai-evaluation.json'), JSON.stringify({ date: new Date().toISOString(), endpoint: `${base}/functions/v1/immersion-explain`, results }, null, 2));
}
const times = results.map(r => r.latencyMs).sort((a,b) => a-b);
console.log(JSON.stringify({ cases: results.length, valid: results.filter(r => r.schemaValid).length, minMs: times[0], medianMs: times.length % 2 ? times[Math.floor(times.length / 2)] : (times[times.length / 2 - 1] + times[times.length / 2]) / 2, p95Ms: times[Math.ceil(times.length * .95) - 1], maxMs: times.at(-1) }));
if (results.some(r => !r.schemaValid)) process.exitCode = 1;
