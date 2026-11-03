# StudyNotes HTTP 契约

`openapi.yaml` 是 Mac 发布客户端与 Web 服务之间唯一的 HTTP 契约。

- 所有发布写请求与状态查询使用 Ed25519 签名。
- 签名覆盖方法、规范化路径与查询、时间戳、随机数和请求体 SHA-256。
- Web Route Handler 在进入业务服务前读取本文件并执行 JSON Schema 运行时校验。
- 修改字段时必须同步更新契约与 Web 测试，不手写第二套请求边界。
