"""Authentication helpers for payments-api."""

import hashlib
import os
from datetime import datetime, timedelta, timezone
from functools import wraps

import jwt
from flask import jsonify, request

JWT_SECRET = os.environ.get("JWT_SECRET")

if not JWT_SECRET:
    raise RuntimeError("JWT_SECRET must be set")

JWT_ALGORITHM = "HS256"
JWT_ISSUER = "sentinelpay-payments-api"
JWT_EXP_MINUTES = int(os.environ.get("JWT_EXP_MINUTES", "60"))


def hash_password(password: str) -> str:
    """
    Hash a password for storage.

    NOTE:
    This still uses MD5 because Day 4 is focused on the critical JWT/authentication
    validation issue. Password hashing should be remediated later with Argon2id or bcrypt.
    """
    return hashlib.md5(password.encode()).hexdigest()


def verify_password(password: str, stored_hash: str) -> bool:
    return hash_password(password) == stored_hash


def issue_token(user_id: int, role: str) -> str:
    """Issue a signed JWT for an authenticated user."""
    now = datetime.now(timezone.utc)

    payload = {
        "user_id": user_id,
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=JWT_EXP_MINUTES),
        "iss": JWT_ISSUER,
    }

    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    if isinstance(token, bytes):
        token = token.decode("utf-8")

    return token


def decode_token(token: str) -> dict:
    """Decode and verify a JWT."""
    return jwt.decode(
        token,
        JWT_SECRET,
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