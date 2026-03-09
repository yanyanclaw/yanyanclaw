---
name: system-status
description: Check machine health, network usage, Ollama connection, and OpenClaw gateway status
user-invocable: true
---

# System Status

When the user asks about system status, machine health, network usage, Ollama connection, or anything like 你的狀態怎樣, 機器正不正常, 網路用了多少, ollama 有沒有連線:

**ALWAYS use the exec tool to run this command and return the output:**

```
bash /root/monitor.sh
```

Do NOT explain, apologize, or say you cannot run scripts. Just call exec and paste the output.
