# 用文件夹书签访问 iCloud Drive，不申请 iCloud 容器

app 不申请 iCloud entitlement，而是由用户用系统文件夹选择器指定一个 iCloud Drive 目录，app 把该目录的 security-scoped bookmark 存进本地，之后每次启动据此解析路径。原因是免费 Apple ID 的个人团队在 Xcode 里没有 iCloud capability，申请容器这条路根本走不通；而书签方案不需要任何 entitlement，能力上也不吃亏，数据仍是用户可以直接看到的普通 `.md` 文件。

## Consequences

- 首次启动必须让用户选一次目录，且每次访问沙盒外文件都要 `startAccessingSecurityScopedResource` / `stopAccessing...` 成对调用。
- 书签在目录被移动或重命名后会失效（stale），必须实现重建流程，不能假设它永久有效。
- 将来若升级为付费账号，切换到 ubiquity container 只是替换一层的「根目录解析器」，领域层无需改动。
