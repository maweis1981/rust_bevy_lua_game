# Engine Showcase · 场景应用

Showcase 的 9 个站不只是演示——每个站都是一类真实需求的最小原型。本文按"你想做什么"索引到"抄哪个站的代码"。

## 1. 休闲小游戏（主打场景）

**抄**：整个 showcase.lua 的结构就是标准游戏包模板（PACK_SPEC 契约：enter/update/tap/leave + DEBUG）。
仓库里已有 12 个上线小游戏用同一套路：Pong 变体、打砖块、贪吃蛇、2048、消除、roguelike、推理 VN……
- 存档站 → 最高分/解锁进度（`save`/`load` 三端同 API）
- 粒子站 → 吃分/爆炸反馈（`emit` 一行）
- JUICE 站 → 打击感三件套（shake+zoom+haptic 各一行）

## 2. 双人同屏 / 本地对战

**抄**：TOUCH 站。`game.touches()` 返回所有手指的世界坐标 + 稳定 id——左右半屏各驱动一个挡板/角色即是双人 Pong；id 稳定性保证手指交叉时不串。桌面开发时鼠标合成 id=0 单指，不接触屏也能调。

## 3. 关卡类 / 地图类玩法（塔防、农场、地牢）

**抄**：TILES 站。`tilemap` + `set_tile` 的格坐标与关卡 JSON 行序一致，**agent 一句话生成的网格数据可直接喂**；配合 CAMERA 站的跟随镜头即可做大于屏幕的世界（示例：仓库的 roguelike 与 world 探索包）。刷全图的成本见 TILES 站 BENCH——先跑分再定地图尺寸。

## 4. 角色扮演 / 剧情演出

**抄**：ROBOT 站 + MIXER 站。
- cutout 骨骼（`spawn_rig`）适合立绘级角色动画：待机呼吸、挥手、行走；`set_bone` 做程序化注视/指向。换角色 = 换部件贴图 + 改 rig JSON，无引擎改动。
- 人声通道（`play_voice`）自动打断上一句，天生适合对白（实例：Midnight Gallery 审讯 VN，四角色各自 TTS 音色）。

## 5. 教学 / 引擎课程

Showcase 是现成教材：每站 60-100 行、单文件、可热重载（桌面 `make run` 下改 Lua 秒级生效）。
建议课程动线：TOUCH（输入）→ ATLAS（渲染）→ TILES（数据驱动）→ ROBOT（动画）→ BENCH 挂具（性能方法论）。
无头测试套件（`tools/test_pong.lua`）演示"游戏逻辑如何被断言"——每站的 bench 在 CI 里被跑到满档。

## 6. 设备/构建性能评估

BENCH 分数 = "该能力守住 45fps 的最大负载档"。用法：
- **横向比设备**：同一构建在 iPhone 真机 / 模拟器 / 浏览器各跑一轮，VAULT 站直接读九项对比。
- **纵向比构建**：Debug vs Release、wasm-opt 开关前后，用分数差量化。
- **回归守门**：引擎改动后跑分骤降 = 性能回归的第一信号（比肉眼看帧率客观）。

## 7. AIGC 素材管线验证场

新风格试装：用 Floniks 生成一套新的金币/tileset/机器人部件 → 跑 `tools/showcase_assets.py` → 打开 showcase 立即看到新素材在动画、tilemap、骨骼三种用法下的实际效果。**Showcase 是素材管线的验收台**——素材问题（枢轴偏、边缘残色、帧不齐）在这里最先暴露。

## 8. 发行前的"电梯演示"

给发行商/投资人看引擎，不用讲 PPT：浏览器打开链接 → 玩 30 秒 → 按一次 BENCH。
"每项能力当场跑分"回答了 demo 场合最常被质疑的问题：*这是实时的吗？在我手机上也这样吗？*——把手机递给他就行。
