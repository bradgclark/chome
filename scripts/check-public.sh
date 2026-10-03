#!/bin/sh
# Fail if a tracked file carries something that marks it as a real household export
# rather than a sanitized example. This repo is public.
#
# Always checked: private (RFC 1918) IPv4 addresses and email addresses.
# Also checked when set: PRIVATE_PATTERNS, an extended regex of this household's own
# hostnames, domains and names. It is kept OUT of the repo (a GitHub Actions variable,
# or your shell), because listing those values here would publish them.
#
# Use placeholders instead: 192.168.1.x (a literal x), the documentation ranges
# 192.0.2.0/24 and 198.51.100.0/24, and example.com addresses.
set -eu

cd "$(git rev-parse --show-toplevel)"
status=0

rfc1918='(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
if git grep -nIE "$rfc1918" -- . ':!scripts/check-public.sh'; then
  echo "error: private IP address above; replace it with a placeholder" >&2
  status=1
fi

email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
allowed_email='@(example\.(com|org|net)|users\.noreply\.github\.com|anthropic\.com)'
if git grep -nIE "$email" -- . ':!scripts/check-public.sh' | grep -vE "$allowed_email"; then
  echo "error: email address above; use an example.com placeholder" >&2
  status=1
fi

if [ -n "${PRIVATE_PATTERNS:-}" ]; then
  if git grep -nIiE "$PRIVATE_PATTERNS" -- . ':!scripts/check-public.sh' >/dev/null; then
    git grep -lIiE "$PRIVATE_PATTERNS" -- . ':!scripts/check-public.sh' | sed 's/^/private value in: /' >&2
    status=1
  fi
else
  echo "note: PRIVATE_PATTERNS not set; household names and domains were not checked"
fi

[ "$status" -eq 0 ] && echo "public check: clean"
exit "$status"
