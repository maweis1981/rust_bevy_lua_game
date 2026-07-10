# TikTok Mini Game 选品分析 — 激励视频高频 × 不反感 × 在我们能力内

> 目标：在 **TikTok Mini Games（TTMinis / HTML 运行时）** 上，选出既**契合我们
> 现有技术能力**、又能让**激励视频广告（rewarded video）展现机会多**、且**用户
> 不反感**的品类，并给出可执行的短名单。
>
> 结论先行：**合成掉落（Suika）** 与 **分类倒水（Ball/Water Sort）** 是投入产出比
> 最高的两个下一作；再加一层可复用的**「结算×2 / 复活 / 每日转盘」元层**贴到
> 每个游戏上，就能把每场的激励视频展现拉到健康的 6–10 次而几乎不惹人烦。

---

## 1. 约束三角：任何候选都要同时过这三关

### A. 我们的能力范围（硬约束）
来自 `miniprogram/RESEARCH.md` 与现有实现：

- **纯 JS + Canvas 2D，零依赖**；`shared/` 引擎在无 DOM 的微信/抖音和有 DOM 的
  TikTok 三端同一份代码跑（引擎仅 ~56KB）。
- **无 3D / 无 wasm**：Bevy/wgpu 的 25MB wasm 在小游戏里是死路（体积 + 无 DOM，
  RESEARCH §3–4）。凡是需要重渲染/重物理/重资源管线的品类**直接排除**。
- **确定性 + 种子随机**：已有 BigInt 精确 LCG（`shared/rng.js`），天然适合
  「无限关卡靠种子生成」「可复现排行榜」。
- **单指 / 按住 / 拖拽**交互；**同步 KV 存档**（`localStorage` / `wx/tt.getStorageSync`）。
- **集合外壳架构**：每个新游戏 = 一个按需加载的子包，启动器不膨胀。做新游戏成本低
  （现已有 7 个：catch / fireflies / forge(Starforge) / gallery / ponies /
  timedodge / snake 等）。
- **变现原语只有激励视频**：`createRewardedVideoAd`，奖励**必须由 `isEnded` 门控**
  （RESEARCH §5）；不能开任意外链、没有强制贴片。我们**已经有这套接线**
  （Time Dodge 的 ABSORB「取消这次撞击」= 复活式激励视频）。

### B. TikTok 平台特性（机会）
来自平台调研（见文末来源）：

- 市场 2025 约 **$2.75B**、高增速；**即点即玩、无需下载**，进入门槛极低。
- **竖屏、单手、短时长、信息流传播**；**超休闲 + 益智/街机**最吃香。
- **暖色 2D / 温馨画风 / 细节丰富的场景**在 TikTok 表现更好。
- **激励视频是超休闲的黄金变现方式**（自愿看 15–30s 换奖励）。

### C. 激励视频「高频且不反感」准则（设计红线）
来自广告变现最佳实践（见文末来源）：

- **永远 opt-in**，绝不强制贴片、绝不在开局前挡路。
- **绑定「失败 / 结算」时刻**，一次提示只给一个**自解释**的奖励。
- **奖励要值 15–30s**：翻倍级别（×2 金币/分数），不是「+5%」。
- 健康频次 **6–10 次/场**、日上限 ~15–20；**冷却 60–120s**；盯 opt-in 率下滑。
- **不打断高强度操作**（别在玩家躲避/连招时弹）。
- 转化最高的两个位：**结算金币翻倍**（opt-in 常 **>70%**）与**死亡后复活**。

---

## 2. 激励视频的「5 个黄金位」——品类好坏 = 能自然、高频地提供几个位

| # | 位（placement） | 触发时刻 | 反感度 | 频次潜力 |
|---|---|---|---|---|
| 1 | **复活 / 继续 Continue** | 死亡瞬间 | 极低（opt-in） | 高（越易失败越高） |
| 2 | **结算翻倍 ×2/×3 金币·分数** | 一局结束 | 极低 | 高（每局一次） |
| 3 | **看广告换道具/加速/额外招** | 局中卡点，玩家主动 | 低 | 中–高 |
| 4 | **解锁/免等待/补体力/开新槽** | 进度门槛 | 低 | 中 |
| 5 | **每日转盘 / 开宝箱 / 免费礼** | 进出游戏、元层 | 低 | 中–高 |

**判据**：核心循环能**自然且高频**地产出 #1（常失败）+ #2（永远有分/币可翻倍）的
品类最优；#3–#5 是可加装的放大器。

---

## 3. 品类评分表（1–5，越高越好；反感度越低越好）

| 品类 | 能力契合 | 激励位密度 | 不反感 | 开发量(低=好) | 我们已有基础 | 综合 |
|---|:--:|:--:|:--:|:--:|---|:--:|
| **合成掉落 Suika（西瓜/合成）** | 5 | 5 | 5 | 4 | Starforge 已按 Suika 模型改造 | ★★★★★ |
| **分类倒水 Ball/Water Sort** | 5 | 4 | 5 | 5 | 种子生成器现成 | ★★★★★ |
| **叠叠乐 Stack / 一键塔** | 5 | 4 | 5 | 5 | — | ★★★★☆ |
| **2048 / 数字合成** | 5 | 4 | 5 | 5 | — | ★★★★☆ |
| **Snake .io（贪吃蛇竞技）** | 5 | 4 | 4 | 5 | **已有 Snake** | ★★★★☆ |
| **合成进化 Merge idle（合成动物/物件）** | 4 | 5 | 4 | 2 | — | ★★★★☆ |
| **泡泡龙 / 弹珠 Plinko / 飞刀** | 4 | 4 | 4 | 4 | — | ★★★☆☆ |
| **放置/点击 Idle-clicker** | 4 | 5 | 3 | 3 | — | ★★★☆☆ |
| 3D/重资源/RPG/实时多人 | 1 | — | — | 1 | — | ✗ 排除 |

