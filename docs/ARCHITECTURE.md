# StudyNotes 技术架构

| 项目 | 内容 |
| --- | --- |
| 状态 | 已确认技术基线，工作区与编辑器设计已更新 |
| 日期 | 2026-11-03 |
| 范围 | Mac、iOS、Web 发布站与发布 API |

相关文档：

- [产品文档](./PRODUCT_SPEC.md)
- [领域词汇表](../GLOSSARY.md)
- [架构决策记录](./adr/)

## 1. 架构目标

StudyNotes 是按个人单实例、本地优先和低运维成本设计的跨端学习工具。

关键约束：

- Mac 与 iOS 使用原生 Swift 客户端，共享领域与服务代码，不共享页面实现。
- 正文与组织元数据以 iCloud Drive 文件为真相，SQLite 只是设备本地可重建索引；Markdown 笔记的大媒体以稳定对象引用指向私有七牛云。
- Web 发布站与本地资料库生命周期独立，Mac 是唯一发布客户端。
- Web 使用 Next.js 全栈 TypeScript、MySQL 和七牛云，不建设读者账号。
- AI 请求由 Apple 客户端直连用户配置的 OpenAI 兼容供应商。
- 笔记媒体接口使用共享 Bearer 密钥，发布与文章管理接口继续使用 Ed25519 签名。
- Web 应用由现有同机反向代理转发到 `127.0.0.1:8090`，仓库不管理反向代理。
- MySQL 不设独立备份；本地只保存发布映射，不保存可恢复数据库的发布账本。

## 2. 技术栈

| 区域 | 技术 |
| --- | --- |
| Mac / iOS 语言 | Swift 6 |
| Mac / iOS UI | SwiftUI，局部嵌入 AppKit / UIKit |
| PDF | PDFKit |
| Markdown / HTML 阅读 | 共享 Swift 内容模块 + WKWebView |
| Markdown 富文本编辑 | 构建期打包、运行于本地 WKWebView 的共享编辑器内核 |
| Apple 依赖管理 | Swift Package Manager |
| Apple 本地索引 | GRDB、SQLite、FTS5 |
| Web | Next.js App Router、React、TypeScript |
| Web 数据访问 | Drizzle ORM、`mysql2` |
| Web 数据库 | MySQL 8.4 LTS |
| Web 媒体 | 七牛云私有 Bucket |
| Web 部署 | Docker Compose、Next.js Standalone、现有 Nginx |
| 跨端协议 | OpenAPI 3.1、JSON Schema、共享 Reader Runtime |

精确依赖版本在初始化工程时锁定；语言和运行时大版本作为长期基线。

## 3. 仓库结构

```text
StudyNotes/
├── apple/
│   ├── StudyNotes.xcworkspace
│   ├── Apps/
│   │   ├── StudyNotesMac/
│   │   └── StudyNotesIOS/
│   └── Packages/
│       └── StudyNotesKit/
├── web/
│   ├── app/
│   ├── src/
│   └── drizzle/
├── contracts/
│   ├── openapi.yaml
│   ├── studyitem.schema.json
│   └── reader-runtime/
├── infra/
│   └── docker-compose.yml
└── docs/
    ├── PRODUCT_SPEC.md
    ├── ARCHITECTURE.md
    └── adr/
```

不引入 Nx、Turborepo、tRPC 或 GraphQL。Web 使用 npm，Apple 使用 Swift Package Manager。

## 4. Apple 客户端

### 4.1 模块边界

两个 App Target 只负责应用生命周期、窗口、导航和平台入口。

共享 `StudyNotesKit` 包含：

- `Domain`：学习材料、标注、发布映射等领域模型和纯规则。
- `Persistence`：iCloud 文件协调、材料包读写、GRDB 索引和冲突处理。
- `Reader`：Markdown/HTML 渲染、WKWebView 桥接、PDFKit 适配和标注覆盖层。
- `Editor`：共享富文本 WebKit 容器、原生桥接、Markdown 往返和安全保存。
- `Services`：AI、网页抓取、发布、导出和周期提醒。
- `UI`：跨端共享的 SwiftUI 组件、样式与展示模型。

`Domain` 不依赖 SwiftUI、UIKit、AppKit、WebKit 或数据库框架。

