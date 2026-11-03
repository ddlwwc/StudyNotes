# Web 发布站与发布 API 使用 Next.js 全栈 TypeScript

Web 发布站和仅由 Mac 调用的发布 API 共同使用 Next.js、React 与 TypeScript 实现，连接 MySQL 和七牛云，并以单一 Node.js 运行时部署。该产品是无读者账号的个人只读发布站，页面渲染、全文搜索、发布版本、幂等控制和媒体签名可以共享同一服务与类型边界；相比再维护一个 Java/Spring Boot 服务，全栈 TypeScript 降低了单人维护和部署成本。代价是 Web 端与 Apple 端不能共享业务代码，只通过 OpenAPI、JSON Schema 和 HTTP 契约协作。
