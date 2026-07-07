// wechat/game.js — WeChat mini-game MAIN-PACKAGE entry (declared by game.json).
// Thin launcher: build the wx adapter, then hand off to the shared boot/launch,
// which shows a loading screen and downloads the `engine` subpackage (see
// ../boot/launch.js and game.json's "subpackages"). The engine itself lives in
// engine/ and is required only after the subpackage is in.
'use strict';

var platform = require('./adapter.js');
var launch = require('./boot/launch.js').launch;

launch(platform, function (p) {
  require('./engine/index.js').start(p);
});
