// Shared client-side markdown renderer for blog posts and docs pages.
//
// The page declares where its markdown lives via data attributes on <body>:
//   data-md-dir      — directory (relative to the page) holding the .md files
//   data-github-md   — GitHub blob URL prefix for repo-relative .md links that
//                      aren't published on this site (e.g. ../roadmap.md)
// The file is picked by the ?p=<name> query parameter (sanitized: no slashes),
// so posts/docs never need per-file HTML.
(function () {
  var body = document.body;
  var mdDir = body.dataset.mdDir || 'posts';
  var githubMd = body.dataset.githubMd || '';
  var target = document.getElementById('md-target');

  var name = new URLSearchParams(location.search).get('p') || '';
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
    target.innerHTML = '<p class="loading">未指定文章。</p>';
    return;
  }

  fetch(mdDir + '/' + name + '.md')
    .then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    })
    .then(function (md) {
      target.innerHTML = marked.parse(md, { mangle: false, headerIds: false });

      // Rewrite markdown-style links so navigation stays inside the site:
      //  - same-directory .md → this renderer page (?p=<name>)
      //  - repo-relative ../*.md → GitHub blob URL (docs not published here)
      target.querySelectorAll('a[href]').forEach(function (a) {
        var href = a.getAttribute('href');
        if (!/\.md($|#)/.test(href) || /^https?:/.test(href)) return;
        var m = href.match(/^(?:\.\/)?([A-Za-z0-9._-]+)\.md(#.*)?$/);
        if (m) {
          a.setAttribute('href', location.pathname + '?p=' + m[1] + (m[2] || ''));
        } else if (githubMd) {
          a.setAttribute('href', githubMd + href.replace(/^(\.\.\/)+/, ''));
        }
      });

      var h1 = target.querySelector('h1');
      if (h1) document.title = h1.textContent + ' · hollowlullaby';
    })
    .catch(function (e) {
      target.innerHTML = '<p class="loading">加载失败（' + e.message + '）。文章可能不存在。</p>';
    });
})();
