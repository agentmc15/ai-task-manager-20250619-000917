"""
Archer connectivity smoke test.

Read-only validation that the Clarity service account can reach ArcherPOC,
authenticate, exercise the session token against a real GET, and log out
cleanly. Does NOT create, update, or delete any content.

Run from inside the clarity-api container so it inherits the same network,
proxy, and CA bundle as the real publisher will:

    docker compose -f docker-compose.production.yaml exec clarity-api \
        python scripts/archer_smoke_test.py

Required environment variables (set in .env):
    ARCHER_BASE_URI       e.g. https://archerpoc.corp.ray.com
    ARCHER_INSTANCE_NAME  e.g. ArcherPOC_PROD
    ARCHER_USERNAME       e.g. API-Clarity
    ARCHER_PASSWORD       (service account password)

Optional:
    ARCHER_USER_DOMAIN    defaults to "" (empty string for local accounts)
    ARCHER_VERIFY_SSL     defaults to "false" (with a loud warning)

Exit codes:
    0 = all steps passed
    1 = any step failed or required config missing
"""

from __future__ import annotations

import os
import sys
from typing import Any

import httpx


# ---------- tiny output helpers (no external deps) ----------

def _step(msg: str) -> None:
    print(f"\n--- {msg} ---", flush=True)


def _ok(msg: str) -> None:
    print(f"  [OK]   {msg}", flush=True)


def _fail(msg: str) -> None:
    print(f"  [FAIL] {msg}", flush=True)


def _info(msg: str) -> None:
    print(f"         {msg}", flush=True)


def _warn(msg: str) -> None:
    print(f"  [WARN] {msg}", flush=True)


def _mask_token(token: str) -> str:
    if not token:
        return "<empty>"
    if len(token) <= 8:
        return "*" * len(token)
    return f"{token[:8]}... ({len(token)} chars)"


# ---------- config loading ----------

def _load_config() -> dict[str, Any]:
    """Pull all Archer settings from os.environ. Standalone on purpose:
    we do NOT import clarity.core.settings so a Pydantic validation error
    elsewhere can't block this script."""
    required = {
        "ARCHER_BASE_URI": os.environ.get("ARCHER_BASE_URI", "").strip(),
        "ARCHER_INSTANCE_NAME": os.environ.get("ARCHER_INSTANCE_NAME", "").strip(),
        "ARCHER_USERNAME": os.environ.get("ARCHER_USERNAME", "").strip(),
        "ARCHER_PASSWORD": os.environ.get("ARCHER_PASSWORD", ""),
    }

    missing = [k for k, v in required.items() if not v]
    if missing:
        _fail(f"Missing required env vars: {', '.join(missing)}")
        sys.exit(1)

    # Normalize base URI: strip trailing slash so we can concat /api/... cleanly
    base_uri = required["ARCHER_BASE_URI"].rstrip("/")

    user_domain = os.environ.get("ARCHER_USER_DOMAIN", "")  # empty string OK

    verify_ssl_raw = os.environ.get("ARCHER_VERIFY_SSL", "false").strip().lower()
    verify_ssl = verify_ssl_raw in ("true", "1", "yes", "on")

    return {
        "base_uri": base_uri,
        "instance_name": required["ARCHER_INSTANCE_NAME"],
        "username": required["ARCHER_USERNAME"],
        "password": required["ARCHER_PASSWORD"],
        "user_domain": user_domain,
        "verify_ssl": verify_ssl,
    }


# ---------- the three test steps ----------

def step_login(client: httpx.Client, cfg: dict[str, Any]) -> str | None:
    """POST /api/core/security/login - returns session token or None on failure.

    Body shape mirrors the C# ArcLogin method exactly:
        {"InstanceName": ..., "Username": ..., "UserDomain": ..., "Password": ...}
    Token comes back at RequestedObject.SessionToken.
    """
    _step("Step 1/3: Login")

    url = f"{cfg['base_uri']}/api/core/security/login"
    body = {
        "InstanceName": cfg["instance_name"],
        "Username": cfg["username"],
        "UserDomain": cfg["user_domain"],
        "Password": cfg["password"],
    }

    _info(f"POST {url}")
    _info(f"InstanceName={cfg['instance_name']!r} Username={cfg['username']!r} "
          f"UserDomain={cfg['user_domain']!r}")

    try:
        resp = client.post(url, json=body)
    except httpx.RequestError as e:
        _fail(f"Network error: {type(e).__name__}: {e}")
        _info("Check base URI, DNS, proxy, and SSL trust from inside the container.")
        return None

    _info(f"HTTP {resp.status_code}")

    if resp.status_code != 200:
        _fail(f"Login HTTP status {resp.status_code}")
        _info(f"Response body: {resp.text[:500]}")
        return None

    try:
        payload = resp.json()
    except ValueError:
        _fail("Login response was not valid JSON")
        _info(f"Response body: {resp.text[:500]}")
        return None

    # Archer wraps everything in IsSuccessful + RequestedObject
    if not payload.get("IsSuccessful"):
        _fail("Archer reported IsSuccessful=false")
        _info(f"ValidationMessages: {payload.get('ValidationMessages')}")
        return None

    token = (payload.get("RequestedObject") or {}).get("SessionToken")
    if not token:
        _fail("No SessionToken in RequestedObject")
        _info(f"RequestedObject keys: {list((payload.get('RequestedObject') or {}).keys())}")
        return None

    _ok(f"Got session token: {_mask_token(token)}")
    return token


