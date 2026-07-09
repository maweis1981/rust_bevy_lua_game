// server.js — minimal reference backend for TikTok Mini Game In-App Purchase.
// No framework, no deps: plain Node (>=18, for global fetch + crypto). Deploy
// anywhere reachable over HTTPS (a small VPS, Fly, Render, Railway, or adapt the
// two handlers to a Vercel / Cloudflare Worker function).
//
// Flow (per the official Mini Games payment docs):
//   client  TTMinis.game.login()  -> auth `code`
//   POST /iap/create-order {login_code, product_id}
//     -> exchange code for a USER access_token   (POST /v2/oauth/token/)
//     -> mint a trade order                       (POST /v2/minis/trade_order/create/)
//     -> return { trade_order_id } to the client, which calls TTMinis.game.pay
//   POST /iap/webhook  (register this URL in the Developer Portal)
//     -> verify TikTok-Signature (HMAC-SHA256 of `${t}.${rawBody}` with client_secret)
//     -> on `minis.trade_order.redeem.success`, grant the product (fulfilment).
//
// Set these env vars (from Developer Portal → Credentials; NEVER ship the secret
// to the browser):
//   TIKTOK_CLIENT_KEY, TIKTOK_CLIENT_SECRET
//   PORT (default 8787)
'use strict';
const http = require('http');
const crypto = require('crypto');

const CLIENT_KEY = process.env.TIKTOK_CLIENT_KEY || '';
const CLIENT_SECRET = process.env.TIKTOK_CLIENT_SECRET || '';
const PORT = Number(process.env.PORT || 8787);

// Your product catalog. `beans` = price in TikTok Beans (set to your chosen tier).
// product_id is any string you choose; it flows through the order + webhook so you
// know what to grant. Keep in sync with the client (timedodge.lua PRO_PRODUCT).
const PRODUCTS = {
  timedodge_pro: { name: 'Time Dodge — Pro Gold Skin', beans: 100, image_url: '' },
};

const OAUTH_URL = 'https://open.tiktokapis.com/v2/oauth/token/';
const ORDER_URL = 'https://open.tiktokapis.com/v2/minis/trade_order/create/';

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
  res.end(JSON.stringify(obj));
}
function readRaw(req) {
  return new Promise((resolve) => { let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => resolve(b)); });
}

// Exchange the login `code` for a USER access_token (+ open_id). Minis omit
// redirect_uri / code_verifier vs standard OAuth.
async function exchangeCode(code) {
  const body = new URLSearchParams({
    client_key: CLIENT_KEY, client_secret: CLIENT_SECRET,
    code, grant_type: 'authorization_code',
  });
  const r = await fetch(OAUTH_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
  });
  return r.json();   // { access_token, open_id, expires_in, ... }
}

// Mint a trade order for `product`, authorized by the user's access_token.
async function createOrder(userAccessToken, product, productId) {
  const orderId = 'ord_' + crypto.randomUUID();
  const r = await fetch(ORDER_URL, {
    method: 'POST',
    headers: { 'Authorization': 'Bearer ' + userAccessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      token_type: 'BEANS',
      token_amount: product.beans,
      order_info: {
        order_id: orderId,
        product_name: product.name,
        product_id: productId,
        order_url: '/profile/order_history/' + productId,
        quantity: 1,
        quantity_unit: 'item',
        image_url: product.image_url || '',
      },
    }),
  });
  const data = await r.json();
  // Response shape varies; trade_order_id may be nested under `data`.
  const tradeOrderId = data.trade_order_id || (data.data && data.data.trade_order_id);
  return { tradeOrderId, orderId, raw: data };
}

// Verify a webhook: HMAC-SHA256 of `${t}.${rawBody}` keyed by client_secret == s.
function verifyWebhook(rawBody, sigHeader) {
  if (!sigHeader) return false;
  const parts = Object.fromEntries(sigHeader.split(',').map((kv) => kv.split('=')));
  if (!parts.t || !parts.s) return false;
  const signed = parts.t + '.' + rawBody;
  const local = crypto.createHmac('sha256', CLIENT_SECRET).update(signed).digest('hex');
  let ok = false;
  try { ok = crypto.timingSafeEqual(Buffer.from(local), Buffer.from(parts.s)); } catch (e) { ok = false; }
  const fresh = Math.abs(Date.now() / 1000 - Number(parts.t)) < 300;   // 5-min replay guard
  return ok && fresh;
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {   // CORS preflight
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  if (req.method === 'POST' && req.url === '/iap/create-order') {
    try {
      const { login_code, product_id } = JSON.parse((await readRaw(req)) || '{}');
      const product = PRODUCTS[product_id];
      if (!product) return json(res, 400, { error: 'unknown_product' });
      const tok = await exchangeCode(login_code);
      if (!tok.access_token) return json(res, 400, { error: 'login_exchange_failed', detail: tok });
      const { tradeOrderId, raw } = await createOrder(tok.access_token, product, product_id);
      if (!tradeOrderId) return json(res, 502, { error: 'order_create_failed', detail: raw });
      return json(res, 200, { trade_order_id: tradeOrderId });
    } catch (e) {
      return json(res, 500, { error: 'server_error', detail: String(e) });
    }
  }

  if (req.method === 'POST' && req.url === '/iap/webhook') {
    const raw = await readRaw(req);
    if (!verifyWebhook(raw, req.headers['tiktok-signature'])) return json(res, 401, { error: 'bad_signature' });
    let evt = {};
    try { evt = JSON.parse(raw); } catch (e) {}
    if (evt.event === 'minis.trade_order.redeem.success') {
      // TODO(fulfilment): mark this order/user as entitled to `evt.order_id`'s product
      // in your datastore. `evt.is_sandbox === true` for DevTool IAP-Mock purchases.
      console.log('[iap] redeem success', { order_id: evt.order_id, trade_order_id: evt.trade_order_id, sandbox: evt.is_sandbox });
    }
    return json(res, 200, { ok: true });
  }

  if (req.url === '/healthz') return json(res, 200, { ok: true });
  return json(res, 404, { error: 'not_found' });
});

server.listen(PORT, () => console.log('IAP backend listening on :' + PORT));
