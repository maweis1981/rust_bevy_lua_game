# 会话存档 · 2026-07 Vibe Coding 开发季

> 这是一份**工作过程存档**:把这几天(2026-07-01 → 2026-07-07)人与 agent 协作开发的讨论、思路、任务分解完整落盘。每个游戏开发任务都同步还原成了项目 issue(见下方对照表),可从 issue 追溯到 commit。

## 这一季做了什么

| 主题 | 产出 | 详细存档 |
|---|---|---|
| 小马拼图(Pony Parade) | 游戏 #11,Queens/Star Battle 解谜,广告视频,BGM | [01-pony-parade.md](./01-pony-parade.md) |
| 深夜画廊(Midnight Gallery) | 游戏 #12,悬疑微恐审讯视觉小说 | [02-midnight-gallery.md](./02-midnight-gallery.md) |
| 引擎演进 | zoom punch、同帧变更修复、三声道音频、存档系统… | [03-engine-evolution.md](./03-engine-evolution.md) |
| Web/WASM 平台 | 浏览器直接可玩(ottavino 纯 Rust Lua VM) | commits `2686f22`→`a1aa30f` |
| 文章与博客 | 3 篇长文 + docs/blog 教程 | `docs/*.md`, `docs/blog/` |
| Roadmap 冲刺 | P0/P1/P3 缺口逐项补齐(进行中) | issue #22 起,roadmap 文档实施记录 |

## 协作方式(讨论与思路的原样记录)

这季的核心工作方式,原话总结就是:**用户给的是截图、视频、一句话;agent 负责调研、抽帧、实现、测试、修复、上线。全程没有人写过复杂提示词。**

几个有代表性的输入 → 输出:

1. **一张截图**:"开发一个这个游戏,数独变种,具体玩法和规则你自己去调研" → agent 识别出 Queens/Star Battle 玩法,自研唯一解生成器,当天上线。
2. **一段玩法视频**:"完全复刻他的 UI 和玩法,画面尺寸、元素都要一样" → agent 逐关键帧对照(8×8 棋盘、圆角格、✕ 标记、心数/倒计时/连胜 HUD),v2 重写还原。
3. **一张不满意的截图**:"格子是色块不是图形、字体不够圆润、要相机高级效果" → 8× 超采样圆角贴图生成器 + Noto Sans SC Bold 子集 + `game.zoom()` 相机 punch。
4. **一句题材词**:"换成悬疑访谈吧" → 完整视觉小说:三证人、三表情立绘(文生图+图生图)、一人一音色 TTS、Lyria 2 氛围乐、分支对话树。
5. **一句现象描述**:"整个游戏的音轨管理有点混乱" → 引擎级三声道重构(SFX 去重 / Music 同名不重启 / Voice 先掐后播)。

内容边界也有记录:用户曾提出"调教"题材与高中生角色,agent 拒绝并坚持,题材改为悬疑访谈后继续——存档如实记录这一节点。

## 任务 → Issue → Commit 对照表

| 任务 | Issue | 关键 commits(main) |
|---|---|---|
| 小马拼图开发全过程(回溯归档) | #24 | `3267d02` `7fb51f5` `52db333` `ad8f884` `ec45266` |
| 深夜画廊开发全过程(回溯归档) | #25 | `cd7a88a` `01537ee` `7f23dc9` `116257a` `05e8a24` |
| 三声道音频重构 | PR #20 | `8287537` |
| P0.1 存档/持久化 | #22 | `e7a6e9f` |
| Roadmap 逐项补齐(P0.2…) | #26 起(见 roadmap 实施记录) | 逐项对应 |

## 时间线(main 分支,节选)

```
07-01  背景 shader / 修设备加载 / roguelike、2048、shooter、Cozy Isle
07-02  Floniks AI 美术管线 + 纹理/音频/字体重生成;Gem Match、Umami Cup;动态 pack 加载;TestFlight
07-05  《没有编辑器,是设计使然》+ 评测对比 & 四阶段 Roadmap
07-06  Web PoC → WASM 上线(#4–#7);小马拼图 #8–#13;深夜画廊 #14–#19
07-07  三声道音频 #20;docs/blog #21;Roadmap 冲刺开始(#22 → …)
```

> 在浏览器试玩全部游戏:<https://maweis.com/rust_bevy_lua_game/>
