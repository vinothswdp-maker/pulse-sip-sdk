/**
 * Serves each customer's SIP config from KV, two ways:
 *
 *   GET  /config/<token>                 ->  200 { webSocketUrl, sipUser, sipPassword, sipDomain, ... }
 *   POST /auth  { companyCode, username, password }  ->  200 { ...same shape... }
 *
 * The Android app calls these at runtime via PulseSipSdk.registerWithConfigUrl(context, url)
 * or PulseSipSdk.registerWithCredentials(context, baseUrl, companyCode, username, password) —
 * it never needs to hardcode SIP credentials.
 *
 * KV value shape for the token flow, one entry per customer (see README.md):
 *   {
 *     "status": "active" | "revoked",
 *     "expiresAt": "2027-01-01T00:00:00Z",   // optional
 *     "config": { ...PulseSipConfig fields... }
 *   }
 *
 * KV value shape for the credentials flow, keyed by "<companyCode>:<username>"
 * (see README.md, provisioned via add-company-user.sh):
 *   {
 *     "status": "active" | "revoked",
 *     "expiresAt": "2027-01-01T00:00:00Z",   // optional
 *     "salt": "<hex>",
 *     "passwordHash": "<hex, PBKDF2-SHA256(password, salt, 100000 iterations)>",
 *     "config": { ...PulseSipConfig fields... }
 *   }
 */
const MAX_FAILED_ATTEMPTS = 10;
const FAILED_ATTEMPT_LOCKOUT_SECONDS = 900; // 15 minutes
const PBKDF2_ITERATIONS = 100000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    const tokenMatch = url.pathname.match(/^\/config\/([A-Za-z0-9_-]{16,64})$/);
    if (request.method === 'GET' && tokenMatch) {
      return handleTokenConfig(request, env, tokenMatch[1]);
    }

    if (request.method === 'POST' && url.pathname === '/auth') {
      return handleAuth(request, env);
    }

    return new Response('Not found', { status: 404 });
  },
};

async function handleTokenConfig(request, env, token) {
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

  await bumpAccessCount(env, `count:${token}`);

  return jsonResponse(record.config);
}

async function handleAuth(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { companyCode, username, password } = body ?? {};
  if (!companyCode || !username || !password) {
    return new Response('Bad request', { status: 400 });
  }

  const key = `${companyCode}:${username}`;
  const failKey = `fail:${key}`;

  const failCount = parseInt((await env.CUSTOMER_CONFIGS.get(failKey)) ?? '0', 10);
  if (failCount >= MAX_FAILED_ATTEMPTS) {
    return new Response('Too many attempts, try again later', { status: 429 });
  }

  const raw = await env.CUSTOMER_CONFIGS.get(key);
  if (!raw) {
    await recordFailedAttempt(env, failKey);
    return new Response('Invalid credentials', { status: 401 });
  }

  let record;
  try {
    record = JSON.parse(raw);
  } catch {
    return new Response('Server error', { status: 500 });
  }

  // Same visibility tooling as the token flow — see README.md "Detecting a leaked link".
  logAccess(request, key);

  if (record.status !== 'active') {
    return new Response('Access revoked', { status: 403 });
  }
  if (record.expiresAt && new Date(record.expiresAt).getTime() < Date.now()) {
    return new Response('Login expired', { status: 403 });
  }

  const candidateHash = await hashPassword(password, record.salt);
  if (candidateHash !== record.passwordHash) {
    await recordFailedAttempt(env, failKey);
    return new Response('Invalid credentials', { status: 401 });
  }

  await env.CUSTOMER_CONFIGS.delete(failKey);
  await bumpAccessCount(env, `count:${key}`);

  return jsonResponse(record.config);
}

function jsonResponse(config) {
  return new Response(JSON.stringify(config), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

function logAccess(request, key) {
  console.log(JSON.stringify({
    key,
    ip: request.headers.get('CF-Connecting-IP'),
    country: request.headers.get('CF-IPCountry'),
    userAgent: request.headers.get('User-Agent'),
    ts: new Date().toISOString(),
  }));
}

async function bumpAccessCount(env, countKey) {
  const current = parseInt((await env.CUSTOMER_CONFIGS.get(countKey)) ?? '0', 10);
  await env.CUSTOMER_CONFIGS.put(countKey, String(current + 1));
}

async function recordFailedAttempt(env, failKey) {
  const current = parseInt((await env.CUSTOMER_CONFIGS.get(failKey)) ?? '0', 10);
  await env.CUSTOMER_CONFIGS.put(failKey, String(current + 1), {
    expirationTtl: FAILED_ATTEMPT_LOCKOUT_SECONDS,
  });
}

/** Must match hash-password.mjs exactly (same algorithm/iterations/salt/output length). */
async function hashPassword(password, saltHex) {
  const salt = hexToBytes(saltHex);
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
    keyMaterial,
    256,
  );
  return bytesToHex(new Uint8Array(bits));
}

function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}

function bytesToHex(bytes) {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}
