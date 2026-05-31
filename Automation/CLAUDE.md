# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Automation workspace for [QuickSay](https://quicksay.app), a Windows speech-to-text desktop app. Manages the **beta pipeline**: form submissions on Cloudflare Pages → N8N workflows → Notion databases + email notifications. Also contains Reddit strategy docs and social media automation config.

**Scope:** N8N workflow management, Notion integration, Cloudflare Pages deployment, email automation. The main app code lives at `C:\QuickSay` (separate CLAUDE.md). The website lives at `C:\QuickSay\Website` (Astro + Tailwind, static `dist/` deployed to Cloudflare Pages).

## Key Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| N8N (remote) | `https://n8n.beekz.uk/api/v1` | Workflow automation (Contabo VPS 212.28.189.181) |
| Notion API | `https://api.notion.com/v1` (version `2022-06-28`) | Feedback + signup databases |
| Cloudflare Pages | Project `quicksay-app` at `quicksay.app` | Website + serverless functions |
| Anthropic API | `https://api.anthropic.com/v1/messages` | AI-drafted Reddit responses (Claude Sonnet 4.6) |
| Purelymail SMTP | `smtp.purelymail.com:587` (STARTTLS) | Transactional email from `beta@quicksay.app` |

**Important:** ALL N8N work targets the **remote** instance at `n8n.beekz.uk`. Local N8N (`localn8n.beekz.uk` / Docker Desktop) is retired — do not modify it.

## Key IDs

### N8N Workflows
| Workflow | ID | Webhook Path |
|----------|-----|-------------|
| Beta Feedback Handler | `RganQ5YYnTXpS7H9` | `/webhook/beta-feedback` |
| Beta Testimonial Handler | `RdkQGJM2qC52qP7e` | `/webhook/beta-testimonial` |
| Beta Email Sequence (SMTP) | `EC4Fzts88a2dSB7q` | `/webhook/beta-signup` |
| Beta Follow-Up Emails | `EA49TPho6MH1kWN5` | (scheduled, runs every 4 hours) |
| Reddit Keyword Monitor | `UjSP4n46JYAzGlb5` | (scheduled, 4 staggered triggers daily) |
| Social Media Auto-Poster | `mGeOQKr0JmMBxiyM` | (scheduled: Twitter 9AM MST, LinkedIn 10AM MST) |

### Notion Databases
- **Beta Feedback DB:** `30a762ba3bc180beae59ec7eac37d2d1`
- **Beta Signups DB:** `571a51b1a860406b99d68ded2be2226c`
- **Social Media Calendar DB:** `30c762ba3bc181b9b26ff20bf62ff4c5`
- **Reddit Engagement Tracking DB:** `30c762ba3bc1811a8d81d3fb853ba583`

### Other
- **SMTP credential (N8N):** `b5Tw1HSnP7f1QovZ` ("QuickSay - beta@ SMTP")
- **N8N API key:** stored in `.mcp.json` under `n8n-mcp.env.N8N_API_KEY`

## Architecture

### Cloudflare Pages Functions → N8N Webhooks → Notion

Serverless functions live at `C:\QuickSay\Website\functions\api/`:

| Function | Form Page | N8N Webhook | Honeypot Field |
|----------|-----------|-------------|----------------|
| `beta-signup.js` | `/beta` | `/webhook/beta-signup` | `website` |
| `beta-feedback.js` | `/beta/feedback` | `/webhook/beta-feedback` | `company` |
| `beta-testimonial.js` | `/beta/testimonial` | `/webhook/beta-testimonial` | `company` |
| `reddit-search.js` | (internal API) | N/A — proxies Reddit JSON search for keyword monitor | N/A |
| `reddit-track.js` | (email links) | N/A — GET endpoint, writes to Notion Reddit Engagement Tracking DB, 302 redirects | N/A |

All functions follow the same pattern: validate fields → honeypot check (silently accept bots) → email regex → enrich with `submittedAt` + `userAgent` → POST to N8N → return `{success: true}` regardless of webhook outcome.

### Beta Email Sequence (EC4Fzts88a2dSB7q)

Triggered by `beta-signup.js` on form submit. Responds immediately, then fans out in parallel:

```
Beta Signup Webhook → Respond OK (immediate, parallel:)
                    → Extract Signup Data → Save to Notion → Send Welcome Email → Update Stage to 1
```

