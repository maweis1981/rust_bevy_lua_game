# 项目总览 · hollowlullaby

> 一份对当前项目的整理文档。目标：让任何人（或任何 agent）在读完本文后，能说清
> **这是什么、代码怎么组织、玩法怎么加、怎么构建/测试/上架**。
> 面向架构与设计细节请配合根目录的 [`CLAUDE.md`](../CLAUDE.md) 一起读；
> 观点与路线图见 [`docs/`](.) 下的三篇文章。

---

## 一、这是什么

一个 2D **迷你游戏合集**：

- **引擎层**：Rust + [Bevy](https://bevyengine.org) 0.19（ECS、渲染、窗口、输入、主循环）。
- **玩法层**：Lua 5.4（通过 [`mlua`](https://github.com/mlua-rs/mlua)，vendored 编译），
  每一个游戏都是一段可热重载的 Lua 脚本。
- **平台**：macOS（开发）与 iOS（UIKit 宿主 app，静态库链接）。

一个 Rust crate（`hollowlullaby`）是唯一真实来源，同时编译为：

- `rlib` → 桌面二进制（`src/main.rs`）；
- `staticlib` → 被 Xcode 链接进 iOS app（入口 `main_rs`）。

**核心理念**：引擎不动，玩法用数据（Lua + 素材）表达。新增游戏 = 新增一个 Lua 文件，
不需要重编 Rust。详见[《我们没有编辑器，这不是欠账，是设计》](./no-editor-by-design.md)。

---

## 二、目录结构

```
.
├── src/                        Rust 引擎层（唯一编译单元）
│   ├── lib.rs                  App 构建、run()、iOS main_rs 入口、FPS overlay
│   ├── main.rs                 桌面二进制（仅调用 run()）
│   ├── script.rs               Lua VM + 资产加载器 + 命令队列桥（整合最重的一块）
│   └── background.rs           自定义 WGSL 着色器背景（Material2d，随玩法呼吸）
│
├── assets/                     运行时资产（folder-reference 打进 iOS bundle）
│   ├── scripts/                Lua 玩法（改这里就改玩法）
│   │   ├── main.lua            场景路由：菜单 + Settings + 三个 preset 游戏
│   │   ├── roguelike.lua       游戏：竞技场幸存者
│   │   ├── game2048.lua        游戏：2048
│   │   ├── shooter.lua         游戏：太空射击（Galaga 风）
│   │   ├── world.lua           游戏：Cozy Isle 沙盒（动森风）
│   │   ├── match3.lua          游戏：Garden Match 消除三消
│   │   ├── umami.lua           游戏：Umami Cup 单指对战
│   │   ├── falling_blocks.lua  早期原型（未被加载，见下文"注意"）
│   │   └── packs/              运行时扫描的 drop-in 游戏包
│   │       └── catch.lua       游戏：Fruit Catch 接水果
│   ├── textures/               86 张程序化/AI 生成的像素图（PNG）
│   ├── audio/                  5 段合成音效/音乐（WAV）
│   ├── fonts/                  UI 字体（game.ttf，Latin-only）
│   ├── shaders/                background.wgsl（极光背景片元着色器）
│   └── ART_REQUESTS.md         美术需求清单（同名同尺寸替换即可升级观感）
│
├── ios/                        iOS 宿主 app
│   ├── Sources/main.m          C main，调用 Rust main_rs
│   ├── Sources/haptics.m       UIKit 触感反馈 C shim（hl_haptic）
│   ├── build_rust.sh           按 Xcode 架构交叉编译静态库
│   ├── Info.plist              由 XcodeGen 从 project.yml 生成（ProMotion 等）
│   ├── ExportOptions.plist     TestFlight 导出配置
│   └── Assets.xcassets/        App 图标
│
├── tools/                      离线工具（不参与运行时）
│   ├── test_pong.lua           无头玩法不变量测试（make test 跑）
│   ├── PACK_SPEC.md            游戏包作者规范（做新游戏先读这个）
│   ├── gen_*.py / *_assets.py  程序化素材生成（纹理/音频/精灵/世界/UI）
│   └── floniks_*.{py,json}     Floniks AI 素材流水线（MCP 接入）
│
├── docs/                       长文（中文）
│   ├── ai-era-game-dev.md      观点 + 教程：AI 时代的游戏开发方式
│   ├── no-editor-by-design.md  反思：为什么没有编辑器
│   ├── roadmap-and-benchmark.md 能力评测对比 + 四阶段 Roadmap
│   └── PROJECT_OVERVIEW.md     本文
│
├── Cargo.toml                  crate 定义（rlib + staticlib）
├── Makefile                    所有开发命令的入口
├── rust-toolchain.toml         固定 stable ≥1.95 + iOS targets
├── project.yml                 XcodeGen 规格（→ 生成 .xcodeproj，git-ignored）
├── CLAUDE.md                   架构 & 约定（给 Claude Code / 开发者）
└── README.md                   快速上手
```

> **注意**：`assets/scripts/falling_blocks.lua` 是早期原型，**未**出现在
> `EXTRA_SCRIPTS` 也不在 `packs/` 目录，因此当前**不会被加载**。若要恢复它，
> 把它改造成 `PACKS` 自注册的包放进 `scripts/packs/`（见 [PACK_SPEC](../tools/PACK_SPEC.md)）。

---

## 三、架构：Rust ↔ Lua 边界

这是整个项目的关键不变量：**Lua 永不直接接触 Bevy `World`**。

原因：直接接触需要跨 FFI 持有 `&mut World`（对借用检查器不友好），并强制 VM
实现 `Send + Sync`。取而代之的三段式：

1. **VM 是 `NonSend` 资源** —— `mlua::Lua` 单线程，系统通过 `NonSendMut<LuaVm>`
   在主线程运行。
2. **写路径（Lua → ECS）走命令队列** —— 暴露给 Lua 的 `game.*` 只往
   `CommandQueue`（存在 mlua app-data 里）**压入 `LuaCommand`**。
3. **Rust 系统排空队列并应用** —— 每帧调用 Lua 回调后，drain 队列，把每条命令
   落到 ECS。

**帧流程**（`Update`，按此顺序链式执行）：

```
reload_changed_scripts   资产加载/变更时重新执行 chunk，并调用 on_start
        ↓
run_lua                  调用 on_update(dt) → 排空并应用命令队列
```

**读路径（输入）**：`tick_lua` 在调用 `on_update` **之前**，把指针（鼠标/触摸的世界
坐标）和按键快照塞进 `Bridge` app-data；`game.pointer()` / `game.key(name)` 只读这份
快照。要加新的"读"（如实体位置），同样先塞快照，**绝不把 `&World` 交给 Lua**。

### 给 Lua API 加能力（务必三步齐做）

1. 在 `src/script.rs` 的 `enum LuaCommand` 加一个变体。
2. 在 `register_api` 里给 `game` 表注册一个函数，压入该变体
   （闭包内用 `lua.app_data_mut::<CommandQueue>()`）。
3. 在 `run_lua` 的 match 里处理该变体（这里才有 `Commands` 和 ECS 查询去真正改世界）。

---

## 四、Lua 宿主 API（`game.*` 全量）

脚本**只能**通过这张表和共享的 `GAME_KIT` 助手与宿主交流。当前 `game` 表提供：

| 分类 | 函数 | 说明 |
|------|------|------|
| 生成 | `game.spawn(x,y,w,h, r,g,b[,a]) -> id` | 纯色矩形精灵 |
|      | `game.spawn_sprite(x,y,w,h, name) -> id` | 纹理精灵（`assets/textures/<name>.png` 必须已存在） |
|      | `game.spawn_text(x,y,size, r,g,b,a, str) -> id` | 文本（**ASCII only**） |
| 变换 | `game.move_to(id,x,y)` | 移动 |
|      | `game.set_color(id,r,g,b,a)` | 改颜色（可 tint 灰度纹理：orb/paddle/brick/tile） |
|      | `game.set_size(id,w,h)` | 改 `custom_size` |
|      | `game.set_rotation(id, radians)` | 旋转 |
|      | `game.set_sprite_image(id, name)` | 换纹理 |
|      | `game.despawn(id)` | 销毁 |
| HUD/表现 | `game.set_text(str)` | 左上角 HUD 单行（受 `SETTINGS.hud` 控制） |
|      | `game.shake(0..1)` | 屏幕震动（叠加 trauma；同时驱动背景着色器） |
|      | `game.set_bg_theme(v)` | 切背景主题 |
|      | `game.play_sound(name)` / `game.play_music(name)` | `assets/audio/<name>.wav` |
|      | `game.haptic("light"/"medium"/"heavy"/"success")` | iOS 触感（桌面为 no-op） |
| 读 | `game.pointer() -> x,y,down` | 指针世界坐标 + 是否按下 |
|      | `game.key(name) -> bool` | 按键是否按住 |
|      | `game.bounds() -> hw,hh` | 屏幕半宽/半高（原点在中心，+y 向上） |
| 杂项 | `game.log(str)` | 打日志 |

对应的 `LuaCommand` 变体：`Spawn / MoveTo / SetColor / SetSize / SetRotation /
SetSpriteImage / SpawnText / SpawnSprite / Despawn / SetText / Shake / SetBgTheme /
PlaySound / PlayMusic / Haptic`。

### GAME_KIT 共享助手

`K = GAME_KIT`：`K.clamp / K.sign / K.in_rect(rect,x,y)`、`K.tracker() -> T`
（自动追踪 `T.spawn/T.sprite/T.text`，`T.clear()` 一键清理）、
`K.make_back(T,hw,hh)`（返回菜单按钮）、`K.switch("menu")`。

---

## 五、场景路由与游戏包系统

`assets/scripts/main.lua` 是一个**极小的场景路由**：

- 每个游戏是一个闭包，返回 `{ enter, update, tap, leave }`，自己追踪实体（`leave` 时清理），
  并暴露 `DEBUG` 表供测试驱动。
- 菜单从全局 `PACKS` 表构建。任何在 `main.lua` **之前**加载的脚本都能把自己
  **自注册**进 `PACKS`（按 `key` 去重，热重载安全）。
- `tier` = `preset` | `curated` | `ai`，`slot` 在同 tier 内排序。菜单据此自动生成，
  **无需改其它文件**。

**加载顺序**（`src/script.rs`）：
1. `EXTRA_SCRIPTS`（roguelike / game2048 / shooter / world / match3 / umami）
2. `PACKS_DIR = scripts/packs/` 下运行时扫描到的 `*.lua`（drop-in 包，如 catch）
3. 最后是 `main.lua`（它的 `on_start` 能看到前两批定义的 `make_*` 全局与 `PACKS`）

### 当前游戏一览

| 游戏 | 文件 | tier | 玩法 |
|------|------|------|------|
| Grow Paddle | main.lua | preset | Pong 变体，绿球长桨、红球缩桨 |
| Breakout | main.lua | preset | 打砖块（Bevy 示例移植） |
| Snake | main.lua | preset | 贪吃蛇 |
| Roguelike | roguelike.lua | — | 竞技场幸存者（浮动摇杆/WASD） |
| 2048 | game2048.lua | — | 滑动合并数字 |
| Shooter | shooter.lua | — | 太空射击，拖动移动、自动开火 |
| Cozy Isle | world.lua | — | 动森式采集/建造沙盒 |
| Garden Match | match3.lua | — | 三消，含火箭/绽放特殊块 + 关卡目标 |
| Umami Cup | umami.lua | — | 单指弹弓对战（角色 + 终极技） |
| Fruit Catch | packs/catch.lua | ai | 拖篮子接水果（drop-in 包示例） |
| Starforge | packs/forge.lua | ai | 数学驱动混合休闲主推：引力井 `a=GM/r²` × 聚变 `a+a→2a`，按住瞄准松手入轨；每日挑战/图鉴/升级树/成就全套 meta（方案见 docs/hybrid-casual-math-game-plan.md） |
| Fireflies | packs/fireflies.lua | ai | boids 三规则 + 指尖追光放牧萤火虫群；光环聚群得分、避蛛网（M0 对决对照组） |

新增游戏请照 [`tools/PACK_SPEC.md`](../tools/PACK_SPEC.md)：定义 `make_<key>()`
返回四个回调，文件末尾自注册进 `PACKS`，放进 `scripts/packs/` 即可被自动发现。

---

## 六、表现层：背景着色器、音频、触感、震动

- **自定义 WGSL 背景**（`src/background.rs`）：全屏 quad 上的 `Material2d`，片元着色器
  在 `assets/shaders/background.wgsl` 里画域扭曲的 FBM 极光 + 暗角。`vec4` uniform 打包
  `(time, aspect, energy, _)`；**energy 把着色器绑到玩法**——`drive_background` 读共享的
  `ScreenShake` trauma（每个游戏命中/得分都会 `game.shake`），attack-fast/release-slow
  平滑后加速流动、提亮、泛出青白闪光。所有迷你游戏无需改 Lua 就有反馈。
- **音频**：`game.play_sound/play_music` 映射到 `assets/audio/<name>.wav`。WAV 解码不在
  Bevy 默认里——`Cargo.toml` 开了 `wav` feature。音效由 `tools/gen_audio.py` 合成。
- **触感**：`game.haptic` 调 `ios/Sources/haptics.m` 的 `hl_haptic`，`#[cfg(target_os="ios")]`
  门控，桌面 no-op。
- **纹理精灵**：`spawn_sprite` 从 `assets/textures/<name>.png` 取图；`lib.rs` 用
  `ImagePlugin::default_nearest()` 保持像素锐利。

**On-screen 文本仅限 Latin**：Bevy 内置字体无 CJK/emoji 字形，非 ASCII 会渲染成空白框
并刷 ICU4X 报错。UI 文案保持英文。

---

## 七、构建 · 测试 · 上架

所有命令走 `Makefile`。工具链由 `rust-toolchain.toml` 固定为 stable ≥1.95
（机器全局默认是老旧的 1.71.1，**不要** `rustup default`）。

### 桌面

```bash
make run      # cargo run；运行时 Lua 热重载
make check    # cargo check
make clippy   # cargo clippy --all-targets
make fmt      # cargo fmt
make test     # Rust 单测 + Lua 无头玩法不变量测试
```

### 测试的两层

- **Rust 单测**（`src/script.rs` 的 `#[cfg(test)]`）：覆盖 `haptic_style`、
  相机震动 `shake_offset` 等纯函数。跑单个：`cargo test <name>`。
- **Lua 玩法不变量**（`tools/test_pong.lua`，需 `lua5.4`）：mock Rust `game` API，
  无头驱动 `main.lua` 数千帧，断言"手感契约"（无 teleport/tunneling、球速有上限、
  大 `dt` 卡顿不跳变）与尺寸机制（绿球长桨、红球缩桨、满屏赢、落地输）。
  改了玩法就扩展它——这套测试抓到过无界速度和未 clamp 的 `dt` bug。

### iOS

```bash
make ios-lib      # 仅为模拟器交叉编译静态库
make ios-project  # 从 project.yml 重新生成 .xcodeproj
make ios-build    # 为模拟器构建
make ios-run      # 构建 + 安装 + 启动模拟器（默认 SIM="iPhone 16"）
make device-run   # 真机（默认 Debug；真机务必用 CONFIG=Release，否则很卡）
make ios-ipa      # archive + 导出 TestFlight 用 .ipa
```

iOS 流水线：交叉编译静态库 → XcodeGen 生成工程 → xcodebuild → 安装/启动。
`project.yml` 是工程的唯一真实来源（`.xcodeproj` git-ignored、可再生）。自动签名：
`DEVELOPMENT_TEAM 4JFR4NTMKQ`，bundle id `com.ngmob.hollow`。真机需连接并解锁。

---

## 八、素材流水线

运行时**不需要**任何外部素材——纹理/音频都由 `tools/` 下的 Python 脚本程序化生成
（stdlib-only 编码器）：

- `gen_textures.py` / `gen_sprites.py` / `gen_world.py` / `gen_ui_art.py` — 像素图
- `gen_audio.py` — 合成音效/音乐
- `umami_assets.py` — Umami Cup 专用素材
- `slice_sheet.py` / `style_bible.py` — 切图 / 风格规范
- `floniks_*.{py,json}` — **Floniks AI 素材流水线**（通过 MCP 接入，把 AI 生成素材
  嵌进开发循环）

升级观感：按 `assets/ART_REQUESTS.md` 用**同名同尺寸**的 PNG 覆盖即可，代码零改动。

---

## 九、约定

- 新的**渲染/引擎能力**放 Rust；新的**行为/数值**放 Lua。若发现自己在重编 Rust
  只为调玩法数字，那说明这段逻辑该搬进 Lua。
- 精灵优先 `Sprite::from_color(...)`（demo 不强依赖纹理资产）。
- **Lua 错误保持非致命**：桥接层记录 `on_update` 错误并继续，绝不 panic 整个 app。
- 想扩展表现力（骨骼动画/粒子/tilemap）的具体方案与验收标准，见
  [`docs/roadmap-and-benchmark.md`](./roadmap-and-benchmark.md)。

---

## 十、延伸阅读

- [`CLAUDE.md`](../CLAUDE.md) — 架构 & 约定（最详尽的技术手册）
- [`tools/PACK_SPEC.md`](../tools/PACK_SPEC.md) — 做一个新游戏包的完整规范
- [`docs/ai-era-game-dev.md`](./ai-era-game-dev.md) — 观点 + 教程
- [`docs/no-editor-by-design.md`](./no-editor-by-design.md) — 为什么没有编辑器
- [`docs/roadmap-and-benchmark.md`](./roadmap-and-benchmark.md) — 评测对比 + Roadmap
- [`docs/web-deployment.md`](./web-deployment.md) — **Web 部署（GitHub Pages）与单游戏单 wasm 发布形态**（合集已不作为发布形态）
