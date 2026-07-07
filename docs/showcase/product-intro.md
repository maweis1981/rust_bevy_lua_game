# Engine Showcase · 产品介绍

**一句话**：hollowlullaby 是一个 AI-native 的 2D 小游戏引擎（Rust + Bevy 内核，Lua 写玩法，一份代码发布 macOS / iOS / Web），而 **Engine Showcase** 是它的自证明 demo——引擎的每一项能力都做成一个可玩的小场景，并且每个场景都带一个实时 benchmark。

在线试玩（浏览器直接打开，无需安装）：<https://maweis.com/rust_bevy_lua_game/> → 菜单选择 **Engine Showcase**。

## 它展示什么

Showcase 是一个 3×3 的能力矩阵，九张卡片对应引擎脚本桥（Lua `game.*` API）的九组能力：

| 卡片 | 能力 | 你会看到 |
|---|---|---|
| **VAULT** | `save` / `load` 跨会话持久化 | 存进去的金币和成绩，杀掉进程再开还在（iOS 沙盒 / 桌面配置目录 / 浏览器 localStorage 三端同一 API） |
| **TOUCH** | `touches()` 多点触控 | 每根手指一个光环，实时跟随（桌面用鼠标模拟单指） |
| **ATLAS** | `spawn_sheet` / `set_frame` 图集动画 | 一张 6 帧贴图驱动满屏旋转金币，帧率不掉 |
| **CAMERA** | `cam(x, y, zoom)` 摄像机 | 无人机巡游一个 3 倍屏幕大的世界，跟随 + 变焦 + 打击抖动叠加 |
| **MIXER** | `set_volume` / `stop_music` | 一张能真拖的混音台：音乐/音效/人声三通道即时调音 |
| **SPARKS** | `emit` CPU 粒子 | 点哪炸哪的烟花（四种 preset），全局 512 粒子上限可视化 |
| **TILES** | `tilemap` / `set_tile` | 手指作画的地形编辑器：草地/泥土/水面/石砖四种笔刷 |
| **ROBOT** | `spawn_rig` / `play_anim` / `set_bone` | 剪纸骨骼机器人：三个动画剪辑切换，头部实时看向你的手指 |
| **JUICE** | `track` + `shake` / `zoom` / `haptic` | 手感实验室：每次按钮既触发效果又落一条分析日志 |

## Benchmark：不是宣传数字，是现场跑分

每个站右上角都有一个 **BENCH** 按钮。按下后：

1. 引擎以 0.75 秒为周期采样真实帧时间（45 帧滑动窗口）；
2. 只要平均帧时间守住 1/45s 预算，就把该能力的负载加一档（更多精灵、更多粒子、更大的全图重刷、更多骨骼角色……）；
3. 第一次守不住时，把**上一个守住的档位**定格为分数。

分数通过 `game.save` 持久化——回到 VAULT 站能看到你这台设备九项能力的跑分板。**benchmark 系统本身就是用被测能力实现的**：这是这个 demo 最诚实的部分。

## 为什么这个 demo 有说服力

- **全部素材来自 AIGC 管线**：金币图集、地形 tileset、机器人部件由 Floniks（Seedream 4）生成，BGM 由 Lyria 2 文生音乐生成，处理脚本一条命令可重放（`tools/showcase_assets.py`）。没有一张人画的图。
- **机器人不是视频**：`assets/rigs/robot.rig` 是 47 行手写 JSON——部件层级、枢轴、三个关键帧剪辑。改一个数字，动画就变。这就是"引擎的编辑器是数据 + agent"的含义。
- **它被 13 万条断言守着**：Showcase 的 9 个站全部接入无头测试套件——CI 里每次提交都会把每个站跑到 benchmark 满档并验证持久化正确。
- **一份代码，三个平台**：你在浏览器里玩到的这个 demo，与 iOS 真机上 120Hz 运行的是同一份 Lua，逐字节相同。

## 技术底座（30 秒版）

Rust + Bevy 0.19 内核；Lua 5.4 玩法层（桌面/iOS 用 mlua，Web 用纯 Rust 的 ottavino——因此 wasm 不需要 C 工具链）；Lua 从不直接触碰 ECS，全部通过命令队列桥（这让 CPU 粒子未来换 GPU 粒子、精灵 tilemap 换 bevy_ecs_tilemap 时，脚本一行不改）。完整架构见 `CLAUDE.md` 与 `docs/roadmap-and-benchmark.md`。
