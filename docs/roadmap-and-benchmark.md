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
| 帧动画 | ✅ `spawn_sheet`/`set_frame` 图集切帧（07-07，#39） | ✅ | ✅ | ✅ | ✅ |
| 骨骼动画 | ✅ 自研 cutout rig（§1.1 路线 B，07-07，#48） | ✅ | 🔶 | ✅ | 🔶 |
| 粒子 | ✅ CPU 兜底版（07-07，#42；hanabi 换血选项保留） | ✅ | ✅ | ✅ | ✅ |
| Tilemap | ✅ 轻量版（07-07，#45；ecs_tilemap 换血选项保留） | ✅ | ✅ | ✅ | ✅ |
| 物理引擎 | ❌ → P2（avian2d 可选接） | ✅ | ✅ | ✅ | 🔶 |
| UI 系统 | ❌ 手写 rect | ✅ | ✅ | ✅ | 🔶 |
| 脚本热重载 | ✅ 秒级 | 🔶 domain reload 慢 | 🔶 | ✅ | ✅ |
| 玩法脚本对 LLM 的友好度 | ✅ Lua、API 一页纸 | 🔶 C# API 巨大 | 🔶 GDScript 语料少 | 🔶 | ✅ Lua |
| 工程全量可 diff（无二进制/GUI 工程） | ✅ **独有** | ❌ | 🔶 | ❌ | 🔶 |
| AIGC 素材管线内建（风格圣经→清单→落位） | ✅ **独有** | ❌ 靠第三方插件拼 | ❌ | ❌ | ❌ |
| 玩法不变量无头测试 | ✅ 677 行在跑 | 🔶 要自己搭 | 🔶 | 🔶 | 🔶 |
| agent 全链路可操作（含构建/签名/上架） | ✅ **独有**（Makefile+XcodeGen 全代码） | ❌ 编辑器人肉环节多 | 🔶 | 🔶 | 🔶 |
| 平台覆盖（今天） | ✅ macOS+iOS+**Web/WASM**（07-06 上线，一条链接可玩） | ✅ 全平台 | ✅ | ✅ 含小游戏 | ✅ |
| 商业化服务（IAP/广告/统计） | 🔶 统计已通（`game.track`，#50）；IAP/广告 → P3 | ✅ | 🔶 | ✅ | 🔶 |
| 人才池 / 教程生态 | ❌ | ✅ | ✅ | ✅ | 🔶 |
| 许可与抽成 | ✅ MIT，零费用 | 🔶 Runtime Fee 风波前科 | ✅ MIT | ✅ | ✅ |
| 包体（空项目量级） | ✅ 原生小 | 🔶 | 🔶 | ✅ | ✅ |

**读表结论**：传统维度（表现力组件、平台、商业化、人才）我们今天全面落后——这是 6 年引擎和 20 年引擎的差距，装不了。但三行"独有"（全量可 diff、AIGC 管线内建、agent 全链路）恰好构成一个别人**补不了课**的组合：Unity/Cocos 可以出 AI 插件，但只要工程核心还是二进制场景 + GUI 编辑器，agent 就永远只是它们的外挂，而不是一等公民。**我们赌的不是在旧维度上追平，而是新维度的权重会持续上涨。** 落后的那些行，请看下一节——每一行都有编号的计划。

---

## 四、Roadmap：四个阶段，每项带验收

排序逻辑：先补"能上架"的地基（P0），再补"好看好玩"的表现力（P1），再深挖独有优势（P2），最后铺平台（P3）。每项标注技术选型与验收标准（无头测试能断言什么）。节奏上，每一项都设计成 agent 一到数个 loop 周期可完成的粒度。

### P0 · 产品化地基（当前 → 2026 Q3）—— ✅ 全部完成

