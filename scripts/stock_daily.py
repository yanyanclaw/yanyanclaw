#!/usr/bin/env python3
"""
stock_daily.py — 每日股票 AI 分析 + Telegram 推送
每天 19:00 UTC 執行（台股收盤後，美西中午）

優先讀取本機推送的分析結果（stock_analysis_YYYY-MM-DD.json）；
若不存在才呼叫 Gemini 自行分析。
"""
import json, os, datetime, sys, urllib.request, urllib.parse, time
from pathlib import Path

STOCK_DATA     = Path("/root/stock_data.json")
ANALYSIS_DIR   = Path("/root")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyClrVzYGnr6XIx7G7S3LiTgujOaRD2PLXY")
BRAVE_API_KEY  = os.environ.get("BRAVE_API_KEY",  "BSADQHfgEJ8-xga4iFe2Frc9TAFg64R")
TG_TOKEN = "8723576581:AAFAT6Oxr4oLZxL6ievMgK77fURnFLXT2j0"
TG_CHAT  = "707551310"

GEMINI_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash-lite",
]

def trading_date(stock_data):
    return stock_data["updated_at"].split()[0]

def analysis_file(date_str):
    return ANALYSIS_DIR / f"stock_analysis_{date_str}.json"

def send_telegram(text):
    url  = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"
    body = json.dumps({"chat_id": TG_CHAT, "text": text}).encode()
    req  = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=15)

def brave_search(query, count=3):
    url = f"https://api.search.brave.com/res/v1/web/search?q={urllib.parse.quote(query)}&count={count}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "X-Subscription-Token": BRAVE_API_KEY
    })
    resp = urllib.request.urlopen(req, timeout=10)
    data = json.loads(resp.read())
    results = data.get("web", {}).get("results", [])
    return [{"title": r["title"], "desc": r.get("description", "")[:80]} for r in results]

def gemini_call(prompt):
    for model in GEMINI_MODELS:
        url  = (f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model}:generateContent?key={GEMINI_API_KEY}")
        body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
        req  = urllib.request.Request(url, data=body,
                                      headers={"Content-Type": "application/json"})
        try:
            resp = urllib.request.urlopen(req, timeout=30)
            data = json.loads(resp.read())
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                print(f"  {model} 暫時不可用 ({e.code})，嘗試下一個")
                time.sleep(5)
                continue
            raise
    raise RuntimeError("所有 Gemini 模型都不可用")

def build_analysis_from_gemini(stock):
    queries = ["台股 今日 行情", "國巨 2327", "國碩 2406 散熱", "布蘭特原油 今日"]
    news_lines = []
    for q in queries:
        try:
            for r in brave_search(q, 2):
                news_lines.append(f"- {r['title']}: {r['desc']}")
        except Exception as e:
            print(f"  Brave search 失敗 ({q}): {e}")

    stocks_text = ""
    for s in stock["stocks"]:
        pnl_str = f"{s['pnl_pct']:+.1f}%" if s["pnl_pct"] is not None else "N/A"
        chg_str = f"{s['daily_chg_pct']:+.1f}%" if s["daily_chg_pct"] else "N/A"
        stocks_text += (f"- {s['name']}({s['code'].replace('.TW','')}): "
                        f"均價{s['avg_price']} 現價{s['current_price']} "
                        f"當日{chg_str} 損益{pnl_str}\n")

    summ  = stock["summary"]
    brent = stock["brent"]["current"]

    prompt = f"""你是我的台股投資助理，用繁體中文、口語化但精確地給出今日操作建議。

## 今日持股
{stocks_text}
Brent油價: ${brent}

## 帳戶
- 股票現值: {summ['total_value']:,}元  現金: {summ['cash']:,}元  總資產: {summ['total_assets']:,}元
- 未實現損益: {summ['stock_pnl']:+,}元 ({summ['stock_pnl_pct']}%)

## 策略背景
- 00631L（元大台灣50正2）2x槓桿ETF，剩2張底倉。買回條件：油價跌破$90、停火談判、外資連買。
- 2327（國巨）停損線215元，目標270-280元，被動元件2026漲價循環。
- 2406（國碩）趁當日漲超3%出場33-34元，Q3法說會確認AI散熱訂單前不回來。

## 今日新聞
{chr(10).join(news_lines[:8]) or "（無法取得新聞）"}

請給我：
1. 每支股票今日一句話判斷（要不要動）
2. 明天特別注意什麼
3. 整體倉位評估（一句話）

總字數200字以內，不用客套話。"""

    print("呼叫 Gemini 分析...")
    return gemini_call(prompt)

def main():
    if not STOCK_DATA.exists():
        print("找不到 stock_data.json")
        sys.exit(1)

    stock   = json.loads(STOCK_DATA.read_text())
    today   = trading_date(stock)
    af      = analysis_file(today)

    if af.exists():
        saved = json.loads(af.read_text())
        analysis = saved["analysis"]
        source   = f"（本機預分析 {saved.get('generated_at', '')}）"
        print(f"讀取預存分析：{af.name}")
    else:
        analysis = build_analysis_from_gemini(stock)
        source   = "（Gemini 即時分析）"
        # 存下來避免重複呼叫
        af.write_text(json.dumps({
            "date": today,
            "analysis": analysis,
            "generated_at": datetime.datetime.now(
                datetime.timezone(datetime.timedelta(hours=8))
            ).strftime("%Y-%m-%d %H:%M 台灣時間")
        }, ensure_ascii=False, indent=2))

    tz      = datetime.timezone(datetime.timedelta(hours=8))
    tw_time = datetime.datetime.now(tz).strftime("%m/%d %H:%M")
    msg     = f"📊 每日股票分析 {tw_time} {source}\n\n{analysis}"

    if stock.get("alerts"):
        msg += "\n\n⚠️ 警示\n" + "\n".join(stock["alerts"])

    send_telegram(msg)
    print(f"已發送 Telegram {source}")
    print(f"\n--- 分析 ---\n{analysis}")

if __name__ == "__main__":
    main()
