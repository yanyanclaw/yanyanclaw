#!/usr/bin/env bash
#
# model-limits.sh — 查詢 Groq / Gemini 免費 tier 可用模型與 rate limit
#
# 用法：
#   GROQ_API_KEY=xxx GEMINI_API_KEY=yyy ./model-limits.sh
#   GROQ_API_KEY=xxx GEMINI_API_KEY=yyy ./model-limits.sh --update-config /path/to/openclaw.json
#
# 依賴：curl, jq, bash 4+
#
set -euo pipefail

# --- 設定 ---
GROQ_API_KEY="${GROQ_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
UPDATE_CONFIG=""
OUTPUT_FILE=""
UA="model-limits/1.0"

# Groq 排除清單（非聊天用途）
GROQ_SKIP="whisper-large-v3|whisper-large-v3-turbo|llama-prompt-guard|orpheus"

# Gemini 排除關鍵字
GEMINI_SKIP="tts|embedding|imagen|robotics|computer-use|deep-research|nano-banana|image-preview|gemma|flash-image|-latest$|gemini.*pro|gemini-2\.0|preview-09-2025|-001$|customtools"

# 弱模型過濾（參數量太小，不實用）— 兩邊 provider 都套用
WEAK_MODELS="[^a-z][1-8]b[^0-9]|e[24]b-it|8b-instant|scout-17b|compound|allam|safeguard|gpt-oss-20b"

# Gemini 已知限制 (model_prefix:RPM:RPD:TPM)
GEMINI_KNOWN=(
  "gemini-2.5-pro:5:100:250000"
  "gemini-2.5-flash:10:250:250000"
  "gemini-2.5-flash-lite:15:1000:250000"
  "gemini-2.0-flash:10:250:250000"
  "gemini-2.0-flash-lite:15:1000:250000"
  "gemini-3-flash-preview:10:250:250000"
  "gemini-3-pro-preview:5:100:250000"
  "gemini-3.1-flash-lite-preview:15:1000:250000"
  "gemini-3.1-pro-preview:5:100:250000"
)

# --- 參數解析 ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-config)
      UPDATE_CONFIG="$2"; shift 2 ;;
    --output|-o)
      OUTPUT_FILE="$2"; shift 2 ;;
    --help|-h)
      echo "用法: GROQ_API_KEY=xxx GEMINI_API_KEY=yyy $0 [options]"
      echo "       (also accepts GOOGLE_API_KEY as alias for GEMINI_API_KEY)"
      echo ""
      echo "Options:"
      echo "  -o, --output FILE          輸出 markdown 到檔案（預設 stdout）"
      echo "  --update-config FILE       自動更新 openclaw.json fallback 鏈"
      echo "  -h, --help                 顯示說明"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- 檢查依賴 ---
for cmd in curl jq bc; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed." >&2
    echo "  Install: apt install $cmd  (Debian/Ubuntu)" >&2
    echo "           brew install $cmd  (macOS)" >&2
    echo "           yum install $cmd   (CentOS/RHEL)" >&2
    exit 1
  fi
done

HAS_GROQ=false
HAS_GEMINI=false
[[ -n "$GROQ_API_KEY" ]] && HAS_GROQ=true
[[ -n "$GEMINI_API_KEY" ]] && HAS_GEMINI=true

# --- 互動引導：缺 key 時提示使用者輸入 ---
prompt_key() {
  local name="$1" url="$2" env_file="$3"
  echo "" >&2
  echo "$name not found." >&2
  echo "Get your free key at: $url" >&2
  read -rp "Paste your $name here (or press Enter to skip): " key
  if [[ -z "$key" ]]; then
    return 1
  fi
  echo "$key"
  # 詢問是否存到 .env
  if [[ -n "$env_file" ]]; then
    read -rp "Save to $env_file for next time? [Y/n] " save
    if [[ "$save" != "n" && "$save" != "N" ]]; then
      echo "${name}=${key}" >> "$env_file"
      echo "Saved to $env_file" >&2
    fi
  fi
}

ENV_FILE="${ENV_FILE:-}"  # 可透過 ENV_FILE=/path/.env 指定儲存位置

if ! $HAS_GROQ && [[ -t 0 ]]; then
  got=$(prompt_key "GROQ_API_KEY" "https://console.groq.com/keys" "$ENV_FILE") && {
    GROQ_API_KEY="$got"
    HAS_GROQ=true
  }
fi

