# Showcase 资产清单与再生成

全部素材来自 Floniks 管线，可整体重放（换风格 = 换 prompt 重跑）。

## 清单

| 文件 | 来源 | Floniks 任务 id |
|---|---|---|
| `assets/audio/showcase.wav` | Lyria 2 textToMusic（32.8s 循环，经 ffmpeg 转 44.1k/s16） | `0L35WDBMEv8bUa7pZKS3` |
| `assets/textures/coin_sheet.png` | Seedream 4 文生图（8 帧挑 6，色键+切格+重组） | `WQMR57bCpO1y6K7yx4cY` |
| `assets/textures/tileset.png` | Seedream 4 文生图（4 格，内缩裁切去圆角） | `lHj7BZl2he2NSVZckOXu` |
| `assets/textures/robot_*.png`（6 件） | Seedream 4 文生图（躯干取胸屏件，左臂/左腿镜像） | `EJsSsi9dci8K1oFjyYaK` |
| `assets/rigs/robot.rig` | 手写 JSON（部件层级 + idle/wave/walk 剪辑） | —（agent 直接生成） |

## 再生成

1. 在 Floniks 重跑上表任务（或用新 prompt 生成同构图：帧/部件按等宽格子横排、magenta 纯色底、tileset 白底满格）。
2. 原图放入任一目录，命名 `coin_strip.png` / `robot_strip.png` / `tileset_strip.png`。
3. `python3 tools/showcase_assets.py <该目录>` —— 输出直接落 `assets/textures/`。
4. BGM：Lyria 2 出 wav 后 `ffmpeg -i in.wav -ar 44100 -ac 2 -c:a pcm_s16le assets/audio/showcase.wav`。

管线的判定常量（色键阈值、内缩比例、帧序）都在 `tools/showcase_assets.py` 顶部，风格大改时先调它们。