### 4.2 iCloud 文件布局

```text
StudyNotes/
├── Inbox/
└── Libraries/
    └── <knowledge-base-id>/
        └── <nested-folders>/
            └── <material-id>.studyitem/
                ├── manifest.json
                ├── source/
                │   └── media/           # 旧版本地媒体；新笔记媒体使用稳定云端引用
                ├── content/
                ├── annotations/
                │   └── <annotation-id>.json
                ├── ai/
                │   └── <conversation-id>.json
                └── revisions/
                    └── <version-id>.md
```

规则：

- 一个 `.studyitem` 对应一份学习材料，是主要同步单元。
- `manifest.json` 保存稳定标识、类型、标题、标签、材料关联和发布映射。
- `source/` 保存不可变原始文件及必要媒体。
- `content/` 保存用户可编辑的 Markdown 或 HTML 阅读副本。
- 标注和 AI 会话按对象拆分文件，降低并发编辑时的文件冲突范围。
- `revisions/` 保存产品要求的最近 10 个文字版本。
- `rendered.html`、缩略图、全文索引和预览全部只存在设备本地缓存。
- Markdown 笔记的新图片和附件以 `media://qiniu/<objectKey>` 引用私有七牛云，不复制进材料包。
- 待上传媒体队列和已查看媒体缓存放在 Application Support，不进入 iCloud。

### 4.3 文件与索引一致性

- 所有 iCloud 文件读写经过 `NSFileCoordinator`。
- 使用 `NSMetadataQuery` 发现其他设备产生的变化。
- 写入采用同目录临时文件加原子替换。
- 冲突不静默覆盖，按材料文件保留冲突副本，由用户选择处理。
- SQLite 不进入 iCloud，可从材料包扫描后完整重建。
- FTS5 使用 trigram tokenizer；1～2 个汉字的短查询使用受限 `LIKE` 回退。

iOS 默认只取得目录和 `manifest.json`，正文通过 iCloud 按需下载。全文搜索只覆盖已下载或已离线保存的材料，界面明确显示该范围。

### 4.4 阅读与标注

- Markdown/HTML 由共享 Swift Reader 模块生成清洗后的派生 `rendered.html`。
- WKWebView 加载派生 HTML 和本地样式，不执行源网页脚本。
- 标注锚点采用文本引用、前后文、偏移与块路径、图片归一化矩形、PDF 页号与归一化矩形。
- `contracts/reader-runtime/` 提供无第三方依赖的共享 JavaScript 运行时，负责选区读取、锚点恢复、矩形计算和高亮覆盖。
- Reader Runtime 不修改正文 DOM，不直接访问 iCloud 或数据库；持久化始终由 Swift 或 Web 应用层负责。
- PDF 原文永不修改，标注保存在材料包中，由 PDFKit 与自定义覆盖层渲染。
- 内容变化导致锚点失败时，标注保留为“位置待恢复标注”。

### 4.5 Markdown 编辑

- Markdown 笔记和 Markdown 文档可在阅读区切换为所见即所得编辑。
- 平台无关的 JavaScript 编辑器核心在构建期打包，运行时只加载本地资源。
- 编辑器内部文档树不持久化；Swift 层接收序列化后的 Markdown，并继续以原子替换写入材料包。
- 编辑器支持高级 Markdown 源文本模式。未知语法以兼容块保留，无法无损序列化时拒绝保存。
- 自动保存由 Swift 层统一调度，负责指纹检查、文件协调、版本生成、搜索重建和标注重解析。
- AI、发布、导出和版本操作前必须等待当前编辑会话完成保存。

## 5. AI 客户端

Apple 端共享一个薄 AI 客户端：

- 配置 OpenAI 兼容基础地址、模型 ID 和 API Key。
- API Key 保存到 Apple 钥匙串，可选择 iCloud 钥匙串同步。
- 使用 `URLSession.AsyncBytes` 直接解析 SSE 流。
- 支持解释、总结、继续追问、停止生成和展示 Token 用量。
- 不自动重试，不自动切换供应商，不经过 StudyNotes Web 服务。
- 用户问题、回答、模型 ID 和时间写入材料包内的 AI 会话文件。

## 6. Web 发布站

