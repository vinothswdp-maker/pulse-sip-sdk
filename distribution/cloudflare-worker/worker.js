/**
 * Serves each customer's SIP config from KV, keyed by an unguessable token in the URL path:
 *
 *   GET /config/<token>  ->  200 { webSocketUrl, sipUser, sipPassword, sipDomain, ... }
 *
 * The Android app calls this at runtime via PulseSipSdk.registerWithConfigUrl(context, url) —
 * it never needs to hardcode SIP credentials.
 *
 * KV value shape, one entry per customer (see README.md for how to write one):
 *   {
 *     "status": "active" | "revoked",
 *     "expiresAt": "2027-01-01T00:00:00Z",   // optional
 *     "config": { ...PulseSipConfig fields... }
 *   }
 */
export default {
  async fetch(request, env) {
    if (request.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 });
    }

    const url = new URL(request.url);
    const match = url.pathname.match(/^\/config\/([A-Za-z0-9_-]{16,64})$/);
    if (!match) {
      return new Response('Not found', { status: 404 });
    }
    const token = match[1];

    const raw = await env.CUSTOMER_CONFIGS.get(token);
    if (!raw) {
      return new Response('Not found', { status: 404 });
    }

    let record;
    try {
      record = JSON.parse(raw);
    } catch {
      return new Response('Server error', { status: 500 });
    }

    // Log every access so unusual patterns (same token, many distinct IPs/countries) are
    // visible via `wrangler tail` or Logpush — see README.md "Detecting a leaked link".
    logAccess(request, token);

    if (record.status !== 'active') {
      return new Response('Access revoked', { status: 403 });
    }
    if (record.expiresAt && new Date(record.expiresAt).getTime() < Date.now()) {
      return new Response('Link expired', { status: 403 });
    }

    await bumpAccessCount(env, token);

    return new Response(JSON.stringify(record.config), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      },
    });
  },
};

function logAccess(request, token) {
  console.log(JSON.stringify({
    token,
    ip: request.headers.get('CF-Connecting-IP'),
    country: request.headers.get('CF-IPCountry'),
    userAgent: request.headers.get('User-Agent'),
    ts: new Date().toISOString(),
  }));
}

async function bumpAccessCount(env, token) {
  const key = `count:${token}`;
  const current = parseInt((await env.CUSTOMER_CONFIGS.get(key)) ?? '0', 10);
  await env.CUSTOMER_CONFIGS.put(key, String(current + 1));
}
