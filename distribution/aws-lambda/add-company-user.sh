#!/usr/bin/env bash
# Provisions one (companyCode, username) login for the credentials-based register flow
# (PulseSipSdk.registerWithCredentials) — the customer's app only ever needs a company
# code, a username, and a password; it never sees webSocketUrl/sipDomain.
#
# <username>/<password> ARE the real SIP account credentials (what the SIP proxy expects
# for REGISTER) — this only stores a salted PBKDF2-SHA256 hash of the password, never the
# plaintext, and /auth never echoes it back either.
#
# Usage: ./add-company-user.sh <company_code> <username> <password> <customer_name> [expires_at]
#   expires_at: optional ISO8601 date, e.g. 2027-01-01T00:00:00Z
#
# Requires: aws CLI (configured/authenticated), node
set -euo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: $0 <company_code> <username> <password> <customer_name> [expires_at ISO8601]" >&2
  exit 1
fi

# Same for every user of this company — your SIP proxy. Edit these two once for your
# setup (or run separate provisioning per company if different companies use different
# proxies — just change these two lines before running for that company).
WEBSOCKET_URL="wss://sip.example.com:8089/ws"
SIP_DOMAIN="sip.example.com"

TABLE_NAME="${TABLE_NAME:-PulseSipCustomerConfigs}"
REGION="${AWS_REGION:-ap-south-1}"

COMPANY_CODE="$1"
USERNAME="$2"
PASSWORD="$3"
CUSTOMER_NAME="$4"
EXPIRES_AT="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASH_JSON=$(node "$SCRIPT_DIR/hash-password.mjs" "$PASSWORD")
SALT=$(echo "$HASH_JSON" | jq -r '.salt')
PASSWORD_HASH=$(echo "$HASH_JSON" | jq -r '.passwordHash')

ITEM=$(jq -n \
  --arg pk "${COMPANY_CODE}:${USERNAME}" \
  --arg salt "$SALT" \
  --arg hash "$PASSWORD_HASH" \
  --arg wsUrl "$WEBSOCKET_URL" \
  --arg domain "$SIP_DOMAIN" \
  --arg name "$CUSTOMER_NAME" \
  --arg expires "$EXPIRES_AT" \
  '{
    pk: {S: $pk},
    status: {S: "active"},
    expiresAt: (if $expires == "" then {NULL: true} else {S: $expires} end),
    salt: {S: $salt},
    passwordHash: {S: $hash},
    config: {M: {
      webSocketUrl: {S: $wsUrl},
      sipDomain: {S: $domain},
      displayName: {S: $name},
      pushContactParams: {M: {}},
      allowBadCertificate: {BOOL: false}
    }}
  }')

aws dynamodb put-item --table-name "$TABLE_NAME" --region "$REGION" --item "$ITEM"

echo ""
echo "Added user: $CUSTOMER_NAME (company=$COMPANY_CODE, username=$USERNAME)"
echo ""
echo "Give them these three values — that's all their app needs:"
echo "  Company code: $COMPANY_CODE"
echo "  Username:     $USERNAME"
echo "  Password:     $PASSWORD"
