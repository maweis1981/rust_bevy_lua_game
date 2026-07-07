# 能力评测对比 & Roadmap —— 表现力补全、AIGC 放大器与四阶段计划

> 姊妹篇 [《我们没有编辑器，这不是欠账，是设计》](./no-editor-by-design.md) 回答了"为什么"；本篇回答"接下来怎么办"：骨骼动画（Spine 类）、粒子、tilemap 这些表现力缺口**具体怎么补**，AIGC 能力的每一次提升**如何映射成工具集的升级**，我们与主流引擎的**逐项评测对比**，以及一份带验收标准的**四阶段 Roadmap**。

---

## 一、表现力三件套：怎么支持

原则先立住，方案才不跑偏。本项目加任何新能力都必须过三关：

1. **走命令队列桥**——Lua 只多几个 `game.*` 函数，引擎不变形；
2. **数据可 diff、可由 agent 生成**——拒绝引入任何二进制私有格式；
3. **无头测试能驱动**——不能断言的能力不算完成。

### 1.1 骨骼动画（Spine 类）：三条路线，推荐 AIGC 原生的那条

**路线 A：接 `bevy_spine`（官方 Spine 运行时的 Rust 封装 `rusty_spine`）。**
优点：工业级成熟、支持 `.json`/`.skel`、WASM 兼容、动画师生态大。
代价有两条要诚实说：其一，**Spine 运行时的使用在法律上要求持有有效的 Spine 编辑器付费许可**——而"必须先买一个 GUI 编辑器的许可"与我们无编辑器的整个论证相抵触；其二，社区 crate 对 Bevy 新版本存在**版本滞后风险**（Bevy 每 3-4 个月一个 breaking 版本，插件作者需要追）。
**结论：作为兼容选项保留**（团队里有现成 Spine 资产/动画师时启用），不作为主路线。

**路线 B（推荐）：自研 AIGC 原生的轻量 cutout 骨骼系统。**
2D 手游需要的骨骼动画，95% 是 cutout（剪纸式）：角色拆成部件，按父子层级旋转/平移/缩放，关键帧之间插值。这套东西在 Bevy 里的地基是现成的——`Transform` 父子层级 + 每帧插值，正是 ECS 最擅长的活。方案：

- **rig 即数据**：一个角色 = 一份 `rig.json`（部件列表、锚点/枢轴、父子关系、动画剪辑 = 关键帧数组 + 缓动），纯文本、可 diff、可 review——**agent 可以直接生成和修改 rig**，这是 Spine 二进制工作流永远给不了的；
- **部件即 AIGC 产物**：Floniks 按风格圣经生成分层部件（头/躯干/四肢/武器，透明底，`floniks_manifest.json` 里每个部件多声明一个 `pivot` 锚点字段），管线自动落位；
- **桥上开三个洞**：`game.spawn_rig(name) -> id`、`game.play_anim(id, clip, loop)`、`game.set_bone(id, bone, angle, x, y)`（手动覆写，做程序化动画如"手指向指针方向"）；
- **测试即验收**：无头套件 mock 时钟驱动 rig，断言"任一骨骼单帧转角 ≤ 上限、动画循环回到起始位姿、部件永不脱离锚点"——手感契约延伸到动画。

工作量评估：Rust 侧一个插值系统 + 三个 LuaCommand（估 400–600 行，含测试），rig JSON 的 schema 一页纸。**这是 agent 一个 loop 周期能吃下的活。**

**路线 C（今天就能用）：帧动画增强。** `set_sprite_image` 换帧已在库；补一个 `TextureAtlas` 原生支持（见 Roadmap P0）后，序列帧动画的性能和用法都会舒服一个档次。骨骼没到位之前，Floniks"关键帧图 → 图生视频 → 抽帧"的序列帧管线是完全够用的过渡方案。

### 1.2 粒子系统：GPU 的接生态，简易的进桥

- **主路线：`bevy_hanabi`**（GPU 粒子，效果表达力强，Bevy 生态标准答案）。桥上暴露声明式接口：`game.emit(preset, x, y, {…})`，preset（火花/尘土/彩带/水花）定义在一份 `particles.json` 里——同样是"效果即数据"，agent 可生成新 preset，测试断言"粒子数上限、生命周期归零后实体清空"。
- **兜底路线**：桥内 200 行的 CPU 简易粒子（spawn 一批小 sprite + 寿命/速度/淡出），零依赖，iOS 上对小游戏量级完全够。**先上兜底、后换 hanabi，Lua API 不变**——这是命令队列架构的红利：实现可以整体换血，脚本一行不动。

