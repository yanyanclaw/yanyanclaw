#!/usr/bin/env python3
"""
查詢 Groq / Gemini 免費 tier 的可用模型與 rate limit，產生 markdown 表格。
每天跑一次，存到 docs/model-limits.md
"""

import json
import os
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

# --- 設定 ---
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
GOOGLE_API_KEY = os.environ.get("GOOGLE_API_KEY", "")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
OUTPUT_PATH = os.path.join(REPO_ROOT, "docs", "model-limits.md")

# 排除的 model（非聊天用途）
GROQ_SKIP = {
    "whisper-large-v3", "whisper-large-v3-turbo",
    "meta-llama/llama-prompt-guard-2-22m", "meta-llama/llama-prompt-guard-2-86m",
    "canopylabs/orpheus-arabic-saudi", "canopylabs/orpheus-v1-english",
}

GEMINI_SKIP_KEYWORDS = ["tts", "embedding", "imagen", "robotics", "computer-use",
                         "deep-research", "nano-banana", "image-preview"]

UA = {"User-Agent": "model-limits/1.0"}

# Google 免費 tier 已知限制（官方文件，需定期更新）
# source: https://ai.google.dev/gemini-api/docs/rate-limits
GEMINI_KNOWN_LIMITS = {
    # model_prefix -> (RPM, RPD, TPM)
    "gemini-2.5-pro": (5, 100, 250_000),
    "gemini-2.5-flash": (10, 250, 250_000),
    "gemini-2.5-flash-lite": (15, 1000, 250_000),
    "gemini-2.0-flash": (10, 250, 250_000),
    "gemini-2.0-flash-lite": (15, 1000, 250_000),
    "gemini-3-flash-preview": (10, 250, 250_000),
    "gemini-3-pro-preview": (5, 100, 250_000),
    "gemini-3.1-flash-lite-preview": (15, 1000, 250_000),
    "gemini-3.1-pro-preview": (5, 100, 250_000),
    "gemma-3-27b-it": (15, 1000, 250_000),
    "gemma-3-12b-it": (15, 1000, 250_000),
    "gemma-3-4b-it": (15, 1000, 250_000),
    "gemma-3-1b-it": (30, 1000, 250_000),
    "gemma-3n-e4b-it": (15, 1000, 250_000),
    "gemma-3n-e2b-it": (30, 1000, 250_000),
}


def fetch_json(url, headers=None):
    h = dict(UA)
    h.update(headers or {})
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return json.loads(body)
        except Exception:
            raise


def fetch_groq_models():
    """取得 Groq 所有可用 model"""
    data = fetch_json(
        "https://api.groq.com/openai/v1/models",
        {"Authorization": f"Bearer {GROQ_API_KEY}"}
    )
    models = []
    for m in data.get("data", []):
        mid = m["id"]
        if mid in GROQ_SKIP:
            continue
        models.append({
            "id": mid,
            "context_window": m.get("context_window", "?"),
        })
    return sorted(models, key=lambda x: x["id"])


