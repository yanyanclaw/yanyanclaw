"""
Path resolver for openclaw scripts.
Auto-detects local vs remote environment and returns correct paths.

Usage:
    from paths import get_paths
    p = get_paths()
    print(p["stock_data"])  # /root/.openclaw/stock_data (remote) or None (local)
"""

import json
import os
import platform

def _detect_env():
    """Detect if running on local Mac or remote VPS."""
    if platform.system() == "Darwin":
        return "local"
    if os.path.exists("/root/.openclaw"):
        return "remote"
    # fallback: check hostname
    hostname = platform.node()
    if "yan" in hostname.lower() or "mac" in hostname.lower():
        return "local"
    return "remote"

def get_paths(env=None):
    """
    Load paths for the detected (or specified) environment.

    Args:
        env: "local" or "remote". Auto-detected if None.

    Returns:
        dict with path keys.
    """
    if env is None:
        env = _detect_env()

    config_path = os.path.join(os.path.dirname(__file__), "..", "config", "paths.json")
    with open(config_path) as f:
        all_paths = json.load(f)

    return all_paths[env]

if __name__ == "__main__":
    env = _detect_env()
    p = get_paths(env)
    print(f"Environment: {env}")
    for k, v in p.items():
        print(f"  {k}: {v}")
