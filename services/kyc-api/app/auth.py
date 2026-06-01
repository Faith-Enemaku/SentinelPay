"""Authentication helpers for kyc-api."""

import json
import os
from functools import wraps
from pathlib import Path
from typing import Optional

import jwt
from flask import jsonify, request

JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "RS256")
JWT_ISSUER = os.environ.get("JWT_ISSUER", "sentinelpay-payments-api")
JWT_ACTIVE_KID = os.environ.get("JWT_ACTIVE_KID", "dev-key-1")

# Local development path
JWT_PUBLIC_KEYS_PATH = os.environ.get("JWT_PUBLIC_KEYS_PATH")

# ECS/Secrets Manager injected values
JWT_PUBLIC_KEY_PEM = os.environ.get("JWT_PUBLIC_KEY_PEM")
JWT_PUBLIC_KEYS_JSON = os.environ.get("JWT_PUBLIC_KEYS_JSON")


def normalise_pem(value: Optional[str]) -> Optional[str]:
    """Convert escaped newlines from env vars back into real PEM newlines."""
    if not value:
        return None

    value = value.strip()

    if "\\n" in value:
        value = value.replace("\\n", "\n")

    return value


def read_file(path: Optional[str]) -> Optional[str]:
    """Read a local file when running outside ECS."""
    if not path:
        return None

    file_path = Path(path)

    if not file_path.exists():
        return None

    return file_path.read_text(encoding="utf-8")


def load_public_keys() -> dict:
    """Load public keys used to verify JWTs by key ID.

    Supported options:
    1. ECS/Secrets Manager: JWT_PUBLIC_KEYS_JSON
    2. ECS/Secrets Manager: JWT_PUBLIC_KEY_PEM
    3. Local development: JWT_PUBLIC_KEYS_PATH
    """

    if JWT_PUBLIC_KEYS_JSON:
        try:
            parsed_keys = json.loads(JWT_PUBLIC_KEYS_JSON)
        except json.JSONDecodeError as exc:
            raise RuntimeError("JWT_PUBLIC_KEYS_JSON is not valid JSON") from exc

        if not isinstance(parsed_keys, dict):
            raise RuntimeError("JWT_PUBLIC_KEYS_JSON must be a JSON object")

        return {
            kid: normalise_pem(public_key)
            for kid, public_key in parsed_keys.items()
        }

    public_key = normalise_pem(JWT_PUBLIC_KEY_PEM)

    if public_key:
        return {
            JWT_ACTIVE_KID: public_key
        }

    public_keys_file = read_file(JWT_PUBLIC_KEYS_PATH)

    if public_keys_file:
        try:
            parsed_keys = json.loads(public_keys_file)
        except json.JSONDecodeError as exc:
            raise RuntimeError("JWT public keys file is not valid JSON") from exc

        if not isinstance(parsed_keys, dict):
            raise RuntimeError("JWT public keys file must contain a JSON object")

        return {
            kid: normalise_pem(public_key)
            for kid, public_key in parsed_keys.items()
        }

    raise RuntimeError(
        "JWT public keys not configured. Set JWT_PUBLIC_KEYS_JSON, "
        "JWT_PUBLIC_KEY_PEM, or JWT_PUBLIC_KEYS_PATH."
    )


JWT_PUBLIC_KEYS = load_public_keys()


def decode_token(token: str) -> dict:
    """Decode and verify a JWT issued by the payments API."""
    try:
        header = jwt.get_unverified_header(token)
    except jwt.InvalidTokenError as exc:
        raise jwt.InvalidTokenError("invalid token header") from exc

    if header.get("alg") != JWT_ALGORITHM:
        raise jwt.InvalidTokenError("unexpected signing algorithm")

    kid = header.get("kid")
    if not kid:
        raise jwt.InvalidTokenError("missing key id")

    public_key = JWT_PUBLIC_KEYS.get(kid)
    if not public_key:
        raise jwt.InvalidTokenError("unknown key id")

    return jwt.decode(
        token,
        public_key,
        algorithms=[JWT_ALGORITHM],
        issuer=JWT_ISSUER,
    )


def require_auth(f):
    """Decorator that extracts the current user from the Authorization header."""

    @wraps(f)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")

        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "missing or malformed Authorization header"}), 401

        token = auth_header.replace("Bearer ", "", 1)

        try:
            payload = decode_token(token)
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "invalid token"}), 401

        request.current_user_id = payload.get("user_id")
        request.current_user_role = payload.get("role")

        if not request.current_user_id:
            return jsonify({"error": "invalid token"}), 401

        return f(*args, **kwargs)

    return wrapper