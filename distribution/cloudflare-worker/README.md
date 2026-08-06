# pulse-sip-config — per-customer SIP config server

Serves `PulseSipSdk.registerWithConfigUrl()` on the Android side. Each
customer gets one URL; no SIP credentials are hardcoded in their app.

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
