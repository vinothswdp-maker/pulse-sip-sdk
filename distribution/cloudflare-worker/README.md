# pulse-sip-config — per-customer SIP config server

Serves two Android-side registration flows — no SIP credentials are ever
hardcoded in the customer's app:

- `PulseSipSdk.registerWithConfigUrl()` — customer gets one unguessable URL.
- `PulseSipSdk.registerWithCredentials()` — customer gets a company code,
  username, and password instead (see "Adding a company user" below).

This is a free-tier Cloudflare Worker + KV — no server to run or maintain.

## One-time setup

```bash
npm install -g wrangler
wrangler login
```

Create the KV namespace that stores customer configs, then paste the
printed `id` into `wrangler.toml`:

```bash
wrangler kv:namespace create CUSTOMER_CONFIGS
```

Deploy:

```bash
cd distribution/cloudflare-worker
wrangler deploy
```

This prints your base URL, e.g. `https://pulse-sip-config.<you>.workers.dev`.
(Optional: map a custom domain like `config.yourdomain.com` to it from the
Cloudflare dashboard → Workers → your worker → Settings → Domains.)

## Adding a customer

`webSocketUrl` and `sipDomain` are the same for every customer (your SIP
proxy) — only `sipUser`/`sipPassword` change per customer (their own
extension on your proxy).

**Easiest way** — [add-customer.sh](add-customer.sh) generates the token,
writes the KV record, and prints the URL to hand them (edit the
`WEBSOCKET_URL`/`SIP_DOMAIN`/`WORKER_BASE_URL` constants at the top of the
script once for your setup; requires `wrangler` and `jq`):

```bash
./add-customer.sh 1001 "the-real-password" "Customer Name"
```

**Manual way**, if you'd rather not use the script — generate a token and
write the record yourself:

```bash
TOKEN=$(openssl rand -hex 24)
wrangler kv:key put --binding=CUSTOMER_CONFIGS "$TOKEN" '{
  "status": "active",
  "expiresAt": "2027-01-01T00:00:00Z",
  "config": {
    "webSocketUrl": "wss://sip.example.com:8089/ws",
    "sipUser": "1001",
    "sipPassword": "the-real-password",
    "sipDomain": "sip.example.com",
    "displayName": "Customer Name",
    "pushContactParams": {},
    "allowBadCertificate": false
  }
}'
```

Either way, give the customer the printed URL — that's the single thing
they need:

```
https://pulse-sip-config.<you>.workers.dev/config/<TOKEN>
```

They pass it straight to the SDK:

```kotlin
PulseSipSdk.registerWithConfigUrl(context, "https://pulse-sip-config.<you>.workers.dev/config/<TOKEN>") { success ->
    // ...
}
```

## Revoking a customer

Overwrite their record with `status: "revoked"` — the next fetch gets a 403
and the app's next `register()` call fails (whatever config it already has
cached locally keeps working until the app restarts and re-fetches, so pair
this with telling the customer's contact directly if you need it to stop
immediately):

```bash
wrangler kv:key put --binding=CUSTOMER_CONFIGS "$TOKEN" '{"status": "revoked"}'
```

## Adding a company user (company code + username + password)

For customers who'd rather type three short values into an app than paste a
URL, [add-company-user.sh](add-company-user.sh) provisions a login for
`PulseSipSdk.registerWithCredentials()` (edit the `WEBSOCKET_URL`/`SIP_DOMAIN`
constants at the top once for your setup; requires `wrangler`, `jq`, and
`node`):

```bash
./add-company-user.sh ACME 1001 "the-real-password" "Customer Name"
```

`<username>`/`<password>` here ARE the real SIP account credentials (what the
SIP proxy expects for REGISTER) — this writes a KV record keyed by
`<company_code>:<username>` containing only a salted PBKDF2-SHA256 hash of the
password (never the plaintext) plus the proxy info (`webSocketUrl`/
`sipDomain`); `/auth` never stores or echoes the password back, the app
already knows it. It prints the three values to hand the customer:

```
Company code: ACME
Username:     1001
Password:     the-real-password
```

They pass those straight to the SDK:

```kotlin
PulseSipSdk.registerWithCredentials(
    context,
    baseUrl = "https://pulse-sip-config.<you>.workers.dev",
    companyCode = "ACME",
    username = "1001",
    password = "the-real-password",
) { success -> /* ... */ }
```

`POST /auth` locks a `companyCode:username` pair out for 15 minutes after 10
failed password attempts (tracked in the same KV namespace) — a basic guard
against online password guessing, since a `companyCode`/`username` pair is
far more guessable than the unguessable tokens the URL flow uses. Revoke a
company user's access the same way as a token (`status: "revoked"` on their
`<company_code>:<username>` record).

## Detecting a leaked link

```bash
wrangler tail
```

Streams live access logs (`token`, `ip`, `country`, `userAgent`, `ts`) as
requests come in. Signs a link has been shared beyond the intended customer:
the same token hit from several distinct IPs/countries in a short window, or
a sudden spike in request volume for one token. Cross-check against
`count:<TOKEN>` in KV (`wrangler kv:key get --binding=CUSTOMER_CONFIGS
"count:$TOKEN"`) for a running total since the customer was provisioned.

This link is a visibility/traceability tool, not the actual security
boundary — the real gate is that a leaked link is useless without also
leaking that specific customer's SIP credentials, which you can rotate on
your SIP server independently of this Worker.