def fetch_groq_rate_limits(model_id):
    """發一個最小請求取得 Groq rate limit headers"""
    try:
        req_body = json.dumps({
            "model": model_id,
            "messages": [{"role": "user", "content": "hi"}],
            "max_tokens": 1,
        }).encode()
        req = urllib.request.Request(
            "https://api.groq.com/openai/v1/chat/completions",
            data=req_body,
            headers={
                **UA,
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            h = resp.headers
            # Groq headers: x-ratelimit-limit-requests (RPD), x-ratelimit-limit-tokens (TPM)
            # RPD 從 remaining + used 或直接從 limit 取
            return {
                "rpd": h.get("x-ratelimit-limit-requests", "?"),
                "tpm": h.get("x-ratelimit-limit-tokens", "?"),
                "status": "ok",
            }
    except urllib.error.HTTPError as e:
        h = e.headers if e.headers else {}
        try:
            body = json.loads(e.read())
            msg = body.get("error", {}).get("message", "")
        except Exception:
            msg = ""
        status = f"{e.code}"
        if e.code == 429:
            status = "rate limited"
        return {
            "rpd": h.get("x-ratelimit-limit-requests", "?") if h else "?",
            "tpm": h.get("x-ratelimit-limit-tokens", "?") if h else "?",
            "status": status,
        }
    except Exception as e:
        return {"rpd": "?", "tpm": "?", "status": str(e)[:30]}


def fetch_gemini_models():
    """取得 Gemini 所有支援 generateContent 的 model"""
    data = fetch_json(
        f"https://generativelanguage.googleapis.com/v1beta/models?key={GOOGLE_API_KEY}"
    )
    models = []
    for m in data.get("models", []):
        if "generateContent" not in m.get("supportedGenerationMethods", []):
            continue
        name = m["name"].replace("models/", "")
        if any(kw in name for kw in GEMINI_SKIP_KEYWORDS):
            continue
        models.append({
            "id": name,
            "display": m.get("displayName", name),
        })
    return sorted(models, key=lambda x: x["id"])


def test_gemini_model(model_id):
    """測試 Gemini model，從 error body 的 quotaValue 抓 RPD"""
    url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
           f"{model_id}:generateContent?key={GOOGLE_API_KEY}")
    req_body = json.dumps({
        "contents": [{"parts": [{"text": "say ok"}]}],
        "generationConfig": {"maxOutputTokens": 1},
    }).encode()
    req = urllib.request.Request(url, data=req_body,
                                 headers={**UA, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            # 成功時也嘗試從 response headers 取 rate limit
            h = resp.headers
            rpd = "?"
            # 嘗試各種可能的 header name
            for key in ["x-ratelimit-limit-requests-per-day",
                         "x-ratelimit-limit-requests",
                         "x-rateLimit-limit"]:
                v = h.get(key)
                if v:
                    rpd = v
                    break
            return {"rpd": rpd, "status": "ok"}
    except urllib.error.HTTPError as e:
        code = e.code
        try:
            body = json.loads(e.read())
            error = body.get("error", {})
            msg = error.get("message", "")
            # 從 error details 中找 quotaValue
            rpd = "?"
            for detail in error.get("details", []):
                if detail.get("@type", "").endswith("QuotaFailure"):
                    for v in detail.get("violations", []):
                        qm = v.get("quotaMetric", "")
                        if "requests" in qm:
                            # 從 description 或 quotaValue 取
                            pass
                if "quotaValue" in detail:
                    rpd = detail["quotaValue"]
                if "quotaMetric" in detail and "requests" in detail.get("quotaMetric", ""):
                    rpd = detail.get("quotaValue", rpd)
            # 也試從 message 中 parse "limit: 20"
            m = re.search(r"limit:\s*(\d+),\s*model:", msg)
            if m:
                rpd = m.group(1)
        except Exception:
            msg = ""
            rpd = "?"
        if code == 429 or "quota" in msg.lower():
            status = "quota exceeded"
        elif code == 404:
            status = "not found"
        else:
            status = f"{code}"
        return {"rpd": rpd, "status": status}
    except Exception as e:
        return {"rpd": "?", "status": str(e)[:30]}


def fmt(val):
    """格式化數字，加 K 後綴"""
    if val == "?" or val is None:
        return "—"
    try:
        n = int(val)
        if n >= 1000:
            return f"{n // 1000}K" if n % 1000 == 0 else f"{n / 1000:.1f}K"
        return str(n)
    except (ValueError, TypeError):
        return str(val)


def main():
    if not GROQ_API_KEY:
        print("Error: GROQ_API_KEY not set", file=sys.stderr)
        sys.exit(1)
    if not GOOGLE_API_KEY:
        print("Error: GOOGLE_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    tw = timezone(timedelta(hours=8))
    now = datetime.now(tw).strftime("%Y-%m-%d %H:%M (TW)")

    lines = [
        "# Model Rate Limits (Free Tier)",
        "",
        f"Last updated: {now}",
        "",
    ]

    # --- Groq ---
    print("Fetching Groq models...", file=sys.stderr)
    groq_models = fetch_groq_models()
    lines.append("## Groq")
    lines.append("")
    lines.append("| Model | Context | RPD | TPM | Status |")
    lines.append("|-------|---------|-----|-----|--------|")
    for m in groq_models:
        print(f"  Testing {m['id']}...", file=sys.stderr)
        limits = fetch_groq_rate_limits(m["id"])
        lines.append(
            f"| {m['id']} | {fmt(m['context_window'])} "
            f"| {fmt(limits['rpd'])} "
            f"| {fmt(limits['tpm'])} "
            f"| {limits['status']} |"
        )
    lines.append("")

    # --- Gemini ---
    print("Fetching Gemini models...", file=sys.stderr)
    gemini_models = fetch_gemini_models()
    lines.append("## Gemini")
    lines.append("")
    lines.append("| Model | Display Name | RPM | RPD | TPM | Status |")
    lines.append("|-------|-------------|-----|-----|-----|--------|")
    for m in gemini_models:
        print(f"  Testing {m['id']}...", file=sys.stderr)
        limits = test_gemini_model(m["id"])
        # 查已知限制
        known = GEMINI_KNOWN_LIMITS.get(m["id"])
        if known:
            rpm, rpd, tpm = known
        else:
            rpm = "?"
            rpd = limits["rpd"] if limits["rpd"] != "?" else "?"
            tpm = "?"
        lines.append(
            f"| {m['id']} | {m['display']} "
            f"| {fmt(rpm)} | {fmt(rpd)} | {fmt(tpm)} "
            f"| {limits['status']} |"
        )
    lines.append("")

    # --- 比對舊檔 ---
    new_content = "\n".join(lines) + "\n"
    old_models = {}  # model_id -> (rpd, status)
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH) as f:
            for line in f:
                line = line.strip()
                if line.startswith("|") and not line.startswith("|--") and "Model" not in line:
                    cols = [c.strip() for c in line.split("|")]
                    cols = [c for c in cols if c]
                    if len(cols) >= 3:
                        mid = cols[0]
                        # RPD 在不同表格位置不同，取倒數第二欄（status 前面）
                        status = cols[-1]
                        rpd = cols[-2] if len(cols) >= 3 else "?"
                        old_models[mid] = (rpd, status)

    new_models = {}
    for line in lines:
        line = line.strip()
        if line.startswith("|") and not line.startswith("|--") and "Model" not in line:
            cols = [c.strip() for c in line.split("|")]
            cols = [c for c in cols if c]
            if len(cols) >= 3:
                mid = cols[0]
                status = cols[-1]
                rpd = cols[-2] if len(cols) >= 3 else "?"
                new_models[mid] = (rpd, status)

    # 產生 diff 摘要
    changes = []
    for mid, (rpd, status) in new_models.items():
        if mid not in old_models:
            changes.append(f"  + NEW: {mid} (RPD: {rpd}, {status})")
        else:
            old_rpd, old_status = old_models[mid]
            if old_rpd != rpd:
                changes.append(f"  ~ RPD changed: {mid}: {old_rpd} -> {rpd}")
            if old_status != status:
                changes.append(f"  ~ Status changed: {mid}: {old_status} -> {status}")
    for mid in old_models:
        if mid not in new_models:
            changes.append(f"  - REMOVED: {mid}")

    # --- 寫入 ---
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        f.write(new_content)
    print(f"\nWritten to {OUTPUT_PATH}", file=sys.stderr)

    if changes:
        print("\n=== CHANGES FROM LAST RUN ===", file=sys.stderr)
        for c in changes:
            print(c, file=sys.stderr)
        print(f"\nTotal: {len(changes)} change(s)", file=sys.stderr)
    else:
        print("\nNo changes from last run.", file=sys.stderr)


if __name__ == "__main__":
    main()
