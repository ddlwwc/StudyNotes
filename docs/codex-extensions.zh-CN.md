# Codex 扩展中文说明

本文记录当前安装的 Codex 插件与技能。插件和技能会在新的 Codex 会话中载入；安装或升级后请重新开启会话。

| 名称 | 当前版本 | 用途 | 适用场景 |
| --- | --- | --- | --- |
| `caveman` | 4.0.1 | 压缩表达，减少填充词和重复说明，同时保留代码、命令、技术名词和错误原文。 | 希望回答更短、更省输出 token，但仍需完成复杂工程操作时。 |
| `taste-skill` | 2.1.5 | 为网页和应用界面提供完整视觉方向、真实图片检索和浏览器检查，减少模板化的“AI 风格”页面。 | 新建或重做落地页、产品页、作品集、仪表盘和设置页时。 |
| `playwright-cli` | 0.1.23 | 使用 Playwright 打开和操作真实浏览器，读取页面快照，点击、填写、截图、导出 PDF，并检查控制台、网络请求和测试结果。 | 网页调试、交互验证、界面截图、响应式检查、端到端测试和自动化操作。 |
| `gsap-skills` | 1.0.0 | 提供 GSAP 官方技能，覆盖补间动画、时间线、ScrollTrigger、插件、React、Vue、性能优化和工具函数。 | 为网页加入滚动动画、过渡效果、时间线、SVG 动画和复杂运动效果时。 |

## 安装形态

- `caveman`、`taste-skill`、`gsap-skills`：通过 Codex 插件市场安装。
- `playwright-cli`：从 Microsoft Playwright 仓库安装官方技能，同时安装全局 CLI 和 Chromium。
- 插件缓存位于 `~/.codex/plugins/cache/`。
- Playwright 技能位于 `~/.codex/skills/playwright-cli/`。
- Playwright 浏览器缓存位于 `~/Library/Caches/ms-playwright/`。

## 使用说明

### caveman

适合希望降低回答篇幅的任务，例如代码审查、排错和常规开发沟通。启用后表达会明显精简，但代码、命令、技术细节和错误信息应保持完整。

### taste-skill

仓库定位是前端设计品味与反模板化检查，并非通用“AI 内容识别器”。它会引导界面设计方向，在真实浏览器中截图和测量，并检查页面是否出现常见模板化问题。

### playwright-cli

常用命令：

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli screenshot --filename=page.png
playwright-cli close
```

Playwright CLI 需要在工作目录中生成 `.playwright-cli/` 快照文件。若项目不需要保留这些文件，可将其加入 `.gitignore`。

### gsap-skills

包含 `gsap-core`、`gsap-timeline`、`gsap-scrolltrigger`、`gsap-plugins`、`gsap-react`、`gsap-frameworks`、`gsap-performance` 和 `gsap-utils` 八个技能。Codex 会根据任务内容选择相关技能。

## 维护

查看已安装插件：

```bash
codex plugin list
```

升级插件市场快照：

```bash
codex plugin marketplace upgrade
```

检查 Playwright CLI：

```bash
playwright-cli --version
```

## 来源

- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)
- [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill)
- [microsoft/playwright](https://github.com/microsoft/playwright)
- [greensock/gsap-skills](https://github.com/greensock/gsap-skills)
