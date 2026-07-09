# Time Dodge — IAP backend (reference)

TikTok Mini Game In-App Purchase is **server-mediated**: the client cannot list
products or mint orders. This tiny Node service does the two server jobs — mint a
trade order, and receive the fulfilment webhook. Deploy it, point the game at it,
and a US build (which can't use ads) has a working, reviewable revenue feature.

`server.js` has **no dependencies** — plain Node ≥ 18 (global `fetch` + `crypto`).

## What it does

| Endpoint | Who calls it | Job |
|---|---|---|
| `POST /iap/create-order` | the game (engine.js `iap_buy`) | exchange the login `code` → user `access_token` (`POST /v2/oauth/token/`), then mint a Beans order (`POST /v2/minis/trade_order/create/`), return `{ trade_order_id }` |
| `POST /iap/webhook` | TikTok | verify `TikTok-Signature` (HMAC-SHA256 of `` `${t}.${rawBody}` `` with your `client_secret`), and on `minis.trade_order.redeem.success` **grant the product** |
| `GET /healthz` | you | liveness |

Verified locally: routing, CORS preflight, and the webhook signature check
(valid → 200, tampered → 401). The two outbound TikTok calls need real
credentials + network, so test those with the DevTool **IAP Mock** (below).

## Run / deploy

```bash
export TIKTOK_CLIENT_KEY=...        # Developer Portal → Credentials
export TIKTOK_CLIENT_SECRET=...     # keep server-side ONLY — never in the game bundle
export PORT=8787
node server.js
```

Host it anywhere reachable over HTTPS (small VPS, Fly, Render, Railway…), or port
the two handlers to a Vercel / Cloudflare Worker function. Then:

1. In the game's `index.html`, set the backend base URL:
   ```html
   <script>window.__IAP_ENDPOINT = "https://your-backend.example.com/iap";</script>
   ```
   (Already stubbed in `timedodge/index-us.html`.)
2. Add your backend host to the mini-game's **trusted request domains** in the
   Developer Portal (otherwise the webview's `fetch` is blocked).
3. Register `https://your-backend.example.com/iap/webhook` as the webhook URL for
   `minis.trade_order.redeem.success`.

## Product

Edit `PRODUCTS` in `server.js` — `beans` is the price (a TikTok Beans tier),
`product_id` must match the client (`timedodge.lua` `PRO_PRODUCT = "timedodge_pro"`).
Grant entitlement in the webhook handler (`TODO(fulfilment)`); `is_sandbox:true`
marks DevTool-mock purchases.

## Portal prerequisites (before real payments work)

- Business verification.
- Monetization page → enable **In-App Purchases**, accept the agreement.
- Payout Setup (tax + bank). (US market may add EIS / USDS TPRM review.)

## Testing for review

Turn on **"Enable IAP Mock"** in the TikTok DevTool — `pay()` completes the sheet
without a real charge, and the webhook fires with `is_sandbox:true`. That lets a
reviewer exercise the full purchase flow (the "successfully callable revenue
feature") without money changing hands.
