"""SentinelPay Payments API — main entrypoint."""
import logging
import os

from flask import Flask, jsonify

from app.routes.auth import auth_bp
from app.routes.accounts import accounts_bp
from app.routes.transactions import transactions_bp
from app.routes.wallets import wallets_bp
from app.routes.webhooks import webhooks_bp
from app.routes.admin import admin_bp


def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


def create_app():
    app = Flask(__name__)

    app.config["ENVIRONMENT"] = os.environ.get("ENVIRONMENT", "development")

    # Keep JWT secret optional for backwards compatibility, but do not hardcode a default secret.
    app.config["JWT_SECRET"] = os.environ.get("JWT_SECRET")

    app.register_blueprint(auth_bp, url_prefix="/v1/auth")
    app.register_blueprint(accounts_bp, url_prefix="/v1/accounts")
    app.register_blueprint(transactions_bp, url_prefix="/v1/transactions")
    app.register_blueprint(wallets_bp, url_prefix="/v1/wallets")
    app.register_blueprint(webhooks_bp, url_prefix="/v1/webhooks")
    app.register_blueprint(admin_bp, url_prefix="/v1/admin")

    @app.route("/health")
    def health():
        return jsonify({"status": "ok", "service": "payments-api"})

    @app.errorhandler(Exception)
    def handle_exception(error):
        logging.exception("Unhandled exception in payments-api")
        return jsonify({"error": "Internal server error"}), 500

    return app


if __name__ == "__main__":
    app = create_app()

    host = os.getenv("APP_HOST", "0.0.0.0")
    port = int(os.getenv("APP_PORT", os.getenv("PORT", "8001")))
    debug = env_bool("FLASK_DEBUG", False)

    app.run(host=host, port=port, debug=debug)