# StudyNotes HTTP 契约

`openapi.yaml` 是 Mac/iOS 客户端、Web 服务与发布客户端之间唯一的 HTTP 契约。

- 所有发布写请求与状态查询使用 Ed25519 签名。
- 笔记媒体上传、校验、读取、扫描、清理和发布预览使用共享 Bearer 密钥。
- 服务端只配置 `LIBRARY_MEDIA_KEY_SHA256=sha256:<64hex>`，不保存或返回可用的原始 Bearer 密钥。
- 签名覆盖方法、规范化路径与查询、时间戳、随机数和请求体 SHA-256。
- Web Route Handler 在进入业务服务前读取本文件并执行 JSON Schema 运行时校验。
- 修改字段时必须同步更新契约与 Web 测试，不手写第二套请求边界。
