// Lambda equivalent of distribution/cloudflare-worker/worker.js's POST /auth route —
// same PulseSipSdk.registerWithCredentials() contract, backed by DynamoDB instead of
// Cloudflare KV. Deployed behind a Lambda Function URL (see deploy.sh), no API Gateway.
//
// DynamoDB item shape, one per company user, partition key "pk" = "<companyCode>:<username>"
// (provisioned via add-company-user.sh):
//   {
//     pk: "ACME:1001",
//     status: "active" | "revoked",
//     expiresAt: "2027-01-01T00:00:00Z" | null,
//     salt: "<hex>",
//     passwordHash: "<hex, PBKDF2-SHA256(password, salt, 100000 iterations)>",
//     config: { webSocketUrl, sipDomain, displayName, pushContactParams, allowBadCertificate }
//   }
//
// Failed-login lockout uses a second item per key, "fail:<companyCode>:<username>",
// holding { count, resetAt } — checked/reset in code rather than relying on DynamoDB's
// background TTL sweep (which isn't immediate), though ttl is still set for eventual cleanup.
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { pbkdf2Sync, timingSafeEqual } from 'node:crypto';

const TABLE_NAME = process.env.TABLE_NAME ?? 'PulseSipCustomerConfigs';
const MAX_FAILED_ATTEMPTS = 10;
const FAILED_ATTEMPT_LOCKOUT_SECONDS = 900; // 15 minutes
const PBKDF2_ITERATIONS = 100000;

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export const handler = async (event) => {
  const method = event.requestContext?.http?.method ?? 'GET';
  const path = event.rawPath ?? '/';

  if (method === 'POST' && path === '/auth') {
    return handleAuth(event);
  }

  return response(404, { error: 'Not found' });
};

async function handleAuth(event) {
  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return response(400, { error: 'Bad request' });
  }

  const { companyCode, username, password } = body;
  if (!companyCode || !username || !password) {
    return response(400, { error: 'Bad request' });
  }

  const pk = `${companyCode}:${username}`;
  const failPk = `fail:${pk}`;

  if (await isLockedOut(failPk)) {
    return response(429, { error: 'Too many attempts, try again later' });
  }

  const { Item: record } = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { pk } }));
  if (!record) {
    await recordFailedAttempt(failPk);
    return response(401, { error: 'Invalid credentials' });
  }

  // Same visibility you'd get from `wrangler tail` — check CloudWatch Logs for this
  // function to spot unusual access patterns (same account, many distinct IPs).
  console.log(JSON.stringify({ pk, ip: event.requestContext?.http?.sourceIp, ts: new Date().toISOString() }));

  if (record.status !== 'active') {
    return response(403, { error: 'Access revoked' });
  }
  if (record.expiresAt && new Date(record.expiresAt).getTime() < Date.now()) {
    return response(403, { error: 'Login expired' });
  }

  const candidateHash = hashPassword(password, record.salt);
  if (!timingSafeCompare(candidateHash, record.passwordHash)) {
    await recordFailedAttempt(failPk);
    return response(401, { error: 'Invalid credentials' });
  }

  await ddb.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { pk: failPk } }));

  // Never echo sipUser/sipPassword — the app already knows them, they're exactly what
  // it just sent in this request.
  const { sipUser, sipPassword, ...proxyConfig } = record.config ?? {};
  return response(200, proxyConfig);
}

async function isLockedOut(failPk) {
  const { Item } = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { pk: failPk } }));
  if (!Item) return false;
  if (Date.now() > Item.resetAt) return false; // window expired, treat as no attempts
  return Item.count >= MAX_FAILED_ATTEMPTS;
}

async function recordFailedAttempt(failPk) {
  const { Item } = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { pk: failPk } }));
  const now = Date.now();
  const stillInWindow = Item && now <= Item.resetAt;
  const count = stillInWindow ? Item.count + 1 : 1;
  const resetAt = stillInWindow ? Item.resetAt : now + FAILED_ATTEMPT_LOCKOUT_SECONDS * 1000;

  await ddb.send(new PutCommand({
    TableName: TABLE_NAME,
    Item: {
      pk: failPk,
      count,
      resetAt,
      ttl: Math.floor(resetAt / 1000) + FAILED_ATTEMPT_LOCKOUT_SECONDS,
    },
  }));
}

/** Must match hash-password.mjs exactly (same algorithm/iterations/salt/output length). */
function hashPassword(password, saltHex) {
  return pbkdf2Sync(password, Buffer.from(saltHex, 'hex'), PBKDF2_ITERATIONS, 32, 'sha256').toString('hex');
}

function timingSafeCompare(hexA, hexB) {
  const bufA = Buffer.from(hexA, 'hex');
  const bufB = Buffer.from(hexB, 'hex');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

function response(statusCode, bodyObj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    body: JSON.stringify(bodyObj),
  };
}
