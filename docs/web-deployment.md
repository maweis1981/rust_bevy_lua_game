# Web 部署与单游戏架构

> 记录本项目 Web 端的**部署方式**与**发布形态**的既定设计（2026-07-07 确认）。
> 这份文档是权威口径：设计新游戏或改 Web 构建前先读这里。

## 一、部署：GitHub Pages（自动）

Web 版通过 **GitHub Pages** 部署，全自动，无人工环节：

- 触发：push 到 `main` 分支（或手动 `workflow_dispatch`）。
- 流水线：`.github/workflows/deploy-web.yml` → `bash web/build.sh` 构建 → `build/web/` 上传为 Pages artifact → `actions/deploy-pages` 发布。
- 一次性配置：仓库 Settings → Pages → Source 选 "GitHub Actions"。
- 并发：`concurrency: pages`，同时只跑一个部署，不取消进行中的。

**含义**：功能分支/代理分支的 PR **不会**部署——只有合入 `main` 才触发 Pages。要拿到公开可玩链接 = 合并到 `main`。

## 二、发布形态：单游戏单 wasm（不再是游戏合集）

**核心决策：不再需要"游戏合集"（菜单）作为发布形态。** 每个游戏作为**独立的单游戏 bundle** 发布，
避免一个页面把所有游戏的资产全打包进去、体积过大。

### 为什么

- wasm 引擎本身就有数十 MB。若再把全部游戏的纹理/音频/脚本堆进同一个包，首屏下载会大到伤留存
  （完成度门禁 A2：进入游戏 ≤2s、门禁玩家旅程"前 10 分钟定生死"）。
- 玩家通常从一条链接进**一个**游戏。让他只下载那一个游戏所需的资产，而不是整个合集。

### 机制（引擎共享、游戏即数据）

wasm 是**共享引擎**（Bevy + Lua VM），游戏是 **Lua 资产**。所以单游戏 bundle = 共享 `make web` 产物 +
一行 `AUTOBOOT = "<key>"`，让场景路由**直接启动该游戏**，菜单永不出现，"返回"也只重进该游戏。
**没有 per-game Rust 编译**——引擎二进制对所有游戏相同，游戏差异只在 Lua + 该游戏的贴图/音频。

两条落地路径：

| 路径 | 怎么用 | 产物 |
|---|---|---|
| **在线直链**（`web/game.html`） | 访问 `/play/?game=<key>` | Service Worker 拦截 `main.lua`，运行时注入 `AUTOBOOT`。同一份 Pages 部署，一条链接一个游戏 |
| **离线单游戏包**（`tools/export_web_games.sh`） | `make web` 后 `make web-games` | `build/web-games/<key>/` + `<key>.zip`，硬链共享 wasm（15 个包几乎不占额外磁盘），各自可独立托管 |

### 单游戏包导出（`make web-games`）

```bash
make web         # 先产共享 bundle build/web/
make web-games   # 每个游戏产 build/web-games/<key>/ (+ .zip)
```

导出列表在 `tools/export_web_games.sh` 的 `GAMES` 默认数组——**新增游戏必须把 key 加进去**，
否则不会有它的单游戏包。当前包含：`grow breakout snake roguelike game2048 shooter world craft
match3 umami catch ponies gallery showcase timedodge forge fireflies`。

## 三、菜单/合集的现状

场景路由（`assets/scripts/main.lua`）与菜单**代码仍在**——它是开发期在一个引擎里切换调试所有游戏的便利，
也是 `AUTOBOOT` 机制的宿主（AUTOBOOT 就是让路由跳过菜单直接进某个游戏）。但**合集不再是发布形态**：
线上每条链接、每个离线包都是单游戏。设计新功能时不要把菜单当作玩家入口来规划。

## 四、GitHub Pages 站点结构

Pages 根是**引擎官网**（首页/博客/文档，静态页在 `web/site/`；博客 markdown 来自 `docs/blog/`，客户端渲染），
可玩游戏在 `/play/`（`web/game.html` + wasm bundle）。`web/build.sh` 把这些组装进 `build/web/`。
加博客文章 = 把 `.md` 放进 `docs/blog/` 并在 `web/site/blog/posts.js` 注册（见 `docs/blog/README.md`）。

## 五、一句话

**Web 走 GitHub Pages 自动部署（push main 触发）；发布形态是单游戏单包（`?game=` 直链 / `make web-games`
离线包），引擎 wasm 共享、游戏即 Lua 资产、AUTOBOOT 跳过菜单——合集已不作为发布形态。**
