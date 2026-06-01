"""Internal admin endpoints.

These were originally on a separate internal-only network. The 'separate
internal-only network' never materialised, and the endpoints now ship behind
the same ALB as everything else.
"""
import base64
import json

from flask import Blueprint, request, jsonify

from app.db import get_connection
from app.auth import require_auth

admin_bp = Blueprint("admin", __name__)


@admin_bp.route("/session/restore", methods=["POST"])
@require_auth
def restore_session():
    """Restore an admin session from a base64-encoded JSON blob.

    Previous implementation used pickle.loads(), which is unsafe because
    malicious pickle payloads can execute arbitrary Python code during
    deserialisation. JSON is used here because it only represents data.
    """
    data = request.get_json() or {}
    blob = data.get("session")

    if not blob:
        return jsonify({"error": "session blob required"}), 400

    try:
        raw = base64.b64decode(blob, validate=True)
        session = json.loads(raw.decode("utf-8"))
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
        return jsonify({"error": "Invalid session payload"}), 400

    if not isinstance(session, dict):
        return jsonify({"error": "Session payload must be a JSON object"}), 400

    return jsonify({
        "restored": True,
        "session_keys": list(session.keys())
    })


@admin_bp.route("/users", methods=["GET"])
@require_auth
def list_users():
    """List all users."""
    if request.current_user_role != "admin":
        return jsonify({"error": "admin only"}), 403

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, email, full_name, role, is_active, created_at FROM users")
        return jsonify([dict(r) for r in cur.fetchall()])
    finally:
        cur.close()
        conn.close()