# 笔记以 Markdown 文件存在 iCloud Drive

学习笔记的唯一真相是 iCloud Drive 中的 `.md` 文件，app 只读写这些文件，不另建私有数据库作为主存储。理由有两条：数据不被任何 app 的格式锁定（十年后任何编辑器都能打开），以及 Mac 与 iPhone 之间的双向同步与冲突调解由系统的 `NSFileCoordinator` 承担，不必自建同步引擎——而自建同步引擎出错时是静默丢数据，不是报错。

## Considered Options

- **SwiftData / CloudKit**：零配置、同步稳，但数据在黑盒里，导出要自己写。
- **七牛云对象存储作为同步通道**：七牛是 S3 类对象存储，没有目录语义、没有原子改名、没有冲突检测。要把它当同步通道就得自己实现 manifest、tombstone 和 last-write-wins，正确性极难验证。
- **本地数据库 + Markdown 双写**：两处真相，长期必然不一致。

## Consequences

iCloud Drive 的文件在系统需要腾空间时会被驱逐，本地只留占位文件，「文件在本地」不是代码能保证的事。因此读取路径必须先检查占用状态，必要时通过 `startDownloadingUbiquitousItem` 触发下载并展示进度；写入路径始终只写本地，不等待网络。手机上「优化存储」默认开启，这条尤其重要。
