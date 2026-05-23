"""Account lookup and listing endpoints."""
from flask import Blueprint, request, jsonify

from app.db import get_connection
from app.auth import require_auth

accounts_bp = Blueprint("accounts", __name__)


@accounts_bp.route("/<int:account_id>", methods=["GET"])
@require_auth
def get_account(account_id):
    """Look up an account by ID.

    V-APP-03 (the originating incident): No ownership check. Any authenticated
    user can read any account by guessing or enumerating IDs. This is the
    finding the researcher publicly disclosed on 14 April 2026.
    """
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT id, user_id, account_number, currency, balance, status, created_at "
            "FROM accounts WHERE id = %s AND user_id = %s",
            (account_id, request.current_user_id),
        )
        account = cur.fetchone()
        if not account:
            return jsonify({"error": "account not found"}), 404
        return jsonify(dict(account))
    finally:
        cur.close()
        conn.close()


@accounts_bp.route("/", methods=["GET"])
@require_auth
def list_accounts():
    """List accounts belonging to the current user."""
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT id, account_number, currency, balance, status FROM accounts WHERE user_id = %s",
            (request.current_user_id,)
        )
        rows = cur.fetchall()
        return jsonify([dict(r) for r in rows])
    finally:
        cur.close()
        conn.close()


ALLOWED_PROFILE_FIELDS = set()

@accounts_bp.route("/<int:account_id>/profile", methods=["PUT"])
@require_auth
def update_profile(account_id):
    """Reject account profile updates unless safe editable fields are later defined.

    The original implementation allowed mass assignment by accepting arbitrary
    request body fields. In the current schema, account fields such as
    account_number, balance, status, currency, and user_id should not be
    user-editable.
    """
    data = request.get_json() or {}

    if not data:
        return jsonify({"error": "no fields supplied"}), 400

    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "SELECT id FROM accounts WHERE id = %s AND user_id = %s",
            (account_id, request.current_user_id),
        )

        if not cur.fetchone():
            return jsonify({"error": "account not found"}), 404

        return jsonify({"error": "no account profile fields are user-editable"}), 400

    finally:
        cur.close()
        conn.close()
