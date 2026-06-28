#!/usr/bin/env bash
#
# Verify that your Tesla Fleet app public key is correctly hosted.
#
# Tesla (and the Home Assistant Tesla Fleet integration) require your *public* key to be
# reachable over public HTTPS at:
#   https://<your-subdomain>/.well-known/appspecific/com.tesla.3p.public-key.pem
#
# This script confirms that URL returns HTTP 200 with a valid PEM public key, so you can
# catch hosting problems BEFORE trying to pair the virtual key with the car.
#
# Usage:
#   ./scripts/verify.sh tesla.example.com
#   DOMAIN=tesla.example.com ./scripts/verify.sh

set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"

if [[ -z "${DOMAIN}" ]]; then
  echo "Usage: $0 <your-subdomain>    (e.g. $0 tesla.example.com)" >&2
  echo "   or: DOMAIN=tesla.example.com $0" >&2
  exit 2
fi

# Strip any scheme/trailing slash the user may have pasted in.
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN%%/*}"

URL="https://${DOMAIN}/.well-known/appspecific/com.tesla.3p.public-key.pem"
echo "Checking: ${URL}"
echo

# Fetch headers + body; -f makes curl fail on HTTP >= 400.
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

http_code="$(curl -fsS -o "${tmp}" -w '%{http_code}' "${URL}" 2>/dev/null || true)"

if [[ "${http_code}" != "200" ]]; then
  echo "FAIL: expected HTTP 200, got '${http_code:-no response}'." >&2
  echo "      The file is not reachable. Check the deploy, the custom domain binding," >&2
  echo "      and that DNS/HTTPS have finished provisioning." >&2
  exit 1
fi

if ! grep -q -- "-----BEGIN PUBLIC KEY-----" "${tmp}"; then
  echo "FAIL: URL returned 200 but the body is not a PEM public key." >&2
  echo "----- response body (first 20 lines) -----" >&2
  head -n 20 "${tmp}" >&2
  exit 1
fi

if grep -q "REPLACE_ME" "${tmp}"; then
  echo "FAIL: this is still the placeholder key. Paste the real public key shown by" >&2
  echo "      Home Assistant into docs/.well-known/appspecific/com.tesla.3p.public-key.pem" >&2
  echo "      and redeploy." >&2
  exit 1
fi

# Best-effort structural validation if openssl is available.
if command -v openssl >/dev/null 2>&1; then
  if openssl pkey -pubin -in "${tmp}" -noout >/dev/null 2>&1; then
    echo "PASS: HTTP 200 and a valid, parseable PEM public key is being served."
  else
    echo "WARN: HTTP 200 and PEM markers present, but openssl could not parse the key." >&2
    echo "      Double-check you copied the full key block from Home Assistant." >&2
    exit 1
  fi
else
  echo "PASS: HTTP 200 and a PEM public key is being served (openssl not found, skipped deep parse)."
fi
