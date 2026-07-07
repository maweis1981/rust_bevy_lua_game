# M3 视听计划 ·《星核熔炉》风格圣经 + 素材清单 + Floniks 工作流设计

> **状态：待制作人批准后执行**（生成会消耗 Floniks 积分；当前余额 106,328，
> 本计划全量预算 <1,000 积分含重 roll，见 §四）。批准方式：在 PR #58 或本文档对应
> issue 评论"批准 M3 生成"即可，loop 会自动接手执行。
> 前置：M0 对决判定（若萤火牧歌胜出，§五 备用清单生效，预算同量级）。

## 一、风格圣经（Style Bible v1 草案）

**概念**：深空锻炉（cosmic forge）。你是在黑洞边缘锻星的匠人——画面要同时传达
"天体的宏大"与"锻造的炽热工艺感"。

- **色彩**：深空底（#0B0A1E 靛黑）+ 星核十级冷→热色阶（现有 RAMP：冰蓝→青→绿→
  黄→橙→红→品红→纯白），点缀金色（结算/成就）。饱和度高、剪影清晰（买量素材可用）。
- **材质**：星核 = 熔融矿物球体，表面有裂纹状发光脉络（tint 后仍可读，故底图为
  **灰度高细节**）；黑洞 = 哑光纯黑球 + 细吸积环。
- **光照**：单一强内发光（星核自发光），无外部光源方向——规避 tint 后光照矛盾。
- **构图规则**：所有 sprite 居中、正圆构图、透明底、边缘 2% 安全边距；像素风格
  不强制（nearest 采样下高清纹理同样锐利）。
- **Prompt 模板**（textToImage）：
  `"a single molten mineral sphere, glowing crack veins, grayscale, centered, pure black background, game asset, high detail, no text"`
  —— 每资产替换主体短语，风格尾缀锁定不变。

## 二、图像素材清单（同名同尺寸替换，代码零改动优先）

| # | 文件 | 尺寸 | 用途 | 生成→处理链 |
|---|---|---|---|---|
| 1 | `orb.png`（覆盖） | 256² | 星核底图（灰度可 tint，十级共用） | 生图→去背→放大 |
| 2 | `forge_core.png`（新） | 256² | 黑洞 + 吸积环（forge.lua 换名 1 行） | 生图→去背 |
| 3 | `forge_ghost.png`（新） | 128² | 瞄准幽灵环 | 生图→去背 |
| 4 | `sparkle.png`（覆盖） | 128² | 粒子/萤火虫共用光点 | 生图→去背 |
| 5 | `paddle.png` 等 UI 底 | 256×128 | 按钮/面板质感（结算卡/商店） | 生图→去背 |
| 6 | 商店图标 ×3（新） | 128² | EXTRA CORE/STABLE NEBULA/HEAD START | 生图→去背 |
| 7 | `icon_dust.png`（新） | 64² | 星尘货币图标 | 生图→去背 |

约 12 张图（含 6 的三张）。**程序化生成器保底不动**——任何一张不满意，回滚同名文件即可。

## 三、音频清单（TextToMusic / TextToAudio）

- **BGM 三段同家族**（同调性同 BPM≈96，无缝主题变奏）：菜单（ambient 稀疏）、
  局内（脉冲低音 + 太空合成器）、高压（同主题 +20% 密度，场上质量高时切换——
  引擎已有 energy 通道可驱动切换逻辑，M3 实现）。
- **SFX 族 8 个**：投放、聚变（5 级以下/以上两档）、combo 升调链 ×3、吞噬、超新星。
  Prompt 锁定："deep space forge, metallic resonance, sub-bass impact"。
- 交付格式 WAV（`audioConvert` 节点转），同名替换 `assets/audio/`。

## 四、Floniks 工作流设计与积分预算

一条可重放的 `create_workflow` DAG（"美术流水线即代码"，方案 P2.2）：

```
textInput(风格尾缀) ─┬→ stringFunction(主体×N) → batchRender → removeBackground → upscale → fileOutput
                     └→ textToMusic ×3 → audioConvert → fileOutput
                        textToAudio ×8 → audioConvert → fileOutput
```

| 项 | 单价 | 数量 | 小计 |
|---|---|---|---|
| 生图 batchRender | 5 | 12 | 60 |
| 去背 | 5 | 12 | 60 |
| 放大（仅 orb/core） | 8 | 2 | 16 |
| BGM textToMusic | 10 | 3 | 30 |
| SFX textToAudio | 5 | 8 | 40 |
| **一轮合计** | | | **206** |
| 含 3 轮重 roll 预算 | | | **~650** |

余额 106,328 → 本计划占用 <0.7%。

## 五、备用：萤火牧歌胜出时的清单差异

星核十级色阶 → 萤火虫（发光腹部、翅膀模糊）、蛛网（半透明）、光环（柔光盘）、
夜森林 UI 底；BGM 改"夜曲/萤光"家族。数量与预算同量级（~12 图 + 11 音频）。

## 六、执行与验收（批准后 loop 自动跑）

1. `create_workflow` 建 DAG → `execute_workflow` → 产物落 `assets/`（同名替换）；
2. `consistencyEval` 一致性 ≥85 分门禁，不达标自动重 roll（预算内）；
3. `make test` 全量回归（素材替换不动逻辑，断言应全绿）；
4. 桌面截屏对比 + Web 构建刷新 → 制作人验收观感；
5. blog 记录 + manifest 沉淀（`floniks_manifest.json` 追加，可整包重放）。