### 1.3 Tilemap：`bevy_ecs_tilemap` + AIGC 图集

- 接 `bevy_ecs_tilemap`（tile 即实体、GPU 动画、支持等距/六边形）；Lua API：`game.tilemap(w, h, tileset)`、`game.set_tile(tx, ty, index)`。
- **AIGC 一侧才是重头**：tileset 由 Floniks 按风格圣经生成（地面/边缘/角件一张图集），`slice_sheet.py` 已经会切；再写一个 50 行的 autotile 规则（Wang tiles / 4-bit 掩码），agent 用一句"生成一片有湖的草地"就能产出整张地图数据（JSON 网格，可 diff、可测试）。
- 关卡编辑的答案也在这里：**关卡即数据 + agent 生成 + 不变量测试**（出生点可达、边界封闭），替代人手在编辑器里摆——这正是上一篇 blog 里承认"还没做到"的那块拼图。

---

## 二、AIGC 能力提升 → 工具集升级的映射

我们的工具集设计成"AIGC 每变强一格，管线自动变强一格"。映射关系一览（右列为 Floniks 现有节点/能力，非虚构）：

| AIGC 能力 | 映射到的工具/管线 | 状态 |
|---|---|---|
| 文生图（风格锁定） | `style_bible.py` + `floniks_manifest.json` → 全套 sprite/背景/UI | ✅ 在用 |
| 图生图 / inpaint | 素材微调（"剑柄改成金色"）不重画整图 | ✅ 平台有，待进 manifest 流程 |
| 去背景（rembg/BiRefNet） | 透明底部件 → **骨骼部件分层生成**（§1.1 路线 B 的原料） | ✅ 平台有 |
| 放大（Clarity/AuraSR） | 贴图 2x/4x 重制，manifest 改尺寸即重放 | ✅ 平台有 |
| 图生视频 + 视频拆分 | 序列帧管线（关键帧 → 视频 → 抽帧）；宣传预告片 | ✅ 平台有，`slice_sheet.py` 承接 |
| 角色/场景护照 | 同一角色跨表情、跨动作、跨部件的一致性——骨骼部件生成的前提 | ✅ 平台有 |
| 文生音乐 / 文生音效（TextToMusic/TextToAudio 节点） | 替换 `gen_audio.py` 合成占位 → 每个游戏包一首风格化 BGM + 成套音效 | 🔶 平台有节点，管线待接 |
| 批量/循环/工作流（DAG） | 一次执行产整套素材（`create_workflow` 存成"美术流水线即代码"） | ✅ 平台有，MCP 可编排 |
| LLM 生成结构化数据 | rig.json、粒子 preset、tilemap 网格、关卡数据——**表现力三件套的"编辑器"就是它** | ✅ 就是 agent 本身 |
| （未来）3D 生成 | 预渲染八方向 2D sprite（暗黑式），仍走同一条 manifest 管线 | ⏳ 前瞻 |

看出模式了吗：**每一行的落点都是"一份可 diff 的数据 + 一条可重放的管线"**。所以 AIGC 模型升级（更强的一致性、更高的分辨率、更好的音乐）不需要我们改架构——换个 `FLONIKS_MODEL_ID`，重放清单，全库素材原地进化。这是把 AIGC 焊死在工具集里和"在网页上生成完再手动拖进来"的本质区别。

---

## 三、评测对比：我们 vs 主流引擎

以"一个小团队做 2D 手游"为场景，逐项对比（✅ 强 / 🔶 有但弱或需插件 / ❌ 无）。打分尽量苛刻，包括对我们自己。

