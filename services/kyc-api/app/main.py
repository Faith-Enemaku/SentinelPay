"""SentinelPay KYC API — identity verification service."""
import os

from flask import Flask, jsonify

from app.routes.verify import verify_bp
from app.routes.documents import documents_bp


def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


def create_app():
    app = Flask(__name__)

    # Keep JWT secret optional for backwards compatibility, but do not hardcode a default secret.
    app.config["JWT_SECRET"] = os.environ.get("JWT_SECRET")

    app.register_blueprint(verify_bp, url_prefix="/v1/verify")
    app.register_blueprint(documents_bp, url_prefix="/v1/documents")

    @app.route("/health")
    def health():
        return jsonify({"status": "ok", "service": "kyc-api"})

    return app


if __name__ == "__main__":
    app = create_app()

    host = os.getenv("APP_HOST", "127.0.0.1")
    port = int(os.getenv("APP_PORT", "8002"))
    debug = env_bool("FLASK_DEBUG", False)

    app.run(host=host, port=port, debug=debug)