// engine/index.js — SUBPACKAGE entry (root of the `engine` subpackage declared
// in ../game.json). Loaded on demand by ../boot/launch.js after the subpackage
// download completes; it may `require` anything under ./shared (the engine copy
// that prepare.sh places here). Kept thin: just start the shared game loop.
'use strict';

var startGame = require('./shared/main.js').startGame;

module.exports = {
  start: function (platform) { return startGame(platform); },
};