The Save to Notion Code node maps the `useCase` form value via `mapUseCase()` to one of 6 select options. The Welcome Email is SMTP via `b5Tw1HSnP7f1QovZ`. After stage is set to 1, the Follow-Up Emails workflow (`EA49TPho6MH1kWN5`) picks it up on its next 4-hour cycle.

**Update script:** `update-email-sequence.js` — run `node update-email-sequence.js` to deploy changes.

### Feedback Pipeline (RganQ5YYnTXpS7H9)

```
Webhook → Respond OK (immediate)
       → Extract Feedback Data (Set node, maps $json.body.*)
           → Auto-Categorize (Groq LLM tags)
               → Save to Notion (Code node, rich page with ratings)
               → Send Confirmation Email (to user)
               → NPS Router (Switch: detractor → URGENT notify / passive+promoter → notify)
```

### Testimonial Pipeline (RdkQGJM2qC52qP7e)

```
Webhook → Respond OK (immediate)
       → Extract Testimonial Data (Set node, 5 fields)
           → Save to Notion (tagged "testimonial-form", Testimonial Candidate: true)
           → Notify Adrian (email with testimonial quote)
           → Send Thank You Email (to user)
```

The standalone testimonial page (`/beta/testimonial`) is a lightweight alternative to the full feedback form — just name, email, testimonial text, and consent radio. Linked from the Day 14 follow-up email.

### Follow-Up Emails (EA49TPho6MH1kWN5)

Scheduled workflow (every 4 hours). Nodes: Prepare Due Emails → Build Email HTML (Code node with day3/day7/day14 branches) → Send Follow-Up Email → Update Notion Stage. The Day 14 email CTA links to `/beta/testimonial`.

### Reddit Keyword Monitor (UjSP4n46JYAzGlb5)

Searches 28 curated subreddits for voice typing, speech-to-text, dictation, RSI, and competitor posts, then emails Adrian a digest with AI-drafted response suggestions.

**Cross-run dedup (v6):** The "Fetch and Process" node queries the Reddit Engagement Tracking DB (`30c762ba3bc1811a8d81d3fb853ba583`) at the start of each run to build a set of all `Permalink` URLs from the last 7 days. Posts matching a seen permalink are filtered out before scoring/AI calls. After selecting the top 15 candidates, each post is written back to the DB with `Action = "recommended"`. This means threads already recommended, posted, or skipped in previous runs are never recommended again. Fail-open on Notion errors (dedup skipped, email still sends). DB growth: ~32 entries/day, pruned by the 7-day query window.

**4 staggered triggers** (time-window dedup — each trigger only looks at posts since the previous trigger):
- Weekday morning: 6 AM MST (Mon-Fri, cron `0 13 * * 1-5`)
- Weekend morning: 8 AM MST (Sat-Sun, cron `0 15 * * 0,6`)
- Midday: 11 AM MST (daily, cron `0 18 * * *`)
- Evening: 5 PM MST (daily, cron `0 0 * * *`)

```
Schedule Triggers (4x) → Fetch and Process (Code: 5 keyword groups × 28 subs, dedup, improved scoring, top 15)
    → AI Relevance Filter (Claude Haiku: batch 0-5 rating, drop <2, cap at 8)
        → Generate Responses (Claude Sonnet 4.6, prompt caching, phase-aware drafts)
            → Format Email (absolute tier scores, relevance badges, copy-ready drafts)
                → Send to Adrian (email to a.beeksma21@gmail.com)
```

**AI relevance pre-filter (v5):** Uses Claude Haiku (`claude-haiku-4-5-20251001`) with temperature 0 to batch-classify all candidate posts on a 0-5 relevance scale. Posts scoring below 2 are dropped. Fail-open on API or parse errors (all posts pass through). Cost: ~$0.001/call, ~$0.12/month. The `aiRelevanceScore` multiplies into the opportunity score and displays as a purple badge in the email.

**AI response drafting:** Uses Claude Sonnet 4.6 with phase-aware rules (Phase 1: karma building only, no QuickSay mentions; Phase 2: concept seeding; Phase 3: strategic mentions with disclosure). System prompt cached via `cache_control` for efficiency.

**Scoring formula (v5):** Engagement uses `log2(score+1)` (diminishing returns), comments use a bell curve (0=0.5x, 3-15=1.0x sweet spot, 30+=0.3x), recency uses exponential decay `e^(-age/window)`. Email displays absolute tier thresholds (not relative min-max normalization).

**Update script:** `update-reddit-monitor.js` — contains the full workflow definition. Running `node update-reddit-monitor.js` deactivates, PUTs the updated definition, and reactivates.

**Subreddit whitelist (28):** speechrecognition, transcription, accessibility, RSI, CarpalTunnel, ChronicPain, ErgoMechKeyboards, Ergonomics, productivity, LifeProTips, RemoteWork, writing, selfpublish, Screenwriting, freelanceWriters, ADHD, adhdwomen, Dyslexia, neurodiversity, Windows11, windows, Windows10, software, programming, ExperiencedDevs, AutoHotkey, SideProject, blind

**Niche sub feed (v5):** Reduced to `speechrecognition+CarpalTunnel+RSI+blind` (removed `transcription` and `accessibility` which generated false positives). Now requires at least 1 keyword match (was 0).

**Key details:**
- Reddit blocks datacenter IPs, so requests route through `quicksay.app/api/reddit-search` (Cloudflare Pages function) which proxies to Reddit's JSON search API.
- Proxy accepts optional `subs` parameter (e.g., `?subs=RSI+ADHD+productivity`) to restrict search to specific subreddits via Reddit's `/r/sub1+sub2/search.json?restrict_sr=on` URL format. Without `subs`, falls back to global search.
- Proxy is authenticated via `X-Monitor-Key: qs-reddit-monitor-2026` header.
- If 0 results in 24h window, no email is sent (empty Code output stops the pipeline).
- N8N Code node sandbox does **not** support `fetch`, `require()`, or `import`. Use `this.helpers.httpRequest()` for all HTTP calls.
- 15 additional negative keywords added in v5: deed transfer, manuscript, asylum record, genealogy, wheelchair, building audit, closed caption, subtitle, graduation, court record, historical document, immigration record, property deed, census record, sign language.
- 4 broad keywords removed in v5: ergonomic, assistive tech, keyboard alternative, voice assistant. 8 specific keywords added: voice to text app, dictation for windows, hands free typing, speech to text software, voice typing software, dictation tool, speak and type, typing with voice.

### Social Media Auto-Poster (mGeOQKr0JmMBxiyM)

Automated daily posting to Twitter and LinkedIn from a Notion content calendar. Two schedule triggers fire independently — Twitter at 9 AM MST (cron `0 16 * * *`), LinkedIn at 10 AM MST (cron `0 17 * * *`).

```
Twitter Schedule (9AM MST) → Set Platform → Query Notion → Post via Rube MCP → Update Notion → Format Email → Send to Adrian
LinkedIn Schedule (10AM MST) ↗
```

**How posting works:** N8N Code nodes call the Rube MCP HTTP endpoint (`rube.app/mcp`) using JSON-RPC 2.0 with SSE responses. The `RUBE_REMOTE_WORKBENCH` tool executes Python code that calls `run_composio_tool()` for the actual Twitter/LinkedIn API calls. Post text is base64-encoded to avoid escaping issues in the Python bridge.

**Key IDs:**
- Composio Twitter connected_account: `ca_zmFzeri40WXI`
- Composio LinkedIn connected_account: `ca_nG6Z3tCtMXoR`
- LinkedIn author URN: `urn:li:person:Rqf5guezWz`
- Rube bearer token: in `.mcp.json` under `rube.headers.x-api-key`

**Notion query logic:** Filters by `Date = today (UTC)` AND `Status = "Not Posted"` AND `Platform = <trigger platform>`. Returns empty array (skipping all downstream nodes) on days with no scheduled posts — no email sent.

**LinkedIn link handling (v2 — auto-comment):** When a Notion post has a `Link URL` property set, the workflow automatically: (1) strips that URL from the post body before publishing, (2) extracts the post URN from LinkedIn's response, (3) posts the link as a first comment via `LINKEDIN_CREATE_COMMENT_ON_POST`. If LinkedIn returns a threadUrn mismatch error, the Python code extracts the correct URN from the error message and retries. The confirmation email shows a green callout on success or red callout with manual fallback instructions on failure. Posts without `Link URL` are unaffected.

**Creation/update script:** `create-social-poster-workflow.js` — contains the full workflow definition. Running `node create-social-poster-workflow.js` deactivates the workflow, PUTs the updated definition, and reactivates it.

## Commands

### Deploy website to Cloudflare Pages
```bash
cd /c/QuickSay/Website
npx wrangler pages deploy dist/ --project-name=quicksay-app --branch=main --commit-dirty=true
```
The `--branch=main` flag is required for production deploys. Without it, deploys go to branch preview URLs (not `quicksay.app`).

