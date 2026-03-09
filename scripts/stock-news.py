#!/usr/bin/env python3
import json, os, sys, urllib.request
from datetime import datetime

NEWS_DIR = "/root/.openclaw/stock_data/news"
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "qwen2.5:14b"

NAME_MAP = {
    "0050": "元大台灣50",
    "2330": "台積電",
    "2327": "國巨",
    "2406": "國碩",
}

def translate(title):
    if not title or all(ord(c) < 128 for c in title) is False:
        return title  # already has non-ASCII, skip
    try:
        prompt = f"將以下英文標題翻譯成繁體中文，只輸出翻譯結果，不要解釋：{title}"
        data = json.dumps({"model": MODEL, "prompt": prompt, "stream": False,
                           "options": {"num_predict": 80, "temperature": 0}}).encode()
        req = urllib.request.Request(OLLAMA_URL, data=data,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read()).get("response", title).strip()
    except:
        return title

def get_latest_news_file():
    files = sorted([f for f in os.listdir(NEWS_DIR) if f.endswith(".json")], reverse=True)
    if not files:
        return None
    return os.path.join(NEWS_DIR, files[0])

def main():
    filter_symbols = [s.upper() for s in sys.argv[1:]]

    news_file = get_latest_news_file()
    if not news_file:
        print("找不到新聞資料")
        sys.exit(1)

    with open(news_file) as f:
        data = json.load(f)

    date = data.get("date", "")
    print(f"股票新聞 {date}")

    for symbol, articles in data.get("news", {}).items():
        if filter_symbols and symbol not in filter_symbols:
            continue

        name = NAME_MAP.get(symbol, symbol)
        print(f"\n【{symbol} {name}】")

        valid = [a for a in articles if a.get("title") and "error" not in a]
        if not valid:
            print("（無新聞）")
            continue

        for item in valid[:3]:
            title = translate(item.get("title", ""))
            pub_time = item.get("published", "")[:10]
            link = item.get("link", "")
            print(f"• {title}（{pub_time}）")
            if link:
                print(f"  {link}")

if __name__ == "__main__":
    main()
