# tesla-connector

A free replacement for a paid Tessie subscription: connect Home Assistant (HA) directly
to your Tesla using Home Assistant's **official, free `Tesla Fleet` integration**.

It reads charge status, charge limit, navigation destination + ETA, and tire pressure,
and controls HVAC/preconditioning — everything you were paying Tessie for.

## How this works (and what this repo is)

HA's `Tesla Fleet` integration talks to Tesla's cloud **Fleet API** directly and signs
vehicle commands itself, so **no proxy and no service on this server are required**. HA
communicates with Tesla; this Ubuntu box plays no runtime role.

The only hard requirement Tesla imposes is that your app's **public key** be hosted at a
public HTTPS URL. This repo is a ready-to-push Git repo that deploys that one file to
**GitHub Pages** on `git push` — no inbound ports on your router, no server to maintain.
It holds:

- `docs/` — the published site (GitHub Pages serves from this folder). Contains the
  public key under `.well-known/`, plus `.nojekyll` and `CNAME` (see "Deploy" below).
- `scripts/verify.sh` — checks the key is correctly hosted before you pair the car.
- This runbook.

> **Why GitHub Pages and not Cloudflare Pages?** Tesla's path lives under `.well-known/`
> (a dotfile directory). GitHub Pages serves it once Jekyll is disabled (the included
> `docs/.nojekyll` does that). Cloudflare Pages / Wrangler silently drop dotfiles, so a
> static `.well-known` deploy there is unreliable — you'd need a Cloudflare Worker
> instead. GitHub Pages also works with your existing DNS via a simple CNAME record.

> The matching **private** key is generated and kept by Home Assistant at
> `config/tesla_fleet.key`. Keep it secret. Never host it.

## Setup runbook

Do the steps in this order — HA generates the public key partway through, so you register
the app first, start HA setup to get the key, host it, then finish and pair.

### 1. Register a Tesla developer app
At <https://developer.tesla.com/request>:
- OAuth Grant Type: **Authorization Code and Machine-to-Machine**
- Allowed Origin URL: `https://<your-subdomain>` (e.g. `https://tesla.example.com`)
- Allowed Redirect URI: `https://my.home-assistant.io/redirect/oauth`
  (enable the *My Home Assistant* integration in HA first; otherwise use
  `<HA_URL>/auth/external/callback`)
- Scopes: **Vehicle Information**, **Vehicle Location**, **Vehicle Commands**
- Save the **Client ID** and **Client Secret** (View Details → Credentials & APIs)

### 2. Start the HA integration to get the public key
HA → Settings → Devices & services → Add Integration → **Tesla Fleet**. Enter the Client
ID and Secret, and proceed until HA **displays your public key**. Copy it.

### 3. Host the public key (deploy via GitHub Pages)
Two edits, then push. See the **Deploy** section below for full detail.

1. Paste the public key copied from HA into:
   ```
   docs/.well-known/appspecific/com.tesla.3p.public-key.pem
   ```
   (replace the placeholder block).
2. Put your real subdomain in `docs/CNAME` (replace `tesla.example.com`).
3. Commit and push to a GitHub repo with Pages enabled (one-time setup below):
   ```bash
   git add -A && git commit -m "Set Tesla public key + domain" && git push
   ```

Then verify hosting before pairing:
```bash
./scripts/verify.sh <your-subdomain>     # e.g. ./scripts/verify.sh tesla.example.com
```
You want `PASS: HTTP 200 and a valid ... PEM public key`.

### 4. Finish HA configuration
Back in the HA flow: enter the domain hosting the key, log in to Tesla, **Select All**
scopes → **Allow**, and link the account.

### 5. Pair the virtual key with the car
On your phone (Safari on iPhone) open:
```
https://tesla.com/_ak/<your-subdomain>
```
or scan the QR HA shows, and approve adding the key in the Tesla app. This lets the car
trust HA's signed commands.

### 6. Enable the entities you want (some are off by default)
On the Tesla device page in HA, enable:
- the four **tire pressure** sensors
- **active route arrival time / distance to arrival** (destination + ETA)

Charge status, charge limit, and climate/HVAC controls are on by default.

### 7. Cut over and cancel Tessie
Point your existing automations/dashboards at the new `Tesla Fleet` entities (entity IDs
differ — map 1:1), verify everything, then cancel the Tessie subscription.

## Deploy (one-time GitHub Pages setup)

This repo is already a Git repo with an initial commit. To publish the key file:

1. Create an **empty** GitHub repo (e.g. `tesla-connector`). It can be public or private —
   GitHub Pages serves the site publicly either way; the only thing exposed is your
   *public* key, which is meant to be public.
2. Add the remote and push:
   ```bash
   git remote add origin git@github.com:<you>/tesla-connector.git
   git push -u origin main
   ```
3. In the repo: **Settings → Pages → Build and deployment → Source: Deploy from a
   branch**, Branch: **`main`** / folder **`/docs`**. Save.
4. Still on the Pages settings, set **Custom domain** to your subdomain (e.g.
   `tesla.example.com`) — this must match `docs/CNAME` and the Allowed Origin from step 1
   of the runbook. Leave "Enforce HTTPS" on (it enables once the cert provisions).
5. At your DNS provider, add a **CNAME** record: `tesla` → `<you>.github.io`.
   (GitHub Pages works with any DNS host — no need to move your domain to anyone.)
6. Wait for DNS + HTTPS to provision (minutes to ~an hour), then run
   `./scripts/verify.sh tesla.example.com`.

After this, every change is one command: edit the file, `git push`, done.

**Already handled for you in this repo:**
- `docs/.nojekyll` — disables Jekyll so the `.well-known` dotfile directory is served.
- `docs/CNAME` — placeholder custom domain (edit to your real subdomain).
- `.gitignore` — blocks accidental commits of any `*.key` / private `*.pem`.

**Prefer Cloudflare?** Don't use Cloudflare Pages for this (it drops dotfiles). Instead
deploy a tiny Cloudflare Worker that returns the PEM for the `.well-known` path. Ask and
I'll scaffold it; GitHub Pages above is the lower-maintenance default.

## Cost, limits, battery

- **Free** within Tesla's ~$10/month API credit for a single car polled every ~10 min.
- Free tier caps commands at ~50/day — fine for occasional preconditioning.
- The integration only polls while the car is awake and never force-wakes it, so it
  won't drain the 12V battery (same idea as Tessie).

## Verifying it works end to end
1. `scripts/verify.sh` passes.
2. HA shows live battery %, charge limit, TPMS, and (when a route is active) destination
   + ETA.
3. Trigger climate/preconditioning from HA and confirm the car responds (proves command
   signing + pairing).
4. Remove Tessie with no loss of function, then cancel it.

## Notes
- The public key never changes once generated → hosting is set-and-forget. If you ever
  regenerate HA's private key, re-host the new public key and re-pair.
- Pre-2021 Model S/X can't pair virtual keys (not relevant to a Model 3).
