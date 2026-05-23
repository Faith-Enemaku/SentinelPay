"""Authentication helpers for kyc-api."""

import os
from functools import wraps

import jwt
from flask import jsonify, request

JWT_SECRET = os.environ.get("JWT_SECRET")

if not JWT_SECRET:
    raise RuntimeError("JWT_SECRET must be set")

JWT_ALGORITHM = "HS256"
JWT_ISSUER = "sentinelpay-payments-api"


def decode_token(token: str) -> dict:
    """Decode and verify a JWT issued by the payments API."""
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