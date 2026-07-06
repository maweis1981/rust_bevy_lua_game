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

## 下一阶段（工程集成，非研究）

1. wasm 专用 `ScriptPlugin`（ottavino 版）——`Rc<RefCell<Bridge>>` 让 `'static` 回调持有
   命令队列；`LuaCommand→ECS` 与 native 共享。**mlua（native/iOS）完全 cfg 隔离，不改。**
2. 接入真实 crate → 编整个游戏到 wasm；处理 `assets/` 相对加载、`file_watcher`/`std::fs`
   的 wasm gate（`discover_packs` 在 wasm 上改用静态清单）。
3. serve + 截真实菜单 → 证明菜单 + preset 游戏在浏览器可玩。
4. GitHub Pages 部署 CI（push 自动上线）。