### Query N8N API
```bash
# List all workflows
curl -s -H "X-N8N-API-KEY: <key>" "https://n8n.beekz.uk/api/v1/workflows"

# Fetch specific workflow
curl -s -H "X-N8N-API-KEY: <key>" "https://n8n.beekz.uk/api/v1/workflows/<ID>"

# Check recent executions
curl -s -H "X-N8N-API-KEY: <key>" "https://n8n.beekz.uk/api/v1/executions?workflowId=<ID>&limit=5"

# Activate a workflow (separate endpoint, POST not PUT)
curl -s -X POST -H "X-N8N-API-KEY: <key>" "https://n8n.beekz.uk/api/v1/workflows/<ID>/activate"

# Deactivate
curl -s -X POST -H "X-N8N-API-KEY: <key>" "https://n8n.beekz.uk/api/v1/workflows/<ID>/deactivate"
```

### Update N8N workflows via scripts
```bash
# Update Social Media Auto-Poster (deactivate → PUT → activate)
node create-social-poster-workflow.js

# Update Reddit Keyword Monitor (deactivate → PUT → activate)
node update-reddit-monitor.js

# Update Beta Email Sequence (deactivate → PUT → activate)
node update-email-sequence.js
```
All scripts embed credentials and the full workflow definition. They follow the same pattern: deactivate → PUT (only `name`, `nodes`, `connections`, `settings`) → reactivate.

### Test webhooks end-to-end
```bash
# Full feedback flow: 3 NPS scenarios (promoter/passive/detractor) → N8N → Notion + emails
bash test-feedback-flow.sh

# Test testimonial only
curl -s -X POST "https://quicksay.app/api/beta-testimonial" \
  -H "Content-Type: application/json" \
  -H "Origin: https://quicksay.app" \
  -d '{"name":"Test","email":"test@example.com","testimonialText":"Test testimonial.","testimonialConsent":"first-name","company":""}'
```
`test-feedback-flow.sh` posts directly to the N8N webhook (bypassing Cloudflare). After running, verify: 3 pages in Notion Feedback DB, emails in both a.beeksma21@gmail.com and the test addresses, auto-tags populated.

## N8N API Patterns

### Updating a workflow via PUT
Only these top-level keys are accepted: `name`, `nodes`, `connections`, `settings`, `staticData`. Sending extra keys (`id`, `active`, `createdAt`, `updatedAt`, `versionId`, `tags`, `shared`, etc.) returns `400: must NOT have additional properties`.

### Activating/deactivating
The `active` field is **read-only** on PUT. Use the dedicated `POST /workflows/{id}/activate` and `POST /workflows/{id}/deactivate` endpoints.

### Creating a workflow
`POST /workflows` accepts the same body as PUT. Returns the created workflow with its new `id`. The workflow is inactive by default — call `/activate` separately.

### The `.js` scripts are the source of truth

`update-reddit-monitor.js`, `create-social-poster-workflow.js`, and `update-email-sequence.js` each contain the **complete workflow definition** as a JavaScript object. To change any workflow: edit the relevant `.js` file locally, then run `node <script>.js` to deploy. Never edit workflows directly in the N8N UI without also updating the script — the script will overwrite manual changes on the next deploy.

The `workflows/` directory contains backup JSON exports and is not part of any active deploy process.

### Python scripts (legacy)
Many `.py` scripts in this directory are one-off fix scripts, not maintained utilities. Some reference the retired local N8N URL and stale credential IDs. **Do not reuse them** — write new Node.js scripts or use inline `curl`/`fetch` instead.

## Known Gotchas

### Beta Signups DB `Use Case` is a Select, not rich_text
The `Use Case` property was converted from `rich_text` to `select` with 6 options: General, Writing/Blogging, Code/Development, Accessibility, Email/Communication, Notes/Documentation. The Beta Email Sequence workflow (`EC4Fzts88a2dSB7q`) maps form values via `mapUseCase()`: `general`/`other` → General, `writing` → Writing/Blogging, `coding` → Code/Development, `accessibility` → Accessibility. If adding new form options, update the mapping in `update-email-sequence.js`.

### Phantom node references crash the webhook
If `connections` references a node name that doesn't exist in `nodes`, the webhook's `checkResponseModeConfiguration` traversal throws `Cannot read properties of undefined (reading 'name')` before any data processing. Always verify connection targets exist.

### N8N emailSend v2.1 uses `html` not `message`
When `emailFormat: "html"`, the content field is `html`, not `message`. Setting `message` results in an empty email body.

