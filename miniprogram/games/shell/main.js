// main.js — collection shell entry. Wires the platform adapter to the ad meta
// layer, the game registry, and the router. Called by index.html (browser) /
// any wrapper with a platform object shaped like the other games'.
'use strict';
var createAdMeta = require('./admeta.js').createAdMeta;
var buildRegistry = require('./registry.js').buildRegistry;
var createRouter = require('./router.js').createRouter;

function startShell(platform) {
  var ad = createAdMeta(platform);
  var registry = buildRegistry();
  return createRouter(platform, registry, ad);
}

module.exports = { startShell: startShell };
