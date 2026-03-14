---
name: model-limits
description: Check free tier model availability and rate limits for Groq and Gemini, update fallback chain if needed
user-invokable: true
---

# Model Limits Check

When the user asks about model limits, rate limits, available models, or says things like "更新限制", "查模型", "model limits", "哪些模型能用":

## Step 1: Run the check script

Use exec to run:

```
cd /root/openclaw-repo && export $(grep -v '^#' /root/.openclaw/.env | xargs) && bash scripts/model-limits.sh -o docs/model-limits.md 2>&1
```

## Step 2: Report changes

- If stderr shows `=== CHANGES FROM LAST RUN ===`, summarize the changes to the user
- Highlight: new models, removed models, RPD changes, status changes (ok -> quota exceeded or vice versa)
- If no changes: report "no changes since last check"

## Step 3: Compare with current fallback chain

Read the current fallback config:

```
jq '.agents.defaults.model' /root/.openclaw/openclaw.json
```

Check if any fallback model has status "not found" or is permanently unavailable. If so, suggest removing it.
Check if there are new strong models not in the fallback chain. If so, suggest adding them.

**Do NOT auto-modify openclaw.json.** Always ask the user first before making config changes.

## Safety rules

- Do NOT restart the gateway without user approval
- Do NOT modify openclaw.json without user approval
- Do NOT add models with TPM < 6000 to the fallback chain (they'll hit rate limits immediately)
