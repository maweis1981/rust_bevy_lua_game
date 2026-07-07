# Engine Showcase · 使用手册

## 1. 启动

| 平台 | 方式 |
|---|---|
| **浏览器**（推荐，零安装） | 打开 <https://maweis.com/rust_bevy_lua_game/>，加载后点一下屏幕解锁音频 |
| macOS 桌面 | 仓库根目录 `make run`（需 Rust stable ≥1.95；Lua 热重载开发模式） |
| iOS 模拟器 | `make ios-run`（默认 iPhone 16） |
| iOS 真机 | `make device-run CONFIG=Release`（Debug 构建在真机上会明显卡顿） |
| 本地 Web 构建 | `make web && make web-serve` → http://localhost:8000 |

主菜单中点 **Engine Showcase** 卡片进入。

## 2. 界面通则

- **左上角木牌**：返回主菜单（所有游戏一致）。
- **右上角 HUB**：从任意站回到 9 宫格。
- **右上角 BENCH**：开始/停止本站跑分（见 §4）。
- 顶部 HUD 文字实时显示本站状态（音量百分比、粒子数、当前笔刷……）。

## 3. 九个站怎么玩

### VAULT（存档）
点中央金币 +1 并立即写盘。副标题显示这是你这台设备第几次进站——这个数字杀掉 App 再开还会 +1。下方跑分板列出各站已保存的 BENCH 最好成绩。

### TOUCH（多点触控）
把手指放上去（最多 8 根），每根手指一个呼吸光环，抬起即消失。桌面上按住鼠标左键等效单指。

### ATLAS（图集动画）
中央大金币 + 一排小金币在不同相位旋转——全部来自同一张 6 帧贴图（`coin_sheet.png`），换帧零开销（改的是图集索引，不换纹理）。

### CAMERA（摄像机）
默认**跟随模式**：镜头追着无人机在一个约 3 倍屏幕宽的世界里巡游，带呼吸变焦。**点击任意处**切换到俯瞰模式（拉远看全图）。打击抖动（其他站触发的 shake）会叠加在镜头上而不是覆盖它。

### MIXER（混音台）
- 三条滑轨从上到下：MUSIC / SFX / VOICE，**按住拖动**圆钮即时改音量（正在播的也立刻变）。
- `PLAY MUSIC` 播放 Showcase 主题曲（Lyria 2 生成）；`STOP` 停止后再按 PLAY 会从头开始。
- `SFX BURST` 随机一枚音效；`VOICE` 播一句人声（会打断上一句——对话通道永不叠音）。

### SPARKS（粒子）
自动每 0.5s 一发随机烟花；**点哪炸哪**（confetti）。HUD 显示已发射次数与全局 512 上限——粒子超发不会崩，只会被预算裁剪。

### TILES（地形）
- **拖动手指作画**；`BRUSH` 循环切换草地→泥土→水面→石砖；`RESET` 恢复默认图案。
- 地图格坐标 (0,0) 在左上，行序向下——与关卡 JSON 文件一致，agent 生成的网格可以直接贴进来。

### ROBOT（骨骼）
- `IDLE` / `WAVE` / `WALK` 切换动画剪辑（定义在 `assets/rigs/robot.rig`，纯 JSON）。
- 机器人的**头始终看向你的手指**——这是 `set_bone` 手动覆写在剪辑之上的效果。

### JUICE（手感 + 统计）
四个按钮：SHAKE（屏幕抖动）、ZOOM（变焦冲击）、HAPTIC（触觉反馈，仅 iOS 真机有感）、ALL IN（全都要）。每次按压都会经 `game.track` 落一条本地分析日志。

## 4. BENCH 跑分

1. 进任意站按 **BENCH**。
2. 观察 HUD：`Lv` 每 0.75 秒 +1（伴随一声提示音），对应负载逐级上升。
3. 当帧时间守不住 1/45s 预算时定格，显示 `SCORE n` 并存档（破纪录会有成功音+触觉）。
4. 回 VAULT 站查看全部九项的最好成绩。
5. 再按一次 BENCH 复位重跑。

> 分数含义：**该能力在你这台设备上能守住 45fps 的最大负载档位**（上限 12 档）。分数用于横向比较设备/构建配置，不是绝对性能单位。

## 5. 给开发者：这个 demo 同时是 API 速查表

每个站的实现就是对应 API 的最小可用示例，全部在 `assets/scripts/packs/showcase.lua` 一个文件里（约 620 行，无引擎侧改动）。桥 API 的权威文档在 `src/script.rs` 文件头注释。

常见二次开发：
- **加一个站**：在 `stations` 表加一项 + `order` 加 key —— 60 行以内。
- **换机器人**：重新生成部件贴图 + 改 `robot.rig` 的 JSON，引擎零改动。
- **调 benchmark 口径**：`BUDGET`（帧预算）、`EPOCH`（加压周期）、`LEVEL_CAP` 三个常量。

## 6. 故障排查

| 症状 | 原因/处理 |
|---|---|
| 浏览器里没有声音 | 浏览器策略：先点一下页面任意处 |
| ROBOT 站是空的 | `assets/rigs/robot.rig` 或 `robot_*.png` 缺失——重跑 `python3 tools/showcase_assets.py`（见 docs/showcase/assets.md 的再生成说明） |
| BENCH 一直卡在 Lv12 不出分 | 你的设备太强（无头/极高端），12 档是上限——这本身就是满分 |
| 真机帧率异常低 | 用了 Debug 构建；`make device-run CONFIG=Release` |
