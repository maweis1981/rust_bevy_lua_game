# Game Dev Blog

这套脚手架的开发博客——记录我们如何用**纯 vibe coding**（Claude Code + Floniks + Rust/Bevy/Lua）做 AI 时代的游戏。每篇都来自真实的 git 历史，可照着复现。

> **在线版**：<https://maweis.com/rust_bevy_lua_game/blog/>（官网博客，本目录的 `.md` 由
> `web/build.sh` 原样拷贝、浏览器端 marked.js 渲染）。文章同时发布在
> [作者博客 maweis.com](https://maweis.com)；涉及 Floniks 使用的同步到
> [Floniks 博客](https://floniks.com/blog)。
>
> **新增文章**：在本目录加 `.md`（配图放 `img/`，用 `./img/...` 相对路径）→
> 在 `web/site/blog/posts.js` 头部加一条 manifest → 更新下方表格。合并到 main 后
> Pages 自动上线。

## 文章

| 日期 | 标题 | 一句话 |
| --- | --- | --- |
| 2026-07-07 | [GUIDE · How to Generate Game Art Assets With Claude Code](./2026-07-07-generate-game-art-with-claude-code.md) | 英文 SEO/GEO 落地页：MCP 一行接入、风格圣经、manifest 契约、四步生成循环、FAQ——本仓库素材管线的官方说明 |
| 2026-07-07 | [教程上篇 ·《小马拼图》：一张截图、一段视频，复刻一款解谜手游](./2026-07-07-tutorial-part1-pony-parade.md) | 版本演进图（v1→最终版，WASM 实机截图）；一句话 → agent 统筹分解；引擎 × Floniks 双平台咬合；原生 + WASM 全跨平台——零复杂提示词 |
| 2026-07-07 | [教程下篇 ·《深夜画廊》：一句题材词，做出有声有色的视觉小说](./2026-07-07-tutorial-part2-midnight-gallery.md) | 立绘管线四阶段图（底图→抠图→表情变体）；WASM 实机成品截图；五种生成能力各有引擎契约承接；基频分析证伪"听起来修好了" |
| 2026-07-07 | [总览 · 纯 Vibe Coding：用 Claude Code + Floniks 做 AI 时代的游戏](./2026-07-07-vibe-coding-game-dev.md) | 7 步方法论总览（两篇教程的提纲版） |
| 2026-07-07 | [Engine Showcase：把 feature list 做成游戏，再给每个 feature 一个跑分按钮](./2026-07-07-engine-showcase-devlog.md) | 9 能力站 + 逐站现场 benchmark；全 AIGC 素材；47 行 JSON 的骨骼动画；34 分钟从任务到全绿 |

## 会话存档

开发过程的讨论与思路原样归档在 [`docs/session-archive/2026-07-vibe-session/`](../session-archive/2026-07-vibe-session/)，每个游戏的任务分解可直接还原为项目 issue。

## 相关长文（`docs/`）

- [AI 时代，应该有 AI 时代的游戏开发方式](../ai-era-game-dev.md) —— 观点 + 教程，讲"为什么"
- [没有编辑器，是设计使然](../no-editor-by-design.md) —— 为什么 AI 时代的引擎不需要传统编辑器
- [Roadmap 与横向评测](../roadmap-and-benchmark.md) —— 能力对比与计划

> 在浏览器里试玩全部小游戏：<https://maweis.com/rust_bevy_lua_game/>
