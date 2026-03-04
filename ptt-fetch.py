#!/usr/bin/env python3
"""Fetch PTT Stock [標的] threads: content + Google News, output JSON."""
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

    # Split on articleAid: each block starts with the AID value
    for part in re.split(r'articleAid:"', html)[1:]:
        m = re.match(r"(M\.[0-9A-Za-z.]+)\"", part)
        if not m:
            continue
        aid = m.group(1)
        if aid in seen_aids:
            continue

        # Title is usually within 700 chars after articleAid
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

    # Strip tags
    text = re.sub(r"<[^>]+>", "", m.group(1))
    lines = text.split("\n")

    # First line is merged metadata — skip it
    # Collect body until the "--" signature separator
    body = []
    for line in lines[1:]:
        if re.match(r"^--\s*$", line):
            break
        # Skip PTT template filler lines
        if re.match(r"^\(例\s|^請選擇|^非長期投資|^\s*$", line) and not body:
            continue
        body.append(line)

    result = "\n".join(body).strip()
    # Trim excessive blank lines
    result = re.sub(r"\n{3,}", "\n\n", result)
    return result[:max_chars]


def ticker_from(base_title):
    """Extract the stock ticker / code from a [標的] base title."""
    text = re.sub(r"\[標的\]\s*", "", base_title).strip()
    parts = text.split()
    if not parts:
        return text[:12]
    # Clean punctuation from first token
    ticker = re.sub(r"[^\w.]", "", parts[0])
    return ticker if ticker else text[:12]


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

    # Group into threads: base_title → {main, replies}
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
            # Reply with no main post on current page — skip
            continue

        ticker = ticker_from(base)
        sys.stderr.write(f"[thread] {ticker}: {base}\n")

        # Main post content
        main_content = article_content(main_post["aid"], max_chars=700)

        # Top replies (up to 2, by appearance order)
        replies_data = []
        for reply in thread["replies"][:2]:
            content = article_content(reply["aid"], max_chars=350)
            replies_data.append({"url": reply["url"], "content": content})

        # News
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
                "news": news,
            }
        )

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