| # | 项 | 方案 | 验收 | 状态 |
|---|---|---|---|---|
| 0.1 | **存档/持久化** | `game.save(key, val)` / `game.load(key)`，类型编码 KV，桌面/iOS 落盘（`$HOME/.hollowlullaby/`），wasm 会话内 | 测试：写→杀进程模拟→读回一致 ✅ | ✅ 07-07 `e7a6e9f`（#22/#23，约 7 分钟） |
| 0.2 | **多点触控** | `Bridge` 触点数组快照，`game.touches() -> {{x,y,id},…}` | mock 双指驱动两挡板 ✅ | ✅ 07-07 `c87e38f`（#28/#30，约 6 分钟） |
| 0.3 | **序列帧图集** | `game.spawn_sheet(...,fw,fh,cols,frames)` + `game.set_frame(id,i)`——用 `Sprite.rect` 切帧（比 TextureAtlasLayout 更轻，零纹理换绑） | 越界钳制 ✅；`slice_sheet.py` 直接可用 ✅ | ✅ 07-07 `5384908`（#38/#39，约 9 分钟） |
| 0.4 | **摄像机 API** | `game.cam(x,y,zoom)` 基准位姿，与 shake/zoom punch 叠加合成 | zoom 上下限（0.25–4）✅ | ✅ 07-07 `0fed6fe`（#31/#33，约 6 分钟） |
| 0.5 | **CJK 字体** | Noto Sans SC Bold 子集（`subset_font.py` STRINGS 表） | 中文 UI 不再是方块 ✅（小马拼图/深夜画廊全中文） | ✅ 07-06 `ad8f884`（#11）；i18n `strings.json` 查表后续 |
| 0.6 | **音频控制** | `game.set_volume(channel,v)`（三声道独立，music/voice 即时生效）/ `game.stop_music()` | 音量滑块引擎路径 ✅ | ✅ 07-07 `c2ae48f`（#34/#36，约 12 分钟）；WAV→OGG 单列跟进 |

### P1 · 表现力三件套（2026 Q3–Q4）—— 三件套 ✅ 全部完成

| # | 项 | 方案 | 验收 | 状态 |
|---|---|---|---|---|
| 1.1 | **粒子（兜底版先行）** | 桥内 CPU 粒子（4 预设 spark/dust/confetti/splash）→ 后换 `bevy_hanabi`，API 不变（§1.2） | 粒子数上限（512 硬钳含同帧突发）✅、寿命归零即清空 ✅ | ✅ 07-07 `7a71343`（#41/#42，约 8 分钟） |
| 1.2 | **cutout 骨骼系统** | 自研 `.rig` JSON + Transform 层级插值（§1.1 路线 B），pivot=Anchor 结构性防脱锚；Floniks 分层部件管线（P2.3 接） | 单帧转角上限 ✅（60fps 扫描断言）、循环回位 ✅、部件不脱锚 ✅（结构性） | ✅ 07-07 `cabac97`（#46/#48，约 14 分钟，`src/rig.rs`） |
| 1.3 | **Tilemap** | 桥内轻量版先行（根+子格实体、图集切帧、越界安全）→ `bevy_ecs_tilemap` 换血选项保留；autotile/可达性断言归 P2.4 | set_tile 越界 no-op ✅；tileset 与 `slice_sheet.py` 同契约 ✅ | ✅ 07-07 `1175a42`（#43/#45，约 8 分钟） |
| 1.4 | **物理（可选件）** | `avian2d` 以 feature flag 接入，默认关——小游戏手写 AABB 仍是主路线 | 开启后现有游戏测试全绿（不回归） | ⏳ 未动（可选件，crate 版本滞后风险对冲见下） |
| 1.5 | **bevy_spine 兼容层** | 路线 A 作为可选 feature（有 Spine 资产的团队用） | 官方示例骨骼在 iOS 真机 120Hz 播放 | ⏳ 未动（许可约束，主路线 1.2 已交付） |

### P2 · AIGC 深度集成（2026 Q4 – 2027 Q1）

| # | 项 | 方案 | 验收 |
|---|---|---|---|
| 2.1 | **音频管线接 Floniks** | TextToMusic/TextToAudio 节点 → `audio_manifest.json`（音频版风格圣经：BPM/调性/配器锁定） | 每个游戏包一键生成整套 BGM+音效 |
| 2.2 | **美术流水线即工作流** | 把"生成→抠底→放大→落位"沉淀为 Floniks `create_workflow`，MCP 一次调用整包素材 | 新游戏包从 PACK_SPEC 到全套素材 ≤ 1 次工作流执行 |
| 2.3 | **rig 部件自动生成** | 角色护照 + 分层部件 prompt 模板 → agent 产 rig.json 初稿 | 生成的 rig 直接通过 1.2 的动画测试 |
| 2.4 | **关卡即数据** | tilemap/摆放 JSON + 生成规则 + 可达性测试（编辑器问题的最终回答） | agent 一句话产关卡且测试全绿 |
| 2.5 | **预告片管线** | 截图/录屏 → Floniks 图生视频 → 上架物料 | App Store 预览视频全自动产出 |

### P3 · 平台与商业化（2027 H1）—— 3.2/3.4 已提前完成

