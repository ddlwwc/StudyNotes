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
