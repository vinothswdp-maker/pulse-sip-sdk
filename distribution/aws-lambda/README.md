# pulse-sip-auth — AWS Lambda backend for PulseSipSdk.registerWithCredentials()

Same contract as [`distribution/cloudflare-worker/`](../cloudflare-worker/)'s
`POST /auth` route — a customer app logs in with `companyCode`/`username`/
`password`, gets back the SIP proxy config (`webSocketUrl`/`sipDomain`/...),
and registers with it. Only difference is where it's hosted: Lambda + a
public Function URL (no API Gateway) + DynamoDB, instead of Cloudflare
Workers + KV. Use this one if you'd rather keep everything in an AWS account
you already have.

The token-based `registerWithConfigUrl()` flow (`GET /config/<token>`) only
exists in the Cloudflare version for now — this directory covers the
credentials flow only.

## One-time setup

Requires the `aws` CLI already authenticated (`aws sts get-caller-identity`
should print your account), plus `node`, `npm`, and `jq` locally.

```bash
cd distribution/aws-lambda
./deploy.sh
```

This creates (safe to re-run — skips anything that already exists):

- DynamoDB table `PulseSipCustomerConfigs` (pay-per-request billing, no
  capacity to plan)
- IAM role `pulse-sip-auth-lambda-role`, scoped to CloudWatch Logs plus
  read/write on just that one table
- Lambda function `pulse-sip-auth` (Node.js 20.x) with a public Function URL

It prints your `baseUrl` at the end, e.g.
`https://abc123xyz.lambda-url.ap-south-1.on.aws`. Override the region/table/
function names via `AWS_REGION`/`TABLE_NAME`/`FUNCTION_NAME`/`ROLE_NAME` env
vars before running if you don't want the defaults (`ap-south-1`,
`PulseSipCustomerConfigs`, `pulse-sip-auth`, `pulse-sip-auth-lambda-role`).

## Adding a company user

`webSocketUrl` and `sipDomain` are the same for every user of a company
(your SIP proxy) — edit the `WEBSOCKET_URL`/`SIP_DOMAIN` constants at the top
of [add-company-user.sh](add-company-user.sh) once for your setup, then:

```bash
./add-company-user.sh ACME 1001 "the-real-password" "Customer Name"
```

`<username>`/`<password>` here ARE the real SIP account credentials (what
the SIP proxy expects for REGISTER) — this writes a DynamoDB item keyed by
`<company_code>:<username>` containing only a salted PBKDF2-SHA256 hash of
the password (never the plaintext) plus the proxy info; `/auth` never stores
or echoes the password back, the app already knows it. It prints the three
values to hand the customer:

```
Company code: ACME
Username:     1001
Password:     the-real-password
```

They pass those straight to the SDK:

```kotlin
PulseSipSdk.registerWithCredentials(
    context,
    baseUrl = "https://abc123xyz.lambda-url.ap-south-1.on.aws",
    companyCode = "ACME",
    username = "1001",
    password = "the-real-password",
) { success -> /* ... */ }
```

`POST /auth` locks a `companyCode:username` pair out for 15 minutes after 10
failed password attempts (tracked in the same table) — a basic guard against
online password guessing, since a `companyCode`/`username` pair is far more
guessable than a random token.

## Revoking a company user

```bash
aws dynamodb update-item \
  --table-name PulseSipCustomerConfigs \
  --region ap-south-1 \
  --key '{"pk": {"S": "ACME:1001"}}' \
  --update-expression 'SET #s = :revoked' \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":revoked": {"S": "revoked"}}'
```

The next login attempt gets a 403 (whatever config the app already cached
locally keeps working until it restarts and logs in again, so pair this with
telling the customer directly if you need it to stop immediately).

## Detecting a leaked login

```bash
aws logs tail /aws/lambda/pulse-sip-auth --follow --region ap-south-1
```

Streams live access logs (`pk`, `ip`, `ts`) as requests come in. Signs a
login has been shared beyond the intended user: the same `companyCode:
username` hit from several distinct IPs in a short window, or a sudden spike
in request volume. This is a visibility/traceability tool, not the actual
security boundary — the real gate is that a leaked login is useless without
also leaking that account's SIP password, which you can rotate on your SIP
server independently of this Lambda.

## Updating the function code

After editing `index.mjs`, just re-run `./deploy.sh` — it detects the
function already exists and pushes new code via `update-function-code`
instead of creating anything new.
