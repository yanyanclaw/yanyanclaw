#!/usr/bin/env python3
"""Fetch PTT Stock [標的] threads: content + real-time price + Google News."""
import sys
import re
import json
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from collections import defaultdict

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
)


def fetch(url, extra_headers=None, timeout=20):
    headers = {"User-Agent": UA}
    if extra_headers:
        headers.update(extra_headers)
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", errors="ignore")
    except Exception as e:
        sys.stderr.write(f"[fetch] {url}: {e}\n")
        return ""


def board_articles():
    """Return list of [標的] articles from pttweb.cc board page."""
    html = fetch("https://www.pttweb.cc/bbs/Stock/page")
    if not html:
        return []

    articles = []
    seen_aids = set()

    for part in re.split(r'articleAid:"', html)[1:]:
        m = re.match(r"(M\.[0-9A-Za-z.]+)\"", part)
        if not m:
            continue
        aid = m.group(1)
        if aid in seen_aids:
            continue

        tm = re.search(r'title:"([^"]+)"', part[:700])
        if not tm or "[標的]" not in tm.group(1):
            continue

        seen_aids.add(aid)
        title = tm.group(1)
        is_reply = title.startswith("Re:")
        base = re.sub(r"^Re:\s*", "", title).strip()

        articles.append(
            {
                "aid": aid,
                "title": title,
                "base": base,
                "is_reply": is_reply,
                "url": f"https://www.pttweb.cc/bbs/Stock/{aid}",
            }
        )

    sys.stderr.write(f"[board] found {len(articles)} [標的] articles\n")
    return articles


def article_content(aid, max_chars=700):
    """Fetch article body text from ptt.cc (excludes metadata & comments)."""
    html = fetch(
        f"https://www.ptt.cc/bbs/Stock/{aid}.html",
        extra_headers={"Cookie": "over18=1"},
    )
    if not html:
        return ""

    m = re.search(r'<div id="main-content"[^>]*>(.*)', html, re.DOTALL)
    if not m:
        return ""

    text = re.sub(r"<[^>]+>", "", m.group(1))
    lines = text.split("\n")

    TEMPLATE = re.compile(
        r"^\(例\s|^請選擇並刪除|^非長期投資者|^討論、心得類|^\(請選擇"
    )

    body = []
    for line in lines[1:]:
        if re.match(r"^--\s*$", line):
            break
        if TEMPLATE.match(line):
            continue
        body.append(line)

    result = "\n".join(body).strip()
    result = re.sub(r"\n{3,}", "\n\n", result)
    return result[:max_chars]


def ticker_from_content(content):
    """Extract ticker from article '標的：' line (most reliable source)."""
    m = re.search(r"^標的[：:]\s*(.+)", content, re.MULTILINE)
    if not m:
        return None
    raw = m.group(1).strip()
    # Take first token, strip parentheses and Chinese
    raw = re.sub(r"[（(（].*", "", raw).strip()
    ticker = raw.split()[0] if raw.split() else raw
    return ticker if ticker else None


def ticker_from_title(base_title):
    """Fallback: extract ticker from [標的] base title."""
    text = re.sub(r"\[標的\]\s*", "", base_title).strip()
    parts = text.split()
    if not parts:
        return text[:12]
    ticker = re.sub(r"[^\w.]", "", parts[0])
    return ticker if ticker else text[:12]


def fetch_price_twse(code):
    """Fetch Taiwan stock price from TWSE MIS API (tse_ then otc_ fallback)."""
    for prefix in ("tse", "otc"):
        url = (
            f"https://mis.twse.com.tw/stock/api/getStockInfo.jsp"
            f"?ex_ch={prefix}_{code}.tw&_=1"
        )
        raw = fetch(url, timeout=10)
        if not raw:
            continue
        try:
            j = json.loads(raw)
            arr = j.get("msgArray", [])
            if not arr:
                continue
            d = arr[0]
            prev_close = float(d["y"]) if d.get("y") and d["y"] != "-" else None
            current = float(d["z"]) if d.get("z") and d["z"] != "-" else None
            price = current or prev_close
            if not price:
                continue
            change_pct = None
            if current and prev_close and prev_close != 0:
                change_pct = round((current - prev_close) / prev_close * 100, 2)
            label = "即時" if current else "昨收"
            return {
                "symbol": code,
                "name": d.get("n", ""),
                "price": price,
                "change_pct": change_pct,
                "currency": "TWD",
                "label": label,
            }
        except Exception as e:
            sys.stderr.write(f"[price_twse] {code}: {e}\n")
    return None