### 6.1 代码分层

```text
app/
├── a/[articleId]/         公开文章
├── u/[unlistedToken]/     未列出文章
├── search/                公开文章搜索
└── api/v1/                签名发布接口
```

- Server Components 负责公开页面、文章正文和首次搜索渲染。
- Route Handlers 负责发布、更新、回滚、下架、删除和媒体凭据。
- Service 层负责签名验证、幂等、版本冲突、媒体提交与搜索索引事务。
- Repository 层封装 Drizzle 和 MySQL。
- 仅目录、复制、研读层展开等局部交互使用客户端组件。

### 6.2 数据模型

| 表 | 职责 |
| --- | --- |
| `articles` | 稳定文章身份、`source_material_id`、公开 ID、未列出 Token、可见状态和当前版本指针 |
| `article_versions` | 不可变发布正文、`source_version_id`、内容指纹和版本元数据 |
| `publish_requests` | 发布密钥 ID、客户端请求 ID、首次处理结果和幂等状态 |
| `media_assets` | 七牛云对象键、内容哈希、媒体类型、大小和引用关系 |
| `library_media_assets` | Markdown 笔记媒体的对象键、内容哈希、类型、大小、状态和校验时间 |
| `library_media_cleanup_jobs` | 笔记媒体的引用扫描、延迟清理和失败重试 |
| `article_search` | 仅包含公共文章当前版本的标题、正文、标签和公开研读层全文索引 |

MySQL 是 Web 发布内容的唯一权威状态。iCloud 中的 `manifest.json` 只保存 `articleId`、公开 URL、最后发布版本、可见性和内容指纹等映射，不保存发布版本正文或完整版本链。

### 6.3 发布认证

Mac 使用 Ed25519 私钥签署：

```text
HTTP_METHOD
CANONICAL_PATH_AND_QUERY
TIMESTAMP
NONCE
SHA256(REQUEST_BODY)
```

请求包含密钥 ID、时间戳、随机数和签名。服务端只保存公钥，拒绝过期时间戳、重复随机数和错误签名。API Key、七牛云永久密钥和数据库凭据不得进入 Apple 客户端。

当前部署允许公网 HTTP 链路，因此 Ed25519 只用于防止长期写凭据泄露与请求伪造，不能保护正文传输。公开和未列出文章均视为非机密内容。

笔记媒体接口不沿用 Ed25519：Mac 与 iOS 共用一段设置页配置、钥匙串保存的 Bearer 密钥，服务端保存其哈希。第一版不区分设备和作用域，轮换密钥会使全部设备失效。允许 HTTP 意味着该密钥可能在链路上被截获，客户端只提示风险，不阻止配置。

### 6.4 URL 与可见性

- 公开文章：`/a/{articleId}`
- 未列出文章：`/u/{unlistedToken}`
- 所有页面默认 `noindex`
- 未列出文章不进入列表、搜索或 sitemap
- 切换可见性不复制文章或版本

### 6.5 版本与幂等

- 每个发布请求携带客户端生成的唯一请求 ID。
- 相同请求 ID 返回首次处理结果。
- 内容指纹与当前版本相同则不创建新版本。
- 内容变化时创建不可变 `article_version`。
- 客户端提交的期望版本落后时，服务端返回冲突。
- 回滚只切换当前版本指针。

### 6.6 搜索

- 只有公开文章的当前发布版本进入 `article_search`。
- 发布、回滚和切换可见性与搜索索引更新在同一 MySQL 事务中完成。
- 使用 `FULLTEXT ... WITH PARSER ngram` 处理中文。
- 不引入 Redis、Elasticsearch 或独立搜索服务。

### 6.7 媒体

笔记媒体：

1. Apple 客户端使用共享 Bearer 密钥取得短时、限对象上传凭据。
2. 客户端把待上传文件放入 Application Support 队列并显示本地预览。
3. 上传成功后，服务端验证对象存在性、大小、类型和内容哈希，并登记为可用。
4. Markdown 只保存 `media://qiniu/<objectKey>`；渲染时按对象键换取短时下载 URL。
5. 签名 URL、待上传队列和已查看媒体缓存不进入 iCloud。
6. 清理任务先扫描当前正文和历史版本引用，确认无引用后删除七牛对象。

发布媒体：

1. Mac 通过签名请求获取短时、限用途七牛云上传凭据。
2. Mac 将媒体直接上传到七牛云私有 Bucket。
3. 发布提交只携带对象键、内容哈希和引用关系。
4. 阅读时由 Web 服务校验访问状态并生成短时签名 URL。
5. 永久删除文章时清理无引用媒体。

七牛云永久密钥只保存在 Web 服务端。

笔记媒体和发布媒体使用不同对象前缀、数据表和清理生命周期。发布时由服务端登记或复制笔记对象到发布媒体命名空间，避免删除笔记破坏已发布版本。

### 6.8 笔记媒体接口

OpenAPI 需要新增以下能力：

- 申请笔记媒体上传凭据。
- 校验并完成笔记媒体上传。
- 按对象键换取短时读取 URL。
- 扫描笔记媒体引用。
- 清理用户确认的无引用笔记媒体。
- 查询笔记媒体服务与存储配置状态。

笔记媒体接口使用共享 Bearer 密钥；发布与文章管理接口继续使用发布密钥的 Ed25519 签名、时间戳、随机数和请求体摘要验证。

## 7. 跨端契约

- `contracts/openapi.yaml` 是 Apple 客户端 → StudyNotes Web 服务与发布 API 的唯一 HTTP 契约。
- `contracts/studyitem.schema.json` 是 `manifest.json` 的唯一结构定义。
- `contracts/reader-runtime/` 是 Apple 与 Web 共用的标注几何和文本锚定实现。
- Swift 请求模型由 OpenAPI 生成或校验，不手写第二套路径和字段语义。
- Next.js 在 API 边界执行运行时校验，不只依赖 TypeScript 类型。
- 所有材料包和消息协议都包含显式版本号，未知版本必须拒绝或进入只读兼容模式。

## 8. 部署与运维

```text
Browser / Mac / iOS
      |
Existing Nginx
      |
127.0.0.1:8090
      |
Next.js Standalone ─── MySQL
      |
   七牛云
```

- Docker Compose 运行 Web 与 MySQL。
- Web 只绑定宿主机的 `127.0.0.1:8090`。
- MySQL 不对宿主机外暴露，Web 通过 Docker 内网访问。
- 反向代理和传输层配置位于仓库之外。
- 数据库迁移在启动新容器前单独执行。
- GitHub Actions 只执行测试、构建和契约检查，不自动部署生产。
- 生产部署由所有者手动执行 `docker compose pull && docker compose up -d`。
- MySQL 不设独立备份；主机磁盘和 MySQL 数据卷仍必须持续可用。

## 9. 测试策略

| 层 | 工具与重点 |
| --- | --- |
| Swift Domain / Persistence | Swift Testing；使用临时目录模拟 iCloud 文件协调与冲突副本 |
| Apple Reader | Swift Testing + 代表性 HTML/PDF 固定样本，验证锚点恢复与缩放 |
| Apple Editor | 固定 Markdown 样本库验证往返、未知语法、中文输入、撤销和保存冲突 |
| Apple UI | XCTest / XCUITest 覆盖栏宽、文件夹拖放、编辑、媒体、导入、阅读、标注、AI 和发布主流程 |
| Web Domain / API | Vitest；签名、幂等、版本冲突、可见性和搜索事务 |
| Web 媒体 | 使用内存存储和模拟七牛适配器验证 Bearer 鉴权、登记、校验、读取、去重与延迟清理 |
| Web 数据库 | GitHub Actions MySQL 服务，执行 migration 和集成测试 |
| Web 页面 | Playwright；公开页、未列出页、搜索、导出与响应式布局 |
| 跨端契约 | OpenAPI / JSON Schema 校验，以及 Reader Runtime 固定锚点用例 |

## 10. 明确不包含

- 自建同步服务、CloudKit 记录同步或 iCloud 数据库文件。
- 读者账号、登录、多租户和权限系统。
- Redis、Elasticsearch、消息队列或独立微服务。
- Web 端 AI 代理或服务器保存 AI Key。
- MySQL 自动备份、恢复演练或本地发布账本。
- 在没有本地材料的情况下从 Web 数据库反向生成 StudyNotes 学习材料。