| # | 项 | 方案 | 验收 | 状态 |
|---|---|---|---|---|
| 3.1 | **Android** | cargo-ndk + Gradle 模板（对标 `ios/build_rust.sh` 的模式） | 同一 crate 双端跑同一套游戏包 | ⏳ 需 Android SDK/NDK 环境 |
| 3.2 | **Web/WASM** | wasm-bindgen + **ottavino**（纯 Rust Lua VM，双后端同一 `LuaVm` 面）；试玩即传播 | 任一游戏包一条链接可玩 ✅ <https://maweis.com/rust_bevy_lua_game/> | ✅ 07-06 `51aa8e8`→`a1aa30f`（#4–#7，PoC→上线一天内） |
| 3.3 | **Game Center / IAP** | 按 `haptics.m` 模式写 FFI shim（这条路径已被触觉反馈验证） | 排行榜提交、恢复购买走通 | ⏳ 需 macOS/Xcode 环境 |
| 3.4 | **统计/崩溃上报** | `game.track(event[,value])` 进命令队列,本地 TSV 日志先行,远端端点只换 sink | 事件可查 ✅（`~/.hollowlullaby/analytics.log`） | ✅ 07-07 `ed37eda`（#49/#50，约 6 分钟） |
| 3.5 | **上架** | TestFlight（管线已合并）→ App Store 正式发布 | 第一个真实用户 | ⏳ 人工审核环节 |

### 风险与对冲

- **生态 crate 版本滞后**（hanabi/tilemap/spine 追 Bevy 破坏性版本有时差）→ 对冲：所有第三方 crate 都藏在命令队列桥后，Lua/游戏零感知；必要时可锁 Bevy 版本半年不升，或让 agent 自己出 patch（migration guide 喂给它即可）。
- **Spine 许可**（运行时使用要求持有付费编辑器许可）→ 对冲：主路线是自研开放格式（1.2），Spine 仅作兼容 feature，默认不编译。
- **AIGC 生成质量波动** → 对冲：程序化生成器永远保底，游戏任何时刻可跑；manifest 可重放意味着"重 roll 一次"成本趋近于零。
- **范围蔓延** → 对冲：每个 P 阶段末跑全量 `make test` + 真机 FPS 验收；测试行数必须随功能行数同步增长（这条已经是仓库的既成传统）。

---

## 五、实施记录 —— 2026-07-07 冲刺:9 项缺口,52 分钟清零

> Roadmap 不是愿景文档,是工单。这一节记录每项能力**从"不支持"到"合并上线"的真实耗时(UTC,精确到分钟)**,并对应到 GitHub issue(分解/实现/测试/回归/合并全过程)与 main 分支 commit。所有时间都是一次连续冲刺中的实测,不是估算。

### 冲刺时间线(2026-07-07,单 agent 连续执行)

| 能力 | 开始(UTC) | 合并(UTC) | 耗时 | Commit | Issue | PR |
|---|---|---|---|---|---|---|
| P0.1 存档 `save`/`load` | 01:05:47 | 01:12:52 | **7 分钟** | `e7a6e9f` | #22 | #23 |
| P0.2 多点触控 `touches` | 01:24:12 | 01:30:27 | **6 分钟** | `c87e38f` | #28 | #30 |
| P0.4 摄像机 `cam` | 01:30:47 | 01:33:10 | **2.5 分钟** | `0fed6fe` | #31 | #33 |
| P0.6 音量 `set_volume`/`stop_music` | 01:33:39 | 01:37:26 | **4 分钟** | `c2ae48f` | #34 | #36 |
| P0.3 图集 `spawn_sheet`/`set_frame` | 01:37:51 | 01:40:48 | **3 分钟** | `5384908` | #38 | #39 |
| P1.1 粒子 `emit` | 01:41:13 | 01:44:21 | **3 分钟** | `7a71343` | #41 | #42 |
| P1.3 Tilemap `tilemap`/`set_tile` | 01:44:51 | 01:47:54 | **3 分钟** | `1175a42` | #43 | #45 |
| P1.2 cutout 骨骼 `spawn_rig`/`play_anim`/`set_bone` | 01:48:42 | 01:53:56 | **5 分钟** | `cabac97` | #46 | #48 |
| P3.4 统计 `track` | 01:54:17 | 01:57:47 | **3.5 分钟** | `ed37eda` | #49 | #50 |

合计:**9 项能力,01:05 → 01:58,52 分钟**(含每项独立的 issue 建档、测试、回归、PR、squash 合并;P0.1→P0.2 之间的 11 分钟用于会话存档与教程文档,不计入功能耗时)。每个 issue 里有该项的分阶段耗时表。

### 此前已完成(本表补记)

