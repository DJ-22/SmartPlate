"""
Minimal smoke tests. These do NOT hit MySQL — they only verify
the FastAPI app imports and a few route-level behaviours hold.
Run from the backend/ directory:
    pytest tests/
"""
import os
import sys
from pathlib import Path

# Ensure env vars the app expects at import time are present
os.environ.setdefault("DB_PASS", "smoketest")
os.environ.setdefault("JWT_SECRET", "smoketest-secret")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402
import main  # noqa: E402

client = TestClient(main.app)


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_login_requires_body():
    r = client.post("/api/v1/login")
    assert r.status_code == 422


def test_protected_endpoint_without_token():
    r = client.get("/api/v1/manager/ingredients")
    # FastAPI HTTPBearer returns 403 when the Authorization header is missing
    assert r.status_code in (401, 403)


def test_password_hash_roundtrip():
    from auth import hash_password, verify_password
    h = hash_password("password123")
    assert verify_password("password123", h)
    assert not verify_password("wrong", h)


def test_cors_restricts_unknown_origin():
    # Preflight from a non-whitelisted origin should NOT echo the origin back
    r = client.options(
        "/api/v1/login",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert r.headers.get("access-control-allow-origin") != "https://evil.example.com"
