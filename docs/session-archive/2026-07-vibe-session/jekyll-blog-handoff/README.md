# 交接:两篇教程发布到个人博客(maweis1981.github.com)+ 微信公众号

> 本目录是跨会话交接包。原会话对 `maweis1981/maweis1981.github.com` 无写权限,
> 已把准备好的提交(两篇 Jekyll 文章 + 10 张配图,Chirpy front matter +
> `wechat_source_url` 公众号回链)导出为标准 git patch。

## 新会话操作步骤(授权该仓库后)

```bash
git clone <maweis1981.github.com 仓库> blog && cd blog
git config user.email noreply@anthropic.com && git config user.name Claude
git checkout -b claude/publish-vibe-tutorials
git am path/to/0001-vibe-coding-tutorials.patch   # 原样恢复提交(含二进制图片)
git push -u origin claude/publish-vibe-tutorials
# 开 PR → 合并进 master
```

## 合并 master 后自动发生的事(无需额外操作)

1. **博客上线**:Pages 部署(pages-deploy.yml),两篇文章出现在 maweis.com
   - /posts/pony-parade-tutorial/
   - /posts/midnight-gallery-tutorial/
2. **公众号草稿**:wechat-publish.yml 对 `_posts/*.md` 的 push 自动触发,
   在公众号**草稿箱**为每篇生成图文草稿(publish:false),封面取 front matter
   题图,「阅读原文」回链博客 —— 人工在草稿箱审阅后群发即可。

## patch 内容

- `_posts/2026-07-07-pony-parade-tutorial.md`(题图 = 版本演进图)
- `_posts/2026-07-07-midnight-gallery-tutorial.md`(题图 = 立绘管线四阶段图)
- `assets/img/posts/vibe-coding-game-dev/` 10 张配图
- 提交信息完整(含 Co-Authored-By 与会话链接),committer 已按规范设置