| 维度 | **本项目** | Unity | Godot | Cocos Creator | Defold |
|---|---|---|---|---|---|
| 2D sprite 渲染 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 帧动画 | ✅ TextureAtlas 原生（`spawn_sheet`/`set_frame`，2026-07-07） | ✅ | ✅ | ✅ | ✅ |
| 骨骼动画 | ✅ 自研 cutout（rig.json + `spawn_rig`/`play_anim`/`set_bone`，§1.1 路线 B，2026-07-07） | ✅ | 🔶 | ✅ | 🔶 |
| 粒子 | ✅ 兜底版（`game.emit`，2026-07-07；hanabi 升级 API 不变） | ✅ | ✅ | ✅ | ✅ |
| Tilemap | ✅ 兜底版（`game.tilemap`/`set_tile`，2026-07-07；ecs_tilemap 升级 API 不变） | ✅ | ✅ | ✅ | ✅ |
| 物理引擎 | ❌ → P2（avian2d 可选接） | ✅ | ✅ | ✅ | 🔶 |
| UI 系统 | ❌ 手写 rect | ✅ | ✅ | ✅ | 🔶 |
| 脚本热重载 | ✅ 秒级 | 🔶 domain reload 慢 | 🔶 | ✅ | ✅ |
| 玩法脚本对 LLM 的友好度 | ✅ Lua、API 一页纸 | 🔶 C# API 巨大 | 🔶 GDScript 语料少 | 🔶 | ✅ Lua |
| 工程全量可 diff（无二进制/GUI 工程） | ✅ **独有** | ❌ | 🔶 | ❌ | 🔶 |
| AIGC 素材管线内建（风格圣经→清单→落位） | ✅ **独有** | ❌ 靠第三方插件拼 | ❌ | ❌ | ❌ |
| 玩法不变量无头测试 | ✅ 967 行在跑 | 🔶 要自己搭 | 🔶 | 🔶 | 🔶 |
| agent 全链路可操作（含构建/签名/上架） | ✅ **独有**（Makefile+XcodeGen 全代码） | ❌ 编辑器人肉环节多 | 🔶 | 🔶 | 🔶 |
| 平台覆盖（今天） | ✅ macOS+iOS+**Web**（WASM 已上线，2026-07-06） | ✅ 全平台 | ✅ | ✅ 含小游戏 | ✅ |
| 商业化服务（IAP/广告/统计） | ❌ → P3 | ✅ | 🔶 | ✅ | 🔶 |
| 人才池 / 教程生态 | ❌ | ✅ | ✅ | ✅ | 🔶 |
| 许可与抽成 | ✅ MIT，零费用 | 🔶 Runtime Fee 风波前科 | ✅ MIT | ✅ | ✅ |
| 包体（空项目量级） | ✅ 原生小 | 🔶 | 🔶 | ✅ | ✅ |

**读表结论**：传统维度（表现力组件、平台、商业化、人才）我们今天全面落后——这是 6 年引擎和 20 年引擎的差距，装不了。但三行"独有"（全量可 diff、AIGC 管线内建、agent 全链路）恰好构成一个别人**补不了课**的组合：Unity/Cocos 可以出 AI 插件，但只要工程核心还是二进制场景 + GUI 编辑器，agent 就永远只是它们的外挂，而不是一等公民。**我们赌的不是在旧维度上追平，而是新维度的权重会持续上涨。** 落后的那些行，请看下一节——每一行都有编号的计划。

---

## 四、Roadmap：四个阶段，每项带验收

排序逻辑：先补"能上架"的地基（P0），再补"好看好玩"的表现力（P1），再深挖独有优势（P2），最后铺平台（P3）。每项标注技术选型与验收标准（无头测试能断言什么）。节奏上，每一项都设计成 agent 一到数个 loop 周期可完成的粒度。

### P0 · 产品化地基（当前 → 2026 Q3）—— ✅ 全部完成（2026-07-07）

