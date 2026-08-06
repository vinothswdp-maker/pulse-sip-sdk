#!/usr/bin/env bash
# Provisions one customer: generates their token, writes their KV record
# (same webSocketUrl/sipDomain as everyone else, their own sipUser/sipPassword),
# and prints the single URL to hand them.
#
# Usage: ./add-customer.sh <sip_user> <sip_password> <customer_name> [expires_at]
#   expires_at: optional ISO8601 date, e.g. 2027-01-01T00:00:00Z
#
# Requires: wrangler (npm install -g wrangler), jq (brew install jq / apt install jq)
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <sip_user> <sip_password> <customer_name> [expires_at ISO8601]" >&2
  exit 1
fi

# Same for every customer — your SIP proxy. Edit these two once for your setup.
WEBSOCKET_URL="wss://sip.example.com:8089/ws"
SIP_DOMAIN="sip.example.com"
WORKER_BASE_URL="https://pulse-sip-config.<you>.workers.dev"

SIP_USER="$1"
SIP_PASSWORD="$2"
CUSTOMER_NAME="$3"
EXPIRES_AT="${4:-}"

TOKEN=$(openssl rand -hex 24)

RECORD=$(jq -n \
  --arg wsUrl "$WEBSOCKET_URL" \
  --arg user "$SIP_USER" \
  --arg pass "$SIP_PASSWORD" \
  --arg domain "$SIP_DOMAIN" \
  --arg name "$CUSTOMER_NAME" \
  --arg expires "$EXPIRES_AT" \
  '{
    status: "active",
    expiresAt: (if $expires == "" then null else $expires end),
    config: {
      webSocketUrl: $wsUrl,
      sipUser: $user,
      sipPassword: $pass,
      sipDomain: $domain,
      displayName: $name,
      pushContactParams: {},
      allowBadCertificate: false
    }
  }')

wrangler kv:key put --binding=CUSTOMER_CONFIGS "$TOKEN" "$RECORD"

echo ""
echo "Added customer: $CUSTOMER_NAME (sipUser=$SIP_USER)"
echo "Token:          $TOKEN"
echo ""
echo "Give them this URL:"
echo "  $WORKER_BASE_URL/config/$TOKEN"
