import { assertEquals } from 'jsr:@std/assert@1.0.14';

// Capture the real Edge handler without starting a server or using network.
Deno.env.set('SUPABASE_URL', 'https://backend.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-server-key');
Deno.env.set('SUPABASE_ANON_KEY', 'test-public-key');
Deno.env.set('GEMINI_API_KEY', 'test-model-key');
Deno.env.set('IMMERSION_IP_SALT', 'test-salt');
let handle: (request: Request) => Promise<Response>;
const originalServe = Deno.serve;
Deno.serve = ((handler: typeof handle) => { handle = handler; }) as typeof Deno.serve;
try { await import('./index.ts'); } finally { Deno.serve = originalServe; }
const explanation = { meaning: 'hello', grammar: 'greeting', example: 'Bonjour Marie.', exampleTranslation: 'Hello Marie.' };
const translation = { translation: 'Hello Marie.' };
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status });
const request = () => new Request('https://backend.invalid/functions/v1/immersion-explain', {
  method: 'POST', headers: { Authorization: 'Bearer test-user-token', 'Content-Type': 'application/json' },
  body: JSON.stringify({ text: 'bonjour', sentence: 'Bonjour Marie.', level: 'A1' }),
});
async function withFetch(mock: typeof fetch, run: () => Promise<void>) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  try { await run(); } finally { globalThis.fetch = original; }
}
Deno.test('a cache-write network failure preserves a paid valid explanation', async () => {
  await withFetch((async (input, init) => {
    const url = String(input);
    if (url.endsWith('/auth/v1/user')) return json({ id: 'test-user' });
    if (url.includes('/immersion_ai_cache?')) return json([]);
    if (url.includes('generativelanguage.googleapis.com')) return json({ candidates: [{ content: { parts: [{ text: JSON.stringify(explanation) }] } }] });
    if (url.endsWith('/immersion_ai_cache') && init?.method === 'POST') throw new TypeError('simulated network failure');
    throw new Error('Unexpected network call');
  }) as typeof fetch, async () => {
    const result = await handle(request());
    assertEquals(result.status, 200);
    assertEquals(await result.json(), explanation);
  });
});
Deno.test('Auth outage is retryable service error rather than invalid credentials', async () => {
  await withFetch((async () => json({ error: 'upstream outage' }, 503)) as typeof fetch, async () => {
    const result = await handle(request());
    assertEquals(result.status, 503);
    assertEquals(await result.json(), { error: 'authentication_unavailable' });
  });
});
Deno.test('an invalid user token is rejected before any model request', async () => {
  let calls = 0;
  await withFetch((async () => { calls++; return json({}, 401); }) as typeof fetch, async () => {
    const result = await handle(request());
    assertEquals(result.status, 401);
    assertEquals(calls, 1);
  });
});
Deno.test('translation uses the short Flash-Lite response without a quota RPC', async () => {
  let quotaCalls = 0;
  let providerUrl = '';
  let providerBody: any;
  await withFetch((async (input, init) => {
    const url = String(input);
    if (url.endsWith('/auth/v1/user')) return json({ id: 'test-user' });
    if (url.includes('/immersion_ai_cache?')) return json([]);
    if (url.includes('/rpc/')) { quotaCalls++; return json(false); }
    if (url.includes('generativelanguage.googleapis.com')) {
      providerUrl = url;
      providerBody = JSON.parse(String(init?.body));
      return json({ candidates: [{ content: { parts: [{ text: JSON.stringify(translation) }] } }] });
    }
    if (url.endsWith('/immersion_ai_cache') && init?.method === 'POST') return new Response(null, { status: 201 });
    throw new Error('Unexpected request');
  }) as typeof fetch, async () => {
    const result = await handle(new Request('https://backend.invalid/functions/v1/immersion-explain', {
      method: 'POST', headers: { Authorization: 'Bearer test-user-token', 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'Bonjour Marie.', sentence: 'Bonjour Marie.', level: 'A1', mode: 'translation' }),
    }));
    assertEquals(result.status, 200);
    assertEquals(await result.json(), translation);
    assertEquals(quotaCalls, 0);
    assertEquals(providerUrl.includes('/gemini-3.1-flash-lite:'), true);
    assertEquals(providerBody.generationConfig.maxOutputTokens, 256);
    assertEquals(providerBody.generationConfig.responseJsonSchema.required, ['translation']);
  });
});
Deno.test('provider timeout is a bounded retryable error without private details', async () => {
  await withFetch((async input => {
    const url = String(input);
    if (url.endsWith('/auth/v1/user')) return json({ id: 'test-user' });
    if (url.includes('/immersion_ai_cache?')) return json([]);
    throw new DOMException('private upstream timeout detail', 'TimeoutError');
  }) as typeof fetch, async () => {
    const result = await handle(request());
    assertEquals(result.status, 503);
    assertEquals(await result.json(), { error: 'temporarily_unavailable' });
  });
});
Deno.test('provider rate limit does not retry or expose upstream response', async () => {
  let providerCalls = 0;
  await withFetch((async input => {
    const url = String(input);
    if (url.endsWith('/auth/v1/user')) return json({ id: 'test-user' });
    if (url.includes('/immersion_ai_cache?')) return json([]);
    providerCalls++;
    return json({ private: 'provider diagnostic' }, 429);
  }) as typeof fetch, async () => {
    const result = await handle(request());
    assertEquals(result.status, 502);
    assertEquals(await result.json(), { error: 'ai_unavailable' });
    assertEquals(providerCalls, 1);
  });
});

Deno.test('anonymous mode needs an installation id, is quota limited, and never calls the user lookup', async () => {
  const anon = new Request('https://backend.invalid/functions/v1/immersion-explain', {
    method: 'POST', headers: { Authorization: 'Bearer test-public-key', apikey: 'test-public-key', 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'bonjour', sentence: 'Bonjour Marie.', level: 'A1', installationId: '3f2b8f0e-6c1a-4d3b-9a77-0c5d2e1b4a10' }),
  });
  const urls: string[] = [];
  await withFetch((async (input) => {
    const url = String(input); urls.push(url);
    if (url.includes('/immersion_ai_cache?')) return json([]);
    if (url.includes('/rpc/immersion_take_usage')) return json('ip');
    throw new Error('Unexpected network call');
  }) as typeof fetch, async () => {
    const result = await handle(anon);
    assertEquals(result.status, 429);
    assertEquals(await result.json(), { error: 'daily_explanation_limit_reached', limit: 'ip' });
    assertEquals(urls.some((u) => u.endsWith('/auth/v1/user')), false);
  });
  const missingId = new Request('https://backend.invalid/functions/v1/immersion-explain', {
    method: 'POST', headers: { Authorization: 'Bearer test-public-key', apikey: 'test-public-key' },
    body: JSON.stringify({ text: 'bonjour', sentence: 'Bonjour Marie.', level: 'A1' }),
  });
  assertEquals((await handle(missingId)).status, 400);
});
