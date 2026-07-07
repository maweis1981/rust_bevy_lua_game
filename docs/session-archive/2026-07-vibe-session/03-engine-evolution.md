# 存档 · 引擎演进思路(2026-07 季)

> 游戏开发倒逼出来的引擎改动,每一条都是"游戏先撞墙、引擎再补路"。设计原则不变:Lua 只经命令队列写 ECS;能力=数据+测试。

## 本季引擎改动清单

| 改动 | 起因(哪个游戏撞的墙) | 落点 |
|---|---|---|
| 同帧 spawn+mutate 兜底(`entry::<T>().and_modify()`) | 小马拼图白板:spawn 后同帧 set_color 被静默丢弃 | `7fb51f5` |
| `game.zoom()` 相机 punch(`zoom_scale = 1−0.06z²`) | 小马拼图 v3 "要相机高级效果" | `ad8f884` |
| CJK 字体子集管线(Noto Sans SC Bold,`subset_font.py` STRINGS 表) | 小马拼图中文 UI 方块字 | `ad8f884` |
| 三声道音频(SFX 帧内去重 / Music `CurrentMusic` 同名 no-op / Voice 先掐后播) | 深夜画廊音轨互相叠 | `8287537` |
| Web/WASM 平台(ottavino 纯 Rust Lua VM,双后端同一 `LuaVm` 面) | "试玩即传播" | `51aa8e8`→`a1aa30f` |
| `game.save`/`game.load` 持久化(类型编码 KV,落盘 + wasm 内存) | Roadmap P0.1 冲刺 | `e7a6e9f` |

## 思路摘记(讨论中反复出现的判断)

1. **命令队列是护城河**:所有新能力(zoom、三声道、存档)都只是"多几个 LuaCommand + 一个系统",脚本层零破坏。第三方 crate 版本滞后的风险也被挡在桥后。
2. **同帧语义要完整**:脚本"spawn 完立刻改"是最自然的写法,引擎必须让它成立——Query 查不到就走 Commands 队列兜底,顺序仍在 Spawn 之后。
3. **音频通道是模型问题不是补丁问题**:"停掉上一个"补丁修不完;把用途(SFX/Music/Voice)建模成通道,每条通道各有不变量,重叠 bug 一次根治。
4. **能力=数据+测试**:每个新 API 上线同时进 mock(`test_pong.lua`)与单元测试;13 万+ 断言是 agent 敢自主迭代的底气。
5. **双 VM 后端同面**:mlua(桌面/iOS)与 ottavino(wasm)注册同一张 `game` 表——加 API 必须两边都加,这是纪律,不是可选项。

## Roadmap 冲刺(2026-07-07 起,进行中)

按 `docs/roadmap-and-benchmark.md` 逐项补齐未支持能力,每项:issue(分解/实现/测试/回归/合并全过程)→ 独立 PR → squash 合并,起止时间与 commit 记录在 roadmap 文档"实施记录"一节。首项 P0.1 存档:issue #22 → PR #23 → `e7a6e9f`,约 7 分钟。
