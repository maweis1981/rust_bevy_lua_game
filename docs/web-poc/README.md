# Web 平台可行性 PoC — 结论与证据

> 目标：让现有的 Bevy + Lua 迷你游戏合集在浏览器里跑起来。本文记录可行性验证的
> **结论、踩到的坑、以及每一步的实证**。这是"先做 PoC 再决定全量投入"的产物。

## TL;DR

**可行。** 路线是 **`wasm32-unknown-unknown` + 纯 Rust Lua（ottavino）**。三个技术风险
已全部用实证扫清；剩下的是工程集成，不再有"能否做到"的研究性未知数。

## 为什么不能保留 C Lua（emscripten 死路）

Bevy 0.19 依赖 **winit 0.30.13**。查证其源码，web 后端的编译开关写死为：

```rust
// winit build.rs
web_platform: { all(target_family = "wasm", target_os = "unknown") }
```

winit 的 web 支持**只认 `wasm32-unknown-unknown`**，`platform_impl/` 下**没有 emscripten
后端模块**（emscripten 后端多年前已移除，只剩 changelog 记录）。

因此：
- 能跑 Bevy 的 web 目标**只有** `wasm32-unknown-unknown`；
- 而这个目标**编不了 vendored C Lua**（Lua 靠 `setjmp/longjmp` 做错误处理，该目标不支持，
  且无 libc）。

"保留 C Lua（emscripten）"和"Bevy 上 web"是**互斥**的——这是目标三元组的硬约束，
不是配置能绕过的。结论：Web 版必须换纯 Rust 的 Lua VM。

## 选型：ottavino（piccolo 的扩展 stdlib fork）

脚本对 Lua 运行时的实际需求（按频次）：`ipairs`(70)、`math.*`(random/sin/sqrt/…)、
`string.format`(17)、`string.rep`(4)、`table.remove/sort/insert/concat`、`pcall`、`tostring`。

| 候选 | 结论 |
|------|------|
| **piccolo 0.3.3** | ❌ stdlib 不全：`string` 只有 `len/sub/lower/upper/reverse`（**无 `format`/`rep`**）；`table` 只有 `pack/unpack`（**无 `insert/remove/sort/concat`**）。`main.lua` 的 `on_start` 里就有 `table.sort`，会当场挂。 |
| **ottavino 0.4.0**（piccolo fork） | ✅ 补齐了 `string.format/rep/find/gsub/match/gmatch`、`table.insert/remove/sort/concat/move`、`tonumber`。 |

### 实证 ①：ottavino 能跑真实脚本

用一个原生探针（stub 掉 `game.*`）驱动 `assets/scripts/main.lua`：

```
[lua log] Mini-game collection — started
OK: chunk executed (globals defined)
OK: on_start ran            <- table.sort + 比较器闭包 / string.format / pcall 全过
OK: 120 menu frames
OK: 300 post-tap frames      <- 经 on_tap 进入一个游戏并运行
PICCOLO/OTTAVINO PROBE: PASS
```

## 编 wasm 踩到并解掉的两个坑

1. **`getrandom` wasm 配置**：`getrandom` 0.2 与 0.3 同时在依赖树里，各需开启对应 feature
   （0.3 用 `wasm_js`，0.2 用 `js`）并设 rustflag：
   ```toml
   # .cargo/config.toml
   [target.wasm32-unknown-unknown]
   rustflags = ['--cfg', 'getrandom_backend="wasm_js"']
   ```
2. **ottavino 0.4.0 上游 bug**（`src/stdlib/math.rs`）：`math.randomseed` 把 `SmallRng`
   的种子硬编码成 `[u8; 32]`，但 32 位 wasm 上该种子是 `[u8; 16]` → 类型不匹配编不过。
   修法是按目标位宽推导长度：
   ```rust
   type SmallSeed = <SmallRng as rand::SeedableRng>::Seed;
   let seed: SmallSeed = core::array::from_fn(|idx| { /* idx % 16 ... */ });
   ```
   Web 版需**携带打过补丁的 ottavino**（并向上游提 PR）。

### 实证 ②：ottavino 编到 wasm 成功
`cargo build --target wasm32-unknown-unknown` 通过，产出 `.wasm`。

## 实证 ③：Bevy 编到 wasm 并在浏览器渲染

