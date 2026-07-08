// engine/game.js — SUBPACKAGE entry (root of the `engine` subpackage declared
// in ../game.json). It MUST be named game.js: when a WeChat/Douyin mini-game
// subpackage `root` is a directory, the platform uses that directory's game.js
// as the entry file. Loaded on demand by ../boot/launch.js after the subpackage
// download completes; it may `require` anything under ./shared (the engine copy
// that prepare.sh places here). Kept thin: just start the shared game loop.
'use strict';

var startGame = require('./shared/main.js').startGame;

module.exports = {
  start: function (platform) { return startGame(platform); },
};
