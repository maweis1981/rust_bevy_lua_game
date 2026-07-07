// Blog manifest — newest first. One entry per file in docs/blog/ (the .md files
// are copied verbatim into blog/posts/ by web/build.sh at deploy time).
// Adding a post? Add the .md to docs/blog/, then add an entry here (see
// docs/blog/README.md).
window.BLOG_POSTS = [
  {
    file: '2026-07-07-generate-game-art-with-claude-code',
    date: '2026-07-07',
    tag: 'GUIDE · EN',
    title: 'How to Generate Game Art Assets With Claude Code (the Pipeline Behind This Repo)',
    excerpt: 'One MCP command connects the asset factory; a style bible locks the look; a manifest places every file by convention. Every asset in these 12 games was generated this way — zero hand-made art, zero human prompts.',
  },
  {
    file: '2026-07-07-vibe-coding-game-dev',
    date: '2026-07-07',
    tag: '总览',
    title: '纯 Vibe Coding：用 Claude Code + Floniks 做 AI 时代的游戏',
    excerpt: '7 步方法论总览：从一句话加一个游戏，到多模态素材管线，到系统性 debug 与一键发布——全部来自真实的 git 历史。',
  },
  {
    file: '2026-07-07-engine-showcase-devlog',
    date: '2026-07-07',
    tag: 'DEVLOG',
    title: 'Engine Showcase：把 feature list 做成游戏，再给每个 feature 一个跑分按钮',
    excerpt: '九个能力站 + 逐站现场 benchmark；全 AIGC 素材；47 行 JSON 的骨骼动画；34 分钟从任务到全绿。',
  },
  {
    file: '2026-07-07-tutorial-part2-midnight-gallery',
    date: '2026-07-07',
    tag: '教程 · 下篇',
    title: '《深夜画廊》：一句题材词，做出有声有色的视觉小说',
    excerpt: '立绘管线四阶段（底图→抠图→表情变体）、TTS 一人一音色、文生音乐铺氛围——五种生成能力各有引擎契约承接。',
  },
  {
    file: '2026-07-07-tutorial-part1-pony-parade',
    date: '2026-07-07',
    tag: '教程 · 上篇',
    title: '《小马拼图》：一张截图、一段视频，复刻一款解谜手游',
    excerpt: '玩法调研、视频关键帧比对、任务分解全部由 agent 统筹；引擎 × Floniks 双平台咬合，原生 + WASM 全跨平台。',
  },
];