| # | 项 | 方案 | 验收 | 状态 |
|---|---|---|---|---|
| 0.1 | **存档/持久化** | `game.save(key, val) -> ok` / `game.load(key)`，iOS 沙盒 + 桌面 config 目录，JSON 后端 | 测试：写→杀进程模拟→读回一致；最高分跨会话保留 | ✅ `e7a6e9f`（PR [#23](https://github.com/maweis1981/rust_bevy_lua_game/pull/23)）；过程记录 [#24](https://github.com/maweis1981/rust_bevy_lua_game/issues/24) |
| 0.2 | **多点触控** | `Bridge` 快照从单指针改为触点数组，`game.touches() -> {{x,y,id},…}` | 测试：mock 双指，断言两指坐标/id 可读 | ✅ `c87e38f`（PR [#30](https://github.com/maweis1981/rust_bevy_lua_game/pull/30)）；过程记录 [#29](https://github.com/maweis1981/rust_bevy_lua_game/issues/29) |
| 0.3 | **TextureAtlas 原生** | `game.spawn_sheet(x,y,w,h,name,fw,fh,cols,frames)` + `game.set_frame(id,i)`，接 Bevy `TextureAtlasLayout` | 测试：帧索引越界被钳制；`slice_sheet.py` 输出直接可用 | ✅ `5384908`（PR [#39](https://github.com/maweis1981/rust_bevy_lua_game/pull/39)）；过程记录 [#32](https://github.com/maweis1981/rust_bevy_lua_game/issues/32) |
| 0.4 | **摄像机 API** | `game.cam(x, y[, zoom])`（与 shake 叠加） | 测试：跟随目标时偏移收敛、zoom 有上下限 | ✅ `0fed6fe`（PR [#33](https://github.com/maweis1981/rust_bevy_lua_game/pull/33)）；过程记录 [#35](https://github.com/maweis1981/rust_bevy_lua_game/issues/35) |
| 0.5 | **CJK 字体 + i18n 雏形** | 子集化 CJK TTF 进 `assets/fonts/`（`subset_font.py` STRINGS 管线），`strings.json` 按 locale 查表 | 中文 UI 不再是方块 | ✅ 字体已在库（`bf33fff`/`ad8f884`，Pony Parade 中文 UI 在跑）；strings.json 查表待 i18n 需求触发 |
| 0.6 | **音频控制** | `set_volume(channel, v)` / `stop_music`（三通道即时生效） | 设置页音量滑块真实生效 | ✅ `c2ae48f`（PR [#36](https://github.com/maweis1981/rust_bevy_lua_game/pull/36)）；过程记录 [#37](https://github.com/maweis1981/rust_bevy_lua_game/issues/37)；WAV→OGG 独立跟进 |

### P1 · 表现力三件套（2026 Q3–Q4）—— 三件套全部提前落地（2026-07-07）

| # | 项 | 方案 | 验收 | 状态 |
|---|---|---|---|---|
| 1.1 | **粒子（兜底版先行）** | 桥内 CPU 粒子 → 后换 `bevy_hanabi`，API 不变（§1.2） | 粒子数上限、寿命归零即清空 | ✅ 兜底版 `7a71343`（PR [#42](https://github.com/maweis1981/rust_bevy_lua_game/pull/42)）；过程记录 [#40](https://github.com/maweis1981/rust_bevy_lua_game/issues/40)；hanabi 升级待接 |
| 1.2 | **cutout 骨骼系统** | 自研 rig.json + Transform 层级插值（§1.1 路线 B）；Floniks 分层部件管线（manifest 加 `pivot`） | 单帧转角上限、循环回位、部件不脱锚 | ✅ `cabac97`（PR [#48](https://github.com/maweis1981/rust_bevy_lua_game/pull/48)）：`src/rig.rs` + `spawn_rig`/`play_anim`/`set_bone`，rig.json 纯文本可 diff |
| 1.3 | **Tilemap** | sprite 网格兜底版 → 后换 `bevy_ecs_tilemap` + autotile 规则 + Floniks tileset（§1.3），API 不变 | 越界安全、图集帧钳制；可达性/封闭性断言随 P2 关卡数据落地 | ✅ 兜底版 `1175a42`（PR [#45](https://github.com/maweis1981/rust_bevy_lua_game/pull/45)）；过程记录 [#44](https://github.com/maweis1981/rust_bevy_lua_game/issues/44) |
| 1.4 | **物理（可选件）** | `avian2d` 以 feature flag 接入，默认关——小游戏手写 AABB 仍是主路线 | 开启后现有 12 游戏测试全绿（不回归） | ⏳ 未开始 |
| 1.5 | **bevy_spine 兼容层** | 路线 A 作为可选 feature（有 Spine 资产的团队用） | 官方示例骨骼在 iOS 真机 120Hz 播放 | ⏳ 未开始 |

### P2 · AIGC 深度集成（2026 Q4 – 2027 Q1）

| # | 项 | 方案 | 验收 |
|---|---|---|---|
| 2.1 | **音频管线接 Floniks** | TextToMusic/TextToAudio 节点 → `audio_manifest.json`（音频版风格圣经：BPM/调性/配器锁定） | 每个游戏包一键生成整套 BGM+音效 |
| 2.2 | **美术流水线即工作流** | 把"生成→抠底→放大→落位"沉淀为 Floniks `create_workflow`，MCP 一次调用整包素材 | 新游戏包从 PACK_SPEC 到全套素材 ≤ 1 次工作流执行 |
| 2.3 | **rig 部件自动生成** | 角色护照 + 分层部件 prompt 模板 → agent 产 rig.json 初稿 | 生成的 rig 直接通过 1.2 的动画测试 |
| 2.4 | **关卡即数据** | tilemap/摆放 JSON + 生成规则 + 可达性测试（编辑器问题的最终回答） | agent 一句话产关卡且测试全绿 |
| 2.5 | **预告片管线** | 截图/录屏 → Floniks 图生视频 → 上架物料 | App Store 预览视频全自动产出 |

### P3 · 平台与商业化（2027 H1）

| # | 项 | 方案 | 验收 |
|---|---|---|---|
| 3.1 | **Android** | cargo-ndk + Gradle 模板（对标 `ios/build_rust.sh` 的模式） | 同一 crate 双端跑同一套游戏包 |
| 3.2 | **Web/WASM** | wasm-bindgen + ottavino（纯 Rust Lua VM）；试玩即传播（memeplay 的启示） | 任一游戏包一条链接可玩 —— ✅ **已完成（2026-07-06，提前两个季度）**：`51aa8e8` 起 `e2419ae`→`d69333e`→`b223215`→`a1aa30f`，GitHub Pages 在线可玩，全部 12 游戏 + 音频 + 存档（localStorage）同一条链接 |
| 3.3 | **Game Center / IAP** | 按 `haptics.m` 模式写 FFI shim（这条路径已被触觉反馈验证） | 排行榜提交、恢复购买走通 |
| 3.4 | **统计/崩溃上报** | 轻量自建或接开源端点，进命令队列（`game.track(event)`） | 事件在后台可查 —— ✅ 本地事件日志已落地（`game.track(event[, value])`，`ed37eda`，PR [#50](https://github.com/maweis1981/rust_bevy_lua_game/pull/50)）；远端端点待接 |
| 3.5 | **上架** | TestFlight（管线已合并）→ App Store 正式发布 | 第一个真实用户 |

### 风险与对冲

- **生态 crate 版本滞后**（hanabi/tilemap/spine 追 Bevy 破坏性版本有时差）→ 对冲：所有第三方 crate 都藏在命令队列桥后，Lua/游戏零感知；必要时可锁 Bevy 版本半年不升，或让 agent 自己出 patch（migration guide 喂给它即可）。
- **Spine 许可**（运行时使用要求持有付费编辑器许可）→ 对冲：主路线是自研开放格式（1.2），Spine 仅作兼容 feature，默认不编译。
- **AIGC 生成质量波动** → 对冲：程序化生成器永远保底，游戏任何时刻可跑；manifest 可重放意味着"重 roll 一次"成本趋近于零。
- **范围蔓延** → 对冲：每个 P 阶段末跑全量 `make test` + 真机 FPS 验收；测试行数必须随功能行数同步增长（这条已经是仓库的既成传统）。

---

## 五、支持记录（从不支持到支持的实测速度）

Roadmap 承诺"每一项都是 agent 一到数个 loop 周期能吃下的活"。2026-07-07 上午的实测远超预期：**两条并行的 agent 流水线各自独立把整批缺口从 ❌ 做到 ✅**，互为交叉验证。先合入 main 的系列成为正史（PR #23–#50，含本表未列的 1.2 骨骼与 3.4 统计）；另一条流水线（issues #24–#44）的独立实现保留在合并历史里（PR [#47](https://github.com/maweis1981/rust_bevy_lua_game/pull/47)），其 issue 里有逐项的分解→实现→测试→回归→合并全过程与分钟级计时。

正史落地（main）：

| Roadmap 项 | Lua API | 落地 commit | PR |
|---|---|---|---|
| 0.1 存档/持久化 | `game.save` / `game.load` | `e7a6e9f` | [#23](https://github.com/maweis1981/rust_bevy_lua_game/pull/23) |
| 0.2 多点触控 | `game.touches` | `c87e38f` | [#30](https://github.com/maweis1981/rust_bevy_lua_game/pull/30) |
| 0.3 TextureAtlas | `game.spawn_sheet` / `game.set_frame` | `5384908` | [#39](https://github.com/maweis1981/rust_bevy_lua_game/pull/39) |
| 0.4 摄像机 | `game.cam` | `0fed6fe` | [#33](https://github.com/maweis1981/rust_bevy_lua_game/pull/33) |
| 0.6 音频控制 | `game.set_volume` / `game.stop_music` | `c2ae48f` | [#36](https://github.com/maweis1981/rust_bevy_lua_game/pull/36) |
| 1.1 粒子（兜底版） | `game.emit` | `7a71343` | [#42](https://github.com/maweis1981/rust_bevy_lua_game/pull/42) |
| 1.2 cutout 骨骼 | `game.spawn_rig` / `play_anim` / `set_bone` | `cabac97` | [#48](https://github.com/maweis1981/rust_bevy_lua_game/pull/48) |
| 1.3 Tilemap（兜底版） | `game.tilemap` / `game.set_tile` | `1175a42` | [#45](https://github.com/maweis1981/rust_bevy_lua_game/pull/45) |
| 3.4 统计（本地日志） | `game.track` | `ed37eda` | [#50](https://github.com/maweis1981/rust_bevy_lua_game/pull/50) |

并行验证流水线的分钟级计时（同日，独立实现同批能力；commits 在 PR #47 合并历史中）：

| Roadmap 项 | 开始 (UTC) | 结束 (UTC) | 用时 | 过程记录 | Commit |
|---|---|---|---|---|---|
| 0.1 存档/持久化 | 2026-07-07 01:13:55 | 01:27:55 | **14 分钟** | [#24](https://github.com/maweis1981/rust_bevy_lua_game/issues/24) | `a7585bc679626e403710884f89791f2a328741ec` |
| 0.2 多点触控 | 01:29:00 | 01:30:52 | **2 分钟** | [#29](https://github.com/maweis1981/rust_bevy_lua_game/issues/29) | `0f824ceae31dc34660da05dd254d5be413fd5cfb` |
| 0.3 TextureAtlas | 01:31:38 | 01:33:31 | **2 分钟** | [#32](https://github.com/maweis1981/rust_bevy_lua_game/issues/32) | `29fd01033779826a32ee3b895071a65e0d45247c` |
| 0.4 摄像机 | 01:34:12 | 01:36:43 | **2.5 分钟** | [#35](https://github.com/maweis1981/rust_bevy_lua_game/issues/35) | `207184d0897d8d4dfca1dd74ec205fb1f30d7ca6` |
| 0.6 音频控制 | 01:37:27 | 01:39:50 | **2.5 分钟** | [#37](https://github.com/maweis1981/rust_bevy_lua_game/issues/37) | `fb23d302bae0cbb4ca13b42a83da5420431f7d6b` |
| 1.1 粒子 | 01:40:44 | 01:43:54 | **3 分钟** | [#40](https://github.com/maweis1981/rust_bevy_lua_game/issues/40) | `26065e087df2c7dd25ae0a05220baa4b15c00e99` |
| 1.3 Tilemap | 01:44:55 | 01:47:52 | **3 分钟** | [#44](https://github.com/maweis1981/rust_bevy_lua_game/issues/44) | `6df7847f0b1983bb1e592bf19cb4cf57a75fbf12` |

此前完成的平台项（同样从 ❌ 到 ✅）：

| Roadmap 项 | 落地 | 日期 | 关键 commits |
|---|---|---|---|
| 3.2 Web/WASM | 全部 12 游戏浏览器在线可玩（GitHub Pages），ottavino 纯 Rust Lua VM，音频/触控齐备 | 2026-07-06（原计划 2027 H1，**提前两个季度**） | `2686f22`（PoC）→ `51aa8e8`（跑通）→ `d69333e`（上线）→ `b223215`/`a1aa30f`（wasm-opt 修复） |
| 0.5 CJK 字体 | `subset_font.py` 子集管线 + Pony Parade 全中文 UI | 2026-07-02 起 | `bf33fff`（字体管线）、`ad8f884`（bold CJK） |

**方法论注脚**：两条流水线走的是同一套流程——issue 记录分解 → 双 VM 后端（mlua/ottavino）同步实现 → 纯函数单测 + 无头 Lua 断言 → `make test` 全量回归（12 游戏 13 万+项不变量）→ 独立 commit 关联 issue。速度的来源不是省步骤，而是架构：命令队列桥让每个新能力只是"一个 enum 变体 + 两处注册 + 一个 match 臂"，回归由既有测试网兜底。两条流水线在无协调的情况下给出了 API 形状几乎一致的实现，本身就是"架构决定生产速度"的一次对照实验。

---

## 六、一句话总结

**表现力的缺口（骨骼/粒子/tilemap）全部有清晰、agent 粒度的补全路径，且每一项的"编辑器"都是数据 + AIGC，而不是 GUI；评测表上我们今天输掉的每一行都在 Roadmap 里有编号，而我们赢的三行，对手在现有架构下补不了。**

*生态依据：[bevy_spine](https://github.com/jabuwu/bevy_spine)（基于 rusty_spine，WASM 兼容）、[bevy_hanabi](https://bevy.org/assets/)（GPU 粒子）、[bevy_ecs_tilemap](https://github.com/StarArawn/bevy_ecs_tilemap)（tile 即实体、GPU 动画、等距/六边形）；Floniks 节点能力见 floniks.com/developers/mcp。*
