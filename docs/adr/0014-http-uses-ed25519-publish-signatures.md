# HTTP 部署使用 Ed25519 发布请求签名

Status: extended by ADR-0022; note-media endpoints use a shared Bearer key while publish endpoints keep Ed25519.

Web 应用由同机现有反向代理转发到 `127.0.0.1:8090`，仓库不管理代理与传输层。考虑到当前部署仍可能通过公网 HTTP 访问，Mac 不发送长期 Bearer 凭据，而是用钥匙串中的 Ed25519 私钥签署请求方法、路径、时间戳、随机数和请求体摘要；服务端只保存公钥，并拒绝过期请求与重复随机数。这样可以避免旁观者取得可重放的长期写凭据，但无法防止正文在 HTTP 链路上被读取或篡改，因此公开和未列出文章仍必须视为非机密内容，传输层安全由部署环境另行负责。