if ! $HAS_GEMINI && [[ -t 0 ]]; then
  got=$(prompt_key "GEMINI_API_KEY" "https://aistudio.google.com/apikey" "$ENV_FILE") && {
    GEMINI_API_KEY="$got"
    HAS_GEMINI=true
  }
fi

if ! $HAS_GROQ && ! $HAS_GEMINI; then
  echo "Error: at least one of GROQ_API_KEY or GEMINI_API_KEY must be set" >&2
  exit 1
fi
$HAS_GROQ  || echo "Warning: GROQ_API_KEY not set, skipping Groq models" >&2
$HAS_GEMINI || echo "Warning: GEMINI_API_KEY not set, skipping Gemini models" >&2

# --- 工具函式 ---
fmt_num() {
  local val="$1"
  if [[ -z "$val" || "$val" == "null" || "$val" == "?" ]]; then
    echo "—"
    return
  fi
  if (( val >= 1000 )); then
    local k=$((val / 1000))
    local r=$((val % 1000))
    if (( r == 0 )); then
      echo "${k}K"
    else
      printf "%.1fK" "$(echo "$val / 1000" | bc -l)"
    fi
  else
    echo "$val"
  fi
}

gemini_known_limit() {
  local model_id="$1"
  for entry in "${GEMINI_KNOWN[@]}"; do
    local prefix="${entry%%:*}"
    if [[ "$model_id" == "$prefix" || "$model_id" == "${prefix}-"* ]]; then
      echo "$entry"
      return
    fi
  done
  echo ""
}

# --- Groq ---
declare -a GROQ_ROWS=()
declare -a ALL_GROQ_MODELS=()

if $HAS_GROQ; then
echo "Fetching Groq models..." >&2

groq_models_json=$(curl -sS -H "Authorization: Bearer $GROQ_API_KEY" \
  -H "User-Agent: $UA" \
  "https://api.groq.com/openai/v1/models")

groq_error=$(echo "$groq_models_json" | jq -r '.error.message // empty' 2>/dev/null)
if [[ -n "$groq_error" ]]; then
  echo "Warning: Groq API error: $groq_error" >&2
  echo "Skipping Groq models." >&2
  groq_model_ids=""
else
  groq_model_ids=$(echo "$groq_models_json" | jq -r '.data[] | .id' | grep -vE "$GROQ_SKIP" | grep -vE "$WEAK_MODELS" | sort)
fi

for mid in $groq_model_ids; do
  echo "  Testing $mid..." >&2
  ctx=$(echo "$groq_models_json" | jq -r ".data[] | select(.id==\"$mid\") | .context_window // \"?\"")

  # 發最小請求取 rate limit headers
  resp=$(curl -sS -D /tmp/groq_headers.txt -w '\n%{http_code}' \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -H "Content-Type: application/json" \
    -H "User-Agent: $UA" \
    -d "$(jq -nc --arg m "$mid" '{model:$m,messages:[{role:"user",content:"hi"}],max_tokens:1}')" \
    "https://api.groq.com/openai/v1/chat/completions" 2>/dev/null || true)

  # 解析：http_code 從 curl output，rpd/tpm 從 header file
  http_code=$(echo "$resp" | tail -1)
  rpd=$(grep -i 'x-ratelimit-limit-requests' /tmp/groq_headers.txt 2>/dev/null | awk '{print $2}' | tr -d '\r')
  tpm=$(grep -i 'x-ratelimit-limit-tokens' /tmp/groq_headers.txt 2>/dev/null | awk '{print $2}' | tr -d '\r')

  [[ -z "$rpd" || "$rpd" == "" ]] && rpd="?"
  [[ -z "$tpm" || "$tpm" == "" ]] && tpm="?"

  if [[ "$http_code" == "200" ]]; then
    status="ok"
  elif [[ "$http_code" == "429" ]]; then
    status="rate limited"
  else
    status="$http_code"
  fi

  GROQ_ROWS+=("| $mid | $(fmt_num "$ctx") | $(fmt_num "$rpd") | $(fmt_num "$tpm") | $status |")
  ALL_GROQ_MODELS+=("$mid:$rpd:$tpm:$status")
done

fi  # HAS_GROQ

# --- Gemini ---
declare -a GEMINI_ROWS=()
declare -a ALL_GEMINI_MODELS=()

if $HAS_GEMINI; then
echo "Fetching Gemini models..." >&2

gemini_models_json=$(curl -sS -H "User-Agent: $UA" \
  "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY")