def fetch_price_stooq(symbol):
    """Fetch price from Stooq CSV API (for US stocks and TW futures)."""
    url = f"https://stooq.com/q/l/?s={urllib.parse.quote(symbol)}&f=sd2t2ohlcv&h&e=csv"
    raw = fetch(url, timeout=10)
    if not raw:
        return None
    try:
        lines = raw.strip().split("\n")
        if len(lines) < 2:
            return None
        vals = lines[1].split(",")
        # Symbol,Date,Time,Open,High,Low,Close,Volume
        if len(vals) < 7 or vals[1] == "N/D":
            return None
        close = float(vals[6])
        open_ = float(vals[3])
        change_pct = round((close - open_) / open_ * 100, 2) if open_ else None
        return {
            "symbol": symbol.upper(),
            "price": close,
            "change_pct": change_pct,
            "currency": "USD",
            "label": "收盤",
        }
    except Exception as e:
        sys.stderr.write(f"[price_stooq] {symbol}: {e}\n")
        return None


def fetch_price(ticker):
    """Route ticker to the right price source."""
    t = ticker.strip()
    # Taiwan futures keywords → Stooq TX.F
    if any(k in t for k in ("指期", "台指", "小台")):
        return fetch_price_stooq("TX.F")
    # Pure digits (or digits+letter) → Taiwan listed stock via TWSE
    if re.match(r"^\d{4,6}[A-Za-z]?$", t):
        return fetch_price_twse(t.upper())
    # Otherwise → US stock via Stooq
    return fetch_price_stooq(f"{t.upper()}.US")


def google_news(ticker, max_items=4):
    """Return top news headlines from Google News RSS."""
    q = urllib.parse.quote(f"{ticker} 股票")
    url = (
        f"https://news.google.com/rss/search"
        f"?q={q}&hl=zh-TW&gl=TW&ceid=TW:zh-Hant"
    )
    xml = fetch(url, timeout=15)
    if not xml:
        return []
    try:
        root = ET.fromstring(xml)
        items = []
        for item in root.findall(".//item")[:max_items]:
            t = item.find("title")
            l = item.find("link")
            if t is not None and t.text:
                items.append(
                    {
                        "title": t.text,
                        "link": l.text if l is not None else "",
                    }
                )
        return items
    except Exception as e:
        sys.stderr.write(f"[news] parse error: {e}\n")
        return []


def main():
    articles = board_articles()
    if not articles:
        print("[]")
        return

    threads = defaultdict(lambda: {"main": None, "replies": []})
    for a in articles:
        if a["is_reply"]:
            threads[a["base"]]["replies"].append(a)
        else:
            threads[a["base"]]["main"] = a

    result = []
    for base, thread in threads.items():
        main_post = thread["main"]
        if not main_post:
            continue

        main_content = article_content(main_post["aid"], max_chars=700)

        # Prefer ticker from article content over title
        ticker = ticker_from_content(main_content) or ticker_from_title(base)
        sys.stderr.write(f"[thread] {ticker}: {base}\n")

        replies_data = []
        for reply in thread["replies"][:2]:
            content = article_content(reply["aid"], max_chars=350)
            replies_data.append({"url": reply["url"], "content": content})

        price = fetch_price(ticker)
        news = google_news(ticker)

        result.append(
            {
                "ticker": ticker,
                "base_title": base,
                "main_aid": main_post["aid"],
                "main_url": main_post["url"],
                "main_content": main_content,
                "reply_count": len(thread["replies"]),
                "replies": replies_data,
                "price": price,
                "news": news,
            }
        )

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