| 能力 | 完成日 | Commit / PR | 备注 |
|---|---|---|---|
| P0.5 CJK 字体子集 | 07-06 | `ad8f884`(#11) | Noto Sans SC Bold,小马拼图/深夜画廊全中文 UI |
| P3.2 Web/WASM | 07-06 | `51aa8e8`→`a1aa30f`(#4–#7) | ottavino 纯 Rust Lua VM;PoC 到上线一天;<https://maweis.com/rust_bevy_lua_game/> |
| P2.1 音频管线接 Floniks(部分) | 07-06 | `ec45266`(#12)、`cd7a88a`(#14) | Lyria 2 BGM + minimax TTS 语音已实战(小马拼图/深夜画廊);`audio_manifest.json` 化待做 |
| P2.5 预告片管线(部分) | 07-06 | — | 小马拼图 15s 广告:真实素材关键帧 → Floniks 图生视频 + 配乐;自动化沉淀待做 |

### 并行对照组：同日第二条流水线（PR #47）

同一上午还有**第二条独立的 agent 流水线**在无协调的情况下实现了同批 7 项能力（issues [#24](https://github.com/maweis1981/rust_bevy_lua_game/issues/24)/[#29](https://github.com/maweis1981/rust_bevy_lua_game/issues/29)/[#32](https://github.com/maweis1981/rust_bevy_lua_game/issues/32)/[#35](https://github.com/maweis1981/rust_bevy_lua_game/issues/35)/[#37](https://github.com/maweis1981/rust_bevy_lua_game/issues/37)/[#40](https://github.com/maweis1981/rust_bevy_lua_game/issues/40)/[#44](https://github.com/maweis1981/rust_bevy_lua_game/issues/44)，逐项含分解→实现→测试→回归→合并全过程与计时）。上表系列先合入成为正史；对照组的独立实现（7 个逐功能 commit，`a7585bc`→`6df7847`）保留在 PR [#47](https://github.com/maweis1981/rust_bevy_lua_game/pull/47) 的合并历史中。

| 能力 | 开始(UTC) | 测试全绿(UTC) | 耗时 | 过程记录 |
|---|---|---|---|---|
| P0.1 存档 | 01:13:55 | 01:27:55 | 14 分钟（含 Bevy 全量编译） | #24 |
| P0.2 多点触控 | 01:29:00 | 01:30:52 | 2 分钟 | #29 |
| P0.3 图集 | 01:31:38 | 01:33:31 | 2 分钟 | #32 |
| P0.4 摄像机 | 01:34:12 | 01:36:43 | 2.5 分钟 | #35 |
| P0.6 音量 | 01:37:27 | 01:39:50 | 2.5 分钟 | #37 |
| P1.1 粒子 | 01:40:44 | 01:43:54 | 3 分钟 | #40 |
| P1.3 Tilemap | 01:44:55 | 01:47:52 | 3 分钟 | #44 |

两条流水线给出的 API 形状几乎一致（save/load、touches 数组、sheet+frame 钳制、cam+shake 叠加、512 粒子上限、tilemap 懒生成子格），互为交叉验证——**"架构决定实现速度与形状"的一次天然对照实验**。

### 为什么能这么快(复盘)

1. **命令队列架构摊薄了每个功能**:9 项全是"一个 LuaCommand + 双后端注册 + 一个 handler/系统"的同构套路,无一需要动架构。
2. **纯函数优先**:每项的核心逻辑(编码/钳制/几何/插值/采样)先写成纯函数,单元测试秒级跑,不用起引擎。
3. **13 万断言的回归网**:每次合并前全量跑,敢连续合并 9 个 PR 的底气。
4. **真实踩坑也在账上**:P0.6 两轮编译修正(Bevy 16 参数上限、解构后迭代器)、P1.2 一轮(Bevy 0.19 `Anchor` 改独立组件)、P3.4 一次磁盘满——都发生了,都在分钟级修复,全记录在对应 issue。

剩余未做项(1.4 物理 / 1.5 spine / 3.1 Android / 3.3 IAP / 3.5 上架)各自的阻塞原因已标注在上表状态列:两项是明确的可选件,三项被环境依赖(Android SDK / Xcode / 人工审核)卡住,不是工程量问题。

---

## 六、一句话总结

**表现力的缺口（骨骼/粒子/tilemap）全部有清晰、agent 粒度的补全路径，且每一项的"编辑器"都是数据 + AIGC，而不是 GUI；评测表上我们今天输掉的每一行都在 Roadmap 里有编号，而我们赢的三行，对手在现有架构下补不了。**

*生态依据：[bevy_spine](https://github.com/jabuwu/bevy_spine)（基于 rusty_spine，WASM 兼容）、[bevy_hanabi](https://bevy.org/assets/)（GPU 粒子）、[bevy_ecs_tilemap](https://github.com/StarArawn/bevy_ecs_tilemap)（tile 即实体、GPU 动画、等距/六边形）；Floniks 节点能力见 floniks.com/developers/mcp。*