# 檢查 API 是否回傳錯誤
gemini_error=$(echo "$gemini_models_json" | jq -r '.error.message // empty' 2>/dev/null)
if [[ -n "$gemini_error" ]]; then
  echo "Warning: Gemini API error: $gemini_error" >&2
  echo "Skipping Gemini models." >&2
  gemini_model_ids=""
else
  gemini_model_ids=$(echo "$gemini_models_json" | jq -r '
    .models[]
    | select(.supportedGenerationMethods | index("generateContent"))
    | .name
    | sub("^models/"; "")
  ' | grep -vE "$GEMINI_SKIP" | grep -vE "$WEAK_MODELS" | sort)
fi

for mid in $gemini_model_ids; do
  echo "  Testing $mid..." >&2
  display=$(echo "$gemini_models_json" | jq -r ".models[] | select(.name==\"models/$mid\") | .displayName // \"$mid\"")

  # 發最小請求測可用性
  test_resp=$(curl -sS -w '\n%{http_code}' \
    -H "Content-Type: application/json" \
    -H "User-Agent: $UA" \
    -d '{"contents":[{"parts":[{"text":"say ok"}]}],"generationConfig":{"maxOutputTokens":1}}' \
    "https://generativelanguage.googleapis.com/v1beta/models/${mid}:generateContent?key=$GEMINI_API_KEY" \
    2>/dev/null || true)

  test_http=$(echo "$test_resp" | tail -1)
  test_body=$(echo "$test_resp" | sed '$d')

  if [[ "$test_http" == "200" ]]; then
    status="ok"
  elif [[ "$test_http" == "429" ]]; then
    status="quota exceeded"
  elif [[ "$test_http" == "404" ]]; then
    status="not found"
  else
    # 嘗試從 body 判斷
    if echo "$test_body" | jq -r '.error.message // ""' 2>/dev/null | grep -qi "quota"; then
      status="quota exceeded"
    else
      status="$test_http"
    fi
  fi

  # 查已知限制
  known=$(gemini_known_limit "$mid")
  if [[ -n "$known" ]]; then
    IFS=: read -r _ rpm rpd tpm <<< "$known"
  else
    rpm="?"
    rpd="?"
    tpm="?"
  fi

  GEMINI_ROWS+=("| $mid | $display | $(fmt_num "$rpm") | $(fmt_num "$rpd") | $(fmt_num "$tpm") | $status |")
  ALL_GEMINI_MODELS+=("$mid:$rpd:$tpm:$status")
done

fi  # HAS_GEMINI

# --- 產生 Markdown ---
NOW=$(TZ=Asia/Taipei date "+%Y-%m-%d %H:%M (TW)")

md="# Model Rate Limits (Free Tier)

Last updated: $NOW
"

if $HAS_GROQ; then
md+="
## Groq

| Model | Context | RPD | TPM | Status |
|-------|---------|-----|-----|--------|
$(if [[ ${#GROQ_ROWS[@]} -gt 0 ]]; then printf '%s\n' "${GROQ_ROWS[@]}"; else echo "| (no models found) | — | — | — | — |"; fi)
"
fi

if $HAS_GEMINI; then
md+="
## Gemini

| Model | Display Name | RPM | RPD | TPM | Status |
|-------|-------------|-----|-----|-----|--------|
$(if [[ ${#GEMINI_ROWS[@]} -gt 0 ]]; then printf '%s\n' "${GEMINI_ROWS[@]}"; else echo "| (no models found) | — | — | — | — | — |"; fi)
"
fi

# --- 輸出 ---
if [[ -n "$OUTPUT_FILE" ]]; then
  # 比對舊檔
  if [[ -f "$OUTPUT_FILE" ]]; then
    diff_out=$(diff <(grep '^|' "$OUTPUT_FILE" | grep -v '^|[-—]' | grep -v 'Model' | sort) \
                    <(echo "$md" | grep '^|' | grep -v '^|[-—]' | grep -v 'Model' | sort) 2>/dev/null || true)
    if [[ -n "$diff_out" ]]; then
      echo "" >&2
      echo "=== CHANGES FROM LAST RUN ===" >&2
      echo "$diff_out" >&2
    else
      echo "" >&2
      echo "No changes from last run." >&2
    fi
  fi

  mkdir -p "$(dirname "$OUTPUT_FILE")"
  echo "$md" > "$OUTPUT_FILE"
  echo "Written to $OUTPUT_FILE" >&2
else
  echo "$md"
fi

# --- 更新 openclaw.json fallback ---
if [[ -n "$UPDATE_CONFIG" ]]; then
  if [[ ! -f "$UPDATE_CONFIG" ]]; then
    echo "Error: config file not found: $UPDATE_CONFIG" >&2
    exit 1
  fi

  echo "" >&2
  echo "=== Updating fallback chain ===" >&2

  # 從 config 讀取 provider 前綴（掃 baseUrl 含 groq.com 的 key）
  groq_prefix=$(jq -r '
    .models.providers // {} | to_entries[]
    | select(.value.baseUrl // "" | test("groq\\.com"))
    | .key' "$UPDATE_CONFIG" | head -1)
  [[ -z "$groq_prefix" ]] && groq_prefix="groq"

  # Gemini 用 google/ 前綴（openclaw 內建）
  gemini_prefix="google"

  echo "Groq provider prefix: $groq_prefix" >&2
  echo "Gemini provider prefix: $gemini_prefix" >&2

  # 收集可用模型（status=ok, TPM >= 6000）
  declare -a candidates=()

  for entry in "${ALL_GROQ_MODELS[@]}"; do
    IFS=: read -r mid rpd tpm status <<< "$entry"
    if [[ "$status" == "ok" && "$tpm" != "?" ]]; then
      if (( tpm >= 6000 )); then
        # Groq model ID 可能含 org/ 前綴（如 meta-llama/llama-4-...），只取最後部分
        short_mid="${mid##*/}"
        candidates+=("$groq_prefix/$short_mid:$tpm")
      fi
    fi
  done

  for entry in "${ALL_GEMINI_MODELS[@]}"; do
    IFS=: read -r mid rpd tpm status <<< "$entry"
    if [[ "$status" == "ok" && "$tpm" != "?" ]]; then
      if (( tpm >= 6000 )); then
        candidates+=("$gemini_prefix/$mid:$tpm")
      fi
    fi
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "No eligible models found for fallback chain." >&2
    exit 0
  fi

  # 按 TPM 降序排，取前 15 個
  sorted_candidates=$(printf '%s\n' "${candidates[@]}" | sort -t: -k2 -rn | head -15)

  # 讀取現有 primary model（不動它）
  primary=$(jq -r '.agents.defaults.model.primary // empty' "$UPDATE_CONFIG")
  if [[ -z "$primary" ]]; then
    primary=$(jq -r '.agents.defaults.model // empty' "$UPDATE_CONFIG")
  fi
  # 取 primary 的 model ID 部分（去掉 provider/ 前綴）用於比對
  primary_model_id="${primary##*/}"

  echo "Primary (unchanged): $primary" >&2
  echo "New fallback chain:" >&2

  # 建構 fallback JSON array
  fallback_json="["
  first=true
  while IFS=: read -r model_with_prefix tpm; do
    # 跳過 primary（比對 model ID 部分，不受前綴影響）
    candidate_model_id="${model_with_prefix##*/}"
    if [[ "$candidate_model_id" == "$primary_model_id" ]]; then
      continue
    fi
    echo "  - $model_with_prefix (TPM: $(fmt_num "$tpm"))" >&2
    if $first; then
      first=false
    else
      fallback_json+=","
    fi
    fallback_json+="\"$model_with_prefix\""
  done <<< "$sorted_candidates"
  fallback_json+="]"

  # 備份原始 config
  cp "$UPDATE_CONFIG" "${UPDATE_CONFIG}.bak"
  echo "Backup saved: ${UPDATE_CONFIG}.bak" >&2

  # 建構 models allowlist JSON（保留現有 + 加入新 fallback）
  models_json=$(jq -r '.agents.defaults.models // {}' "$UPDATE_CONFIG")
  for fb_model in $(echo "$fallback_json" | jq -r '.[]'); do
    models_json=$(echo "$models_json" | jq --arg m "$fb_model" '. + {($m): {}}')
  done

  # 更新 JSON（fallbacks + models allowlist）
  tmp_config=$(mktemp)
  jq --argjson fb "$fallback_json" --argjson ml "$models_json" \
    '.agents.defaults.model.fallbacks = $fb | .agents.defaults.models = $ml' \
    "$UPDATE_CONFIG" > "$tmp_config"
  mv "$tmp_config" "$UPDATE_CONFIG"

  echo "" >&2
  echo "Config updated: $UPDATE_CONFIG" >&2
  echo "⚠️  Remember to restart the gateway for changes to take effect." >&2
fi
