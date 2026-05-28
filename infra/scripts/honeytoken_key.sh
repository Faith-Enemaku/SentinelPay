#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:-}"
SECRET_NAME="${2:-}"

if [ -z "$USER_NAME" ] || [ -z "$SECRET_NAME" ]; then
  echo "Usage: ./scripts/create_honeytoken_key.sh <iam-user-name> <secrets-manager-secret-name>"
  exit 1
fi

TMP_FILE="$(mktemp)"

echo "[+] Creating honeytoken access key for IAM user: ${USER_NAME}"
aws iam create-access-key \
  --user-name "${USER_NAME}" \
  --output json > "${TMP_FILE}"

echo "[+] Storing honeytoken key in Secrets Manager: ${SECRET_NAME}"

if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "file://${TMP_FILE}" >/dev/null
else
  aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --description "Honeytoken access key for SentinelPay detection testing. Do not use for real workloads." \
    --secret-string "file://${TMP_FILE}" >/dev/null
fi

shred -u "${TMP_FILE}" 2>/dev/null || rm -f "${TMP_FILE}"

echo "[+] Done. Retrieve the honeytoken only when testing detection."