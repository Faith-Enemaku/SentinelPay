"""Transaction search and retrieval endpoints."""

from flask import Blueprint, jsonify, request

from app.auth import require_auth
from app.db import get_connection

transactions_bp = Blueprint("transactions", __name__)


@transactions_bp.route("/search", methods=["GET"])
@require_auth
def search_transactions():
    """Search transactions belonging to the authenticated user.

    Fixes SQL injection by using parameterised queries.
    Also prevents cross-account access by joining transactions to accounts
    owned by the current user.
    """
    q = request.args.get("q", "")
    account_id = request.args.get("account_id")

    conn = get_connection()
    cur = conn.cursor()

    try:
        like_query = f"%{q}%"

        query = (
            "SELECT t.id, t.account_id, t.reference, t.amount, t.currency, "
            "t.direction, t.counterparty, t.description, t.status, t.created_at "
            "FROM transactions t "
            "JOIN accounts a ON t.account_id = a.id "
            "WHERE a.user_id = %s "
            "AND (t.reference ILIKE %s OR t.counterparty ILIKE %s OR t.description ILIKE %s)"
        )

        params = [request.current_user_id, like_query, like_query, like_query]

        if account_id:
            query += " AND t.account_id = %s"
            params.append(account_id)

        query += " ORDER BY t.created_at DESC LIMIT 50"

        cur.execute(query, tuple(params))
        rows = cur.fetchall()

        return jsonify([dict(row) for row in rows])

    finally:
        cur.close()
        conn.close()


@transactions_bp.route("/<reference>", methods=["GET"])
@require_auth
def get_transaction(reference):
    """Fetch a transaction by reference for the authenticated user only."""
    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "SELECT t.id, t.account_id, t.reference, t.amount, t.currency, "
            "t.direction, t.counterparty, t.description, t.status, t.created_at "
            "FROM transactions t "
            "JOIN accounts a ON t.account_id = a.id "
            "WHERE t.reference = %s AND a.user_id = %s",
            (reference, request.current_user_id),
        )

        row = cur.fetchone()

        if not row:
            return jsonify({"error": "transaction not found"}), 404

        return jsonify(dict(row))

    finally:
        cur.close()
        conn.close()