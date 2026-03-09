---
name: github
description: "Push files to GitHub and interact with GitHub using git and gh CLI."
---

# GitHub Skill

## 推送檔案到 GitHub（最常用）

當用戶要你「做個網頁推到 GitHub」或「把檔案推上去」時，用 exec 執行以下流程：

**永遠用 SSH URL（`git@github.com:owner/repo.git`），絕對不要用 HTTPS。不需要 token，SSH key 已配置好。**

**第一步：clone repo（如果還沒 clone）**
```bash
cd /root && git clone git@github.com:yanyanclaw/yanyanclaw.github.io.git 2>/dev/null || echo "already exists"
```

**第二步：建立或修改檔案**
```bash
cat > /root/yanyanclaw/filename.html << 'HTMLEOF'
你的 HTML 內容
HTMLEOF
```

**第三步：commit 並 push**
```bash
cd /root/yanyanclaw && git add . && git commit -m "add filename" && git push
```

完成後，GitHub Pages 網址格式為：
`https://yanyanclaw.github.io/yanyanclaw/filename.html`

## 重要原則

- **一定要自己執行**，不要把指令貼給用戶叫他自己跑
- 用 heredoc（`<< 'EOF'`）寫檔案，不要用 echo 逐行寫
- commit message 用英文
- push 完後主動給用戶 GitHub Pages 網址

## gh CLI（進階操作）

查 PR、issue、CI 狀態時用 gh：

```bash
gh pr checks 55 --repo yanyanclaw/yanyanclaw
gh run list --repo yanyanclaw/yanyanclaw --limit 10
gh issue list --repo yanyanclaw/yanyanclaw --json number,title
```