- `cargo build --target wasm32-unknown-unknown`（Bevy 0.19，~400 crate）通过。
- `wasm-bindgen --target web` 生成 JS 胶水 + `.wasm`。
- `python3 -m http.server` 静态托管，**无头 Chromium**（SwiftShader 软件 WebGL，
  适配无 GPU 容器）加载并截图：见 [`bevy-renders-in-browser.png`](./bevy-renders-in-browser.png)。
  浏览器控制台确认 `bevy_winit` 创建窗口、`bevy_render` 拿到 WebGL 2.0 adapter、逐帧运行；
  整块画面为 Bevy 的 `ClearColor`，经完整渲染管线画出。

> 注：软件 WebGL 下 `Sprite::from_color` 测试精灵未显示（clear 正常）——待集成阶段用
> 真实游戏画面复核（真实菜单大量用 sprite，是集成后第一屏要看的东西）。

## 静态托管 / GitHub Pages

Web 产物是 **100% 静态**：`index.html` + `*_bg.wasm` + wasm-bindgen `.js` + `assets/`。
GitHub Pages 可托管，注意：
- **相对路径**：Pages 走 `…github.io/<repo>/` 子路径，asset base 必须相对，否则 404。
- **无需 COOP/COEP**：走 WebGL2 + 单线程，不用 SharedArrayBuffer，故不需要跨域隔离头
  （Pages 也无法自定义响应头）——天然可行。
- **体积**：Bevy 的 release wasm（`wasm-opt` 后）~10–20MB，Pages 单文件上限 100MB，OK；
  Web 版必须用 **release** 构建（debug wasm 巨大且卡）。

## 实证 ④：整个游戏在浏览器里跑起来并可玩 ✅

把 ottavino 版 `LuaVm`（`Rc<RefCell<Bridge>>` 让 `'static` 回调持有命令队列；
`LuaCommand→ECS` 逻辑与 native 共享）接进真实 crate 的副本，编成 wasm，
无头 Chromium 加载：

- **完整菜单**：11 个游戏、图标（sprite）、自定义字体文本、极光背景 shader 全部渲染。
  见 [`browser-menu.png`](./browser-menu.png)。控制台确认 ottavino VM 跑了 `on_start`
  （`[lua] Mini-game collection — started`）、`loaded 8 Lua scripts`。
- **可交互**：点「Grow」进入 Pong——球拍/球/HUD（`9%` 每帧更新）全部由 wasm 里的
  ottavino Lua 驱动。见 [`browser-gameplay.png`](./browser-gameplay.png)。

这也顺带解掉了实证③里"软件 WebGL 下测试精灵未显示"的疑问：**真实游戏的 sprite 渲染正常**
（菜单里每个图标都是 sprite）。

### 集成阶段发现的两个 polish 点
- **`.meta` 404 噪音**：Bevy 会先探测每个资源的可选 `<asset>.meta` sidecar，Web 上不存在
  就 404（但会回退到默认 meta 并正常加载真实资源——所以画面完全正常）。用
  `AssetPlugin { meta_check: AssetMetaCheck::Never, .. }` 静音即可。
- **FPS**：截图里 FPS≈4 是因为 CI 容器**无 GPU**、走 SwiftShader 软件 WebGL；真机/带 GPU
  的浏览器有硬件 WebGL2 会流畅。

## 下一阶段：落地到仓库（productionize）

PoC 已在 scratchpad 的 crate 副本里跑通。把它正式落进仓库还需：

1. **cfg 隔离**：`script.rs` 拆成 `#[cfg(not(wasm))]` mlua 后端 + `#[cfg(wasm)]` ottavino 后端，
   共享 `LuaCommand`/`Bridge`/systems。**native/iOS 一行不改**（保证 `cargo check` 恒绿）。
2. **携带打补丁的 ottavino**：`getrandom` 种子那一行补丁——可选 vendor 进仓库、或指向 fork
   的 git 依赖、或等上游合并 PR。（PR 体积 vs 自包含的取舍，需拍板。）
3. **构建工具**：`make web`（`cargo build --release --target wasm32-unknown-unknown` →
   `wasm-bindgen` → 拷 `assets/`），release + `wasm-opt` 压体积；相对 asset base（Pages 子路径）。
4. **GitHub Pages 部署 CI**：push 自动编 wasm 并发布到 `…github.io/<repo>/`。
