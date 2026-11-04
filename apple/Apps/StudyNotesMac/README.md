# StudyNotesMac

macOS 15+ SwiftUI 工作台，依赖相对路径的 `StudyNotesKit`。

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/StudyNotesMac-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/StudyNotesMac-clang-cache \
swift build --disable-sandbox --scratch-path /private/tmp/StudyNotesMac-build
./script/build_and_run.sh
```

离屏截图：

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/StudyNotesMac-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/StudyNotesMac-clang-cache \
swift run --disable-sandbox --scratch-path /private/tmp/StudyNotesMac-build \
  StudyNotesMacSnapshot
```

默认输出到 `dist/StudyNotesMac-1440x1024.png`。截图使用显式标记为“示例预览”的 fixture，不代表持久化数据。

可额外传入 `--search-results` 渲染扁平搜索结果：

```bash
swift run --disable-sandbox --scratch-path /private/tmp/StudyNotesMac-build \
  StudyNotesMacSnapshot dist/StudyNotesMac-search-results.png --search-results
```

可用 `--reader-outline` 展示宽布局常驻目录，并与任意模式组合 `--dark`
验证暗色阅读表面：

```bash
swift run --disable-sandbox --scratch-path /private/tmp/StudyNotesMac-build \
  StudyNotesMacSnapshot dist/StudyNotesMac-outline-dark.png \
  --reader-outline --dark
```