排除项原因：3D/重资源撞 wasm 死线；RPG/叙事内容重、单位工时激励密度低、不合短时长；
实时多人需要我们没有的后端。强制插屏/开局贴片**直接违背不反感红线**。

---

## 4. 推荐短名单（分三梯队）

### Tier 1 — 下一作首选（投入产出比最高）

**① 合成掉落 Suika（把 Starforge 打磨成独立一作）**
- 为什么：**失败=堆顶溢出→复活位天然**；**每局有分→结算×2 天然**；两大黄金位是格式
  自带的。Suika/合成在 TikTok/短视频**病毒性极强**，暖色 2D 讨喜，美术量低。
- 我们已reframe 为 Suika 模型（见 git `#90`），**离成品最近**。
- 激励位：复活（清顶几颗/继续）、结算×2、看广告换「下一个更大果实预览/换果」、每日转盘。

**② 分类倒水 Ball/Water Sort**
- 为什么：**建构成本最低**（纯色试管，无美术）；**种子生成无限关**（我们有精确 LCG，
  可复现）；激励位自解释——**撤销一步 / +1 空试管 / 提示**；零反感；休闲受众巨大。
- 激励位：卡关时「+1 试管」「撤销」「提示」、结算/过关礼、每日转盘。

### Tier 2 — 强候选（中等工时，多为现有资产的增量）

**③ 叠叠乐 Stack（一键塔）** — Canvas 2D 极简，单指，失败频繁→复活+×2，天生 brag-score。
**④ 2048 / 数字合成** — 网格极简、确定性；棋盘满→看广告「消一格/继续」+结算×2。
**⑤ Snake .io 元层升级** — **我们已有 Snake**，只需加「原地复活」「结算×2 质量」
「皮肤解锁」三个激励位 + 排行榜，**最省的增量变现赢**。

### Tier 3 — 激励密度最高，但工程更大（先用 Tier 1 验证广告收入再上）

**⑥ 合成进化 Merge idle** — 激励面最丰富（×2 收益计时、免费合成、离线收益翻倍、开新槽、
加速、宝箱），但需经济系统 + 持久存档 + 更多美术。适合作为收入验证后的「留存/ARPU 引擎」。

### 贯穿所有游戏的「可复用元层」（低成本、立刻抬升展现）
把这三件套做成集合外壳里的**共享模块**，贴到每个 mini-game：
1. **结算 ×2 分数/金币**（opt-in >70%）
2. **死亡后复活**（每局最多 1–2 次，冷却）
3. **每日转盘 / 每日礼**（进出游戏时）

我们**已有 `rewardAd` 接线**（ABSORB），复用即可——一次做，全集合受益，把每场展现推向
6–10 次而不增加反感。

---

## 5. 设计护栏（确保"不反感"，落到实现）

- **只 opt-in**：永不强制、永不开局前贴片；一个提示一个清晰奖励。
- **只在失败/结算触发**，绝不在躲避/连招中弹。
- **冷却 60–120s，日上限 ~15–20**，监控 opt-in 率（下滑=弹太多）。
- **奖励值 15–30s**：翻倍级，不是塞牙缝。
- **奖励由 `isEnded` 门控**（已是我们的契约）：看完才发，中途退按正常结算。
- **首玩宽松**：新玩家先顺畅玩几局，再逐步引入激励提示。

---

## 6. 一句话给决策

> 先做 **Suika（把 Starforge 收成独立作）+ Ball/Water Sort** 两款，配一层
> **「×2 / 复活 / 每日转盘」共享激励元层**：全部落在我们纯 JS Canvas 2D 的能力内、
> 复用已有的 rewardAd 接线、命中 TikTok 最吃香的超休闲/益智品类，且激励位都是
> opt-in 的失败/结算/元层时刻——展现频次高、用户不反感。

---

## 来源

平台与品类趋势：
- [TikTok Mini Games Overview（developers.tiktok.com）](https://developers.tiktok.com/doc/mini-games-overview)
- [TikTok Mini Games Growth Guide — Monetization, Ad Creatives & UA（Mobvista/XMP）](https://xmp.mobvista.com/en-blog/docs/tiktok-minigames)
- [Game Developer's Guide to TikTok Mini Games（BigSpy）](https://bigspy.com/blog/game-developers-guide-tiktok-mini-games)
- [TikTok Mini Game Market Trends 2025–2033（Data Insights Market）](https://www.datainsightsmarket.com/reports/tiktok-mini-game-1948387)

激励视频放置/频次/不反感最佳实践：
- [Rewarded Video Ad Placements — Unity](https://unity.com/blog/the-fundamentals-of-rewarded-video-ad-placements)
- [Best Practices for Rewarded Video Ad Placement — Pangle](https://www.pangleglobal.com/resource/27805)
- [Rewarded Ads in Mobile Games: Strategy, Data & Best Practices — AppSamurai](https://appsamurai.com/blog/rewarded-ads-in-mobile-games-strategy-data-and-best-practices/)
- [6 Secrets to Maximize Hyper-Casual Revenue — CrazyLabs](https://www.crazylabs.com/blog/how-to-maximize-your-hyper-casual-game-revenue/)

内部依据：`miniprogram/RESEARCH.md`（运行时/体积/激励视频 API 映射）、
`miniprogram/README.md`（集合外壳/子包架构）、`assets/scripts/packs/`（现有游戏）。
