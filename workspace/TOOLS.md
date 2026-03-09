# TOOLS.md - Local Notes

---

## CRITICAL: 如何讓指令自動執行

watcher 每分鐘掃描你的訊息，只認識一種格式可以執行任何指令：

**markdown code block，語言標籤寫 `exec`**

範例：
```exec
echo hello
```

```exec
cat > /tmp/test.html << 'STORY'
<p>故事內容</p>
STORY
deploy-story 小黑仔
```

**注意：**
- 語言標籤必須是 `exec`，不是 `bash`、不是 `sh`
- 不要用 `exec << 'EOF'` shell heredoc 語法，那是完全不同的東西
- bash block 只允許白名單指令（deploy-template、deploy-story、python3 /root/stock-price.py、python3 /root/show-holdings.py、python3 /root/write-story.py 等）

---

## Stock Price

```exec
python3 /root/stock-price.py <代號>
```

- 台積電：`python3 /root/stock-price.py 2330`
- 美股：`python3 /root/stock-price.py AAPL`
- 多支：`python3 /root/stock-price.py 2330 AAPL NVDA`

---

## Stock News

追蹤股票：0050、2330、2327（國巨）、2406（國碩）

全部新聞：
```exec
python3 /root/stock-news.py
```

指定個股：
```exec
python3 /root/stock-news.py 2330
```

觸發詞：「新聞」「最新消息」「2330新聞」「台積電新聞」等

---

## System Status

```exec
bash /root/monitor.sh
```

觸發詞：「狀態」「你還好嗎」「機器」「網路」「ollama」

---

## 網站更新（小黑仔主頁 https://yanyanclaw.github.io/）

### 換照片

```exec
deploy-template cat 小黑仔 描述文字 --image https://圖片網址
```

### 更新故事

```exec
cat > /tmp/openclaw-story.html << 'STORY'
<p>第一段故事...</p>
<p>第二段故事...</p>
STORY
deploy-story 小黑仔
```

故事格式：純 p 段落，中文，有情節有趣味，盡情發揮。

---

## 寫檔案

```exec
cat > /root/.openclaw/workspace/memory/YYYY-MM-DD.md << 'EOF'
內容
EOF
```

每次對話結束前把重要事項寫進當天記憶檔。

---

## 管理持股清單

**holdings 檔案路徑**：`/root/.openclaw/stock_data/holdings.json`

格式：`{"holdings": [{"ticker": "2327", "name": "國巨"}]}`

### 新增持股
用戶說「加入 XXXX」、「新增持股 XXXX」、「追蹤 XXXX」時：
```exec
python3 -c "
import json; f='/root/.openclaw/stock_data/holdings.json'
d=json.load(open(f)); d['holdings'].append({'ticker':'XXXX','name':'名稱'})
json.dump(d,open(f,'w'),ensure_ascii=False,indent=2)
print('done')
"
```

### 移除持股
用戶說「移除 XXXX」時：
```exec
python3 -c "
import json; f='/root/.openclaw/stock_data/holdings.json'
d=json.load(open(f)); d['holdings']=[h for h in d['holdings'] if h['ticker']!='XXXX']
json.dump(d,open(f,'w'),ensure_ascii=False,indent=2)
"
```

### 查看持股清單
```exec
python3 /root/show-holdings.py
```

---

## 現有小說《我其實是黑貓可是被變成了白貓》

位置：`/root/workspace/story/novel-xiuxian-cat/`
主角：酷羅內可（クロネコ），被詛咒看起來像白貓的黑貓

### 查看章節清單
```exec
ls /root/workspace/story/novel-xiuxian-cat/chapter_*.md
```

### 讀某章內容（如第1章）
```exec
awk /^---/{exit} {print} /root/workspace/story/novel-xiuxian-cat/chapter_01.md
```

### 查看聖經（角色設定）
```exec
cat /root/workspace/story/novel-xiuxian-cat/bible.md
```

觸發詞：「小說」、「幾章」、「寫到哪」、「看章節」、「酷羅內可」