### Webhook v2 body path
N8N webhook v2 puts POST JSON at `$json.body.*`, not directly at `$json.*`. All Extract nodes use `$json.body.name`, etc.

### Notion API version
Hardcoded to `2022-06-28` across all scripts and Code nodes. The `Notion-Version` header is required on every request. Note: Notion released API version `2025-09-03` (introduces "data sources" abstraction for databases) — existing Code nodes still use `2022-06-28` and should not be migrated without testing. New work via the **notion MCP server** handles versioning automatically.

### Cloudflare Pages deploy branches
Without `--branch=main`, wrangler deploys to a preview URL (e.g., `fix-feedback-webhook.quicksay-app.pages.dev`) not production (`quicksay.app`). Always specify `--branch=main` for production deploys. After deploy, allow 2–3 minutes for propagation before testing.

### URLSearchParams decodes `+` as space
The `reddit-search.js` proxy receives subreddit lists as `?subs=RSI+ADHD+productivity`. JavaScript's `URL.searchParams.get()` decodes `+` as spaces per the `application/x-www-form-urlencoded` spec. The proxy restores `+` via `.replace(/ /g, '+')` before constructing the Reddit URL. If adding new query parameters that use `+` as a literal character, apply the same fix.

### Unicode in Python print statements
Windows cp1252 terminal can't encode `→` (U+2192) or `—` (U+2014). Use ASCII alternatives in print output.

### Rube MCP SSE response parsing
The `rube.app/mcp` endpoint returns SSE format (`event: message\ndata: {...}\n`), not plain JSON. When calling from N8N Code nodes, use `response.text()` then parse `data: ` lines. The Rube x-api-key JWT is NOT a direct Composio API key — it only authenticates with the Rube MCP endpoint, not `backend.composio.dev`.

### Rube MCP tool availability
Individual Composio tools (e.g., `TWITTER_CREATION_OF_A_POST`) are NOT directly callable as MCP tools. They must go through `RUBE_REMOTE_WORKBENCH` with Python code that calls `run_composio_tool(tool_slug=..., arguments={...})`. The `RUBE_SEARCH_TOOLS` MCP tool discovers available tools and their schemas.

## MCP Servers

Configured in `.mcp.json`:
- **n8n-mcp** — N8N workflow CRUD via `npx n8n-mcp`
- **rube** — Social media automation (Composio) via HTTP at `rube.app/mcp` (Twitter, LinkedIn, Reddit). Auth: `Authorization: Bearer <token>` + `Accept: application/json, text/event-stream`. Available tools: `RUBE_SEARCH_TOOLS`, `RUBE_REMOTE_WORKBENCH`, `RUBE_MANAGE_CONNECTIONS`, `RUBE_FIND_RECIPE`, `RUBE_EXECUTE_RECIPE`, `RUBE_MANAGE_RECIPE_SCHEDULE`.
- **notion** — Official Notion MCP via HTTP at `mcp.notion.com/mcp`. Authenticated via OAuth (run `/mcp` in Claude Code to connect). Provides direct read/write access to Adrian's Notion workspace — use this instead of raw `curl` calls to the Notion API.

## Claude Code Plugins

A local plugin is installed at `~/.claude/plugins/local/notion-best-practices/`.

### `notion-best-practices@local`

**What it does:** Enforces correct patterns whenever Claude answers Notion questions in this workspace:
1. **Formula 2.0 syntax** — uses `let()`, `ifs()`, dot notation (`prop("X").method()`), `style()` for color; never old-style nested `if(if(if(...)))` chains.
2. **Automation redirect** — property-trigger automations are Plus+ only; redirects free-plan users to **Button** workarounds instead.
3. **Hub-and-spoke architecture** — single DB per entity type, linked views in a Home dashboard, Rollups over cross-DB formulas, max 3–4 relations per DB.

**Location:** `~/.claude/plugins/local/notion-best-practices/`

**MCP dependency:** Declares `notion` MCP server (`mcp.notion.com/mcp`) in its `plugin.json`. Auth is OAuth — if tools stop working, run `/mcp` in Claude Code to re-authenticate.

**Re-register if needed:**
```bash
# From Claude Code CLI
/plugins install ~/.claude/plugins/local/notion-best-practices
```

**Automatic triggers:**
- Any question containing "formula", "prop(", "dateAdd", "dateBetween", or "style("
- Any question about automating property changes / "when a page is added" workflows
- Any request to design a multi-DB system or "Projects + Tasks" architecture