def step_list_modules(client: httpx.Client, cfg: dict[str, Any], token: str) -> bool:
    """GET /api/core/system/module - confirms the session token is actually
    usable for a real read, and prints the IDs for the two modules we care
    about so we have them on hand for the live publish work later.
    """
    _step("Step 2/3: List modules (read-only sanity check)")

    url = f"{cfg['base_uri']}/api/core/system/module"
    headers = {
        "Authorization": f'Archer session-id="{token}"',
        "Accept": "application/json",
    }

    _info(f"GET {url}")

    try:
        resp = client.get(url, headers=headers)
    except httpx.RequestError as e:
        _fail(f"Network error: {type(e).__name__}: {e}")
        return False

    _info(f"HTTP {resp.status_code}")

    if resp.status_code != 200:
        _fail(f"List modules HTTP status {resp.status_code}")
        _info(f"Response body: {resp.text[:500]}")
        return False

    try:
        payload = resp.json()
    except ValueError:
        _fail("Modules response was not valid JSON")
        return False

    # Archer returns a list of {IsSuccessful, RequestedObject: {Id, Name, ...}}
    if not isinstance(payload, list):
        _fail(f"Expected a list, got {type(payload).__name__}")
        return False

    modules = []
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        obj = entry.get("RequestedObject") or {}
        mid = obj.get("Id")
        name = obj.get("Name")
        if mid is not None and name:
            modules.append((mid, name))

    _ok(f"Retrieved {len(modules)} modules")

    # Look for the two we care about. Match on substring (case-insensitive)
    # so we don't fail just because the display name has extra prefixes.
    targets = ["Hardware", "Authorization Package"]
    for target in targets:
        matches = [(mid, name) for mid, name in modules
                   if target.lower() in name.lower()]
        if matches:
            for mid, name in matches:
                _ok(f"Found target module: Id={mid}  Name={name!r}")
        else:
            _warn(f"No module name contains {target!r} - "
                  f"the publisher will need the exact display name later")

    return True


def step_logout(client: httpx.Client, cfg: dict[str, Any], token: str) -> bool:
    """POST /api/core/security/logout - clean teardown of the session.

    The C# version sends the token in the body as well as the auth header,
    so we mirror that exactly.
    """
    _step("Step 3/3: Logout")

    url = f"{cfg['base_uri']}/api/core/security/logout"
    headers = {
        "Authorization": f'Archer session-id="{token}"',
        "Accept": "application/json",
    }
    body = {"Value": token}

    _info(f"POST {url}")

    try:
        resp = client.post(url, headers=headers, json=body)
    except httpx.RequestError as e:
        _fail(f"Network error: {type(e).__name__}: {e}")
        return False

    _info(f"HTTP {resp.status_code}")

    if resp.status_code != 200:
        _fail(f"Logout HTTP status {resp.status_code}")
        _info(f"Response body: {resp.text[:500]}")
        return False

    _ok("Session terminated cleanly")
    return True


# ---------- entry point ----------

def main() -> int:
    print("=" * 60)
    print("Archer connectivity smoke test")
    print("=" * 60)

    cfg = _load_config()

    print(f"\nbase_uri      = {cfg['base_uri']}")
    print(f"instance_name = {cfg['instance_name']}")
    print(f"username      = {cfg['username']}")
    print(f"user_domain   = {cfg['user_domain']!r}")
    print(f"verify_ssl    = {cfg['verify_ssl']}")
    print(f"password      = {'<set>' if cfg['password'] else '<EMPTY>'}")

    if not cfg["verify_ssl"]:
        _warn("SSL verification is DISABLED. This is fine for a first-run")
        _warn("connectivity test against an internal RTX host, but you should")
        _warn("set ARCHER_VERIFY_SSL=true once the container trusts the RTX CA.")
        # Suppress the noisy InsecureRequestWarning that httpx/urllib3 will emit
        try:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        except Exception:
            pass

    timeout = httpx.Timeout(30.0, connect=10.0)

    with httpx.Client(verify=cfg["verify_ssl"], timeout=timeout) as client:
        token = step_login(client, cfg)
        if not token:
            print("\n" + "=" * 60)
            print("RESULT: FAILED at login")
            print("=" * 60)
            return 1

        modules_ok = step_list_modules(client, cfg, token)

        # Always attempt logout even if the modules step failed - we don't
        # want to leak sessions on the server.
        logout_ok = step_logout(client, cfg, token)

    print("\n" + "=" * 60)
    if modules_ok and logout_ok:
        print("RESULT: ALL STEPS PASSED")
        print("=" * 60)
        return 0
    else:
        print("RESULT: PARTIAL FAILURE")
        print(f"  login:        OK")
        print(f"  list modules: {'OK' if modules_ok else 'FAIL'}")
        print(f"  logout:       {'OK' if logout_ok else 'FAIL'}")
        print("=" * 60)
        return 1


if __name__ == "__main__":
    sys.exit(main())
