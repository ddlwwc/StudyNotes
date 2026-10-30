# 在本机沙盒内构建需要两个参数

`swift build` 和 `swift test` 在 DSH 的 workspace-write 文件策略下会连续失败，必须加 `--disable-sandbox` 并把 `CLANG_MODULE_CACHE_PATH` 指向工作区内目录，两个改动缺一不可。这不是项目本身的问题，而是构建工具与本机沙盒的交互，但换台机器或在受限环境里协作时会重现，所以记录在此。

## 三个互不相关的失败源

1. **SwiftPM 嵌套沙盒**：SwiftPM 默认用 `sandbox-exec` 包裹 manifest 编译和插件执行。沙盒进程内不允许再次 `sandbox_apply`，报 `sandbox-exec: sandbox_apply: Operation not permitted`（退出码 71）。`--disable-sandbox` 关掉的是这一层。

2. **clang 模块缓存不可写**：clang 默认把模块缓存写到 `$TMPDIR/C/clang/ModuleCache`。该路径在沙盒内不可写，导致连标准库都无法加载，报 `error opening '.../C/clang/ModuleCache/Swift-*.swiftmodule' for output` 和 `unable to load standard library for target ...`。这个问题**与 SwiftPM 沙盒无关**，只加 `--disable-sandbox` 仍会失败。`CLANG_MODULE_CACHE_PATH` 是唯一能改掉它的开关（`-Xcc -fmodules-cache-path` 只作用于 manifest 编译那一层，覆盖不到后续编译）。

3. **SwiftPM 用户级缓存不可写**：`~/Library/org.swift.swiftpm` 和 `~/Library/Caches/org.swift.swiftpm` 在沙盒内不可写，SwiftPM 打印 `disabling user-level cache features` 和 `failed loading cached manifest` 的 warning。**这些 warning 无害**，构建仍会成功，不要为了让它们消失去折腾 `--cache-path`。

## 实测结论

`--disable-sandbox` 单独使用失败（撞第 2 条）；`CLANG_MODULE_CACHE_PATH` 单独使用也失败（撞第 1 条）；两者同时使用成功。`--cache-path` 不必要。

## 在普通终端里

不受影响，用标准的 `swift build` / `swift test` 即可。这两个改动只在受限环境中需要。
