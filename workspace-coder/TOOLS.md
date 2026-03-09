# Tools - Coder Agent

## 寫檔案

用 exec + heredoc，避免引號問題：

```
exec:
cat > /path/to/file << 'FILEEOF'
檔案內容
FILEEOF
```

## Git 操作

```
exec: git clone git@github.com:yanyanclaw/yanyanclaw.github.io.git /root/yanyanclaw.github.io
exec: cd /root/yanyanclaw.github.io && git add . && git commit -m "message" && git push
```

## 查看現有檔案

```
exec: cat /root/yanyanclaw.github.io/index.html
exec: ls /root/yanyanclaw.github.io/
```

## GitHub Pages 網址格式

- 根目錄檔案：https://yanyanclaw.github.io/filename.html
- 根目錄 index：https://yanyanclaw.github.io/

## 注意事項

- 不要用 HTTPS clone，一定用 SSH
- heredoc 的結尾標記（EOF）要單獨一行，前面不能有空格
- 大段 HTML/CSS 用 heredoc 寫，不要用 echo
