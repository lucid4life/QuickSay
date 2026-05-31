# QuickSay Production-Hardening Audit — Skills Inventory

> Scope: Map every audit coverage area in the QuickSay beta→$39.99 production campaign to the best-fitting installed skill or plugin, and flag the gaps that need to be filled before kickoff.

Date generated: 2026-05-27
Target app: QuickSay (AHK v2 + WebView2, Inno Setup installer, Cloudflare R2 distribution)
Target outcome: production-grade $39.99 one-time-purchase via LemonSqueezy + 14-day trial

---

## 1. Installed Marketplaces

| Marketplace | Repo | Status |
|---|---|---|
| `claude-plugins-official` | `anthropics/claude-plugins-official` | installed |
| `claude-code-workflows` | `wshobson/agents` | installed (60+ workflows available, only ~10 active) |
| `awesome-claude-plugins` | `ComposioHQ/awesome-claude-plugins` | installed |
| `marketingskills` | `coreyhaines31/marketingskills` | installed |
| `agentkits-marketing` | `aitytech/agentkits-marketing` | installed |
| `pm-skills` | `phuryn/pm-skills` | installed |
| `daymade-skills` | `daymade/claude-code-skills` | installed |
| `playwright-skill` | `lackeyjb/playwright-skill` | installed |
| `supabase-agent-skills` | `supabase/agent-skills` | installed |
| `expo-plugins` | `expo/skills` | installed (mobile-only, mostly N/A) |
| `callstack-agent-skills` | `callstackincubator/agent-skills` | installed (RN-only, mostly N/A) |
| `context-mode` | `mksglu/context-mode` | installed |
| `netresearch-claude-code-marketplace` | `netresearch/claude-code-marketplace` | installed |
| `notion-plugin-marketplace` | `makenotion/claude-code-notion-plugin` | installed |

## 2. Installed Plugins (32)

`superpowers` (5.0.7), `comprehensive-review` (1.3.0), `code-review`, `application-performance` (1.3.0), `performance-testing-review` (1.2.1), `incident-response` (1.3.0), `cicd-automation` (1.2.1), `database-cloud-optimization` (1.2.0), `playwright` + `playwright-skill` (4.1.0), `frontend-design`, `context7`, `typescript-lsp`, `skill-creator`, `claude-md-management`, `claude-code-setup`, `commit-commands`, `feature-dev`, `playground`, `remember`, `revenuecat`, `firecrawl` (1.0.8), `pm-market-research` (1.0.1), `pm-product-strategy` (1.0.1), `marketing-skills`, `agentkits-marketing`, `seo-content-creation` (1.2.0), `seo-technical-optimization` (1.2.0), `seo-analysis-monitoring` (1.2.0), `expo` (RN, skip), `react-native-best-practices` (skip), `supabase` + `postgres-best-practices`, `repomix-safe-mixer`, `mermaid-tools`, `cli-demo-generator`, `context-mode`.

## 3. Coverage Map

| Coverage Area | Best Installed Skill | Gap? | Recommended Install | Notes |
|---|---|---|---|---|
| General code review / static analysis | `superpowers:requesting-code-review` + `code-review:code-review` + `comprehensive-review:full-review` (calls `code-reviewer`, `architect-review`, `security-auditor` agents) | No | — | Already excellent. Use `/code-review` for diff-level, `/full-review` for campaign-wide passes. |
| Systematic debugging | `superpowers:systematic-debugging` + `incident-response:smart-fix` | No | — | Pair with debug-log review of `data/logs/debug.txt`. |
| Test automation (E2E browser — Website + WebView2 settings UI) | `playwright-skill:playwright-skill` + `playwright` plugin | No | — | Covers Cloudflare Pages site + onboarding HTML. Cannot drive native AHK tray UI — that gap is unfixable by a skill. |
| Performance profiling | `application-performance:performance-optimization` | Partial | — | Generic skill, not AHK-aware. Reusable for measuring WebView2 boot + API latency. **No AHK-native profiler exists; rely on inline `A_TickCount` instrumentation.** |
| Security audit | `comprehensive-review` agents (`security-auditor.md`) + `superpowers:systematic-debugging` | Partial | Activate `security-scanning` from `claude-code-workflows` marketplace (already cloned, not installed) | DPAPI key handling + license-server crypto needs threat-modeling. Marketplace has `threat-modeling-expert.md` agent. |
| UX / UI critique | `interface-design:critique` + `interface-design:audit` + `taste-design` + `frontend-design:frontend-design` | No | — | Settings UI is HTML/CSS, fully covered. AHK overlay/tray needs manual review. |
| Accessibility audit | `accessibility` skill + `stitch-a11y` | Partial | Activate `accessibility-compliance` plugin (`wcag-audit-patterns`, `screen-reader-testing` skills available, not active) | Website covered. WebView2 settings page covered. Tray app: manual review only. |
| Installer / packaging (Inno Setup) | — | **YES** | **Custom skill needed** — no Inno Setup or MSI skill exists in any marketplace | Single biggest tooling gap. Suggest a thin `quicksay-installer-audit` skill listing the checks (silent install, upgrade path, uninstall cleanup, Defender SmartScreen). |
| LemonSqueezy checkout / payments | `stripe-webhooks` skill (closest analog) + `marketplaces/claude-code-workflows/plugins/payment-processing` (`stripe-integration`, `paypal-integration`, `billing-automation`, `pci-compliance` skills) | **YES** | **Activate `payment-processing` plugin from `claude-code-workflows`** + **write custom `lemonsqueezy-integration` skill** | No LemonSqueezy-specific skill anywhere. Stripe patterns transfer ~70%. Memory file `project_payment_lemonsqueezy.md` exists with prior research. |
| License key activation server | — | **YES** | **Custom skill needed** — `webhook-handler-patterns` + Supabase plugins cover infra | Logic for offline grace period, machine binding, trial enforcement is bespoke. |
| Crash reporting / Sentry | `marketplaces/claude-code-workflows/plugins/observability-monitoring` (`distributed-tracing`, `prometheus-configuration`, `slo-implementation`) | **YES** | **Write thin `crash-reporting-endpoint` skill** | None of the cloud-tracing skills target a single-binary desktop app uploading minidumps. AHK doesn't crash with dumps anyway — strategy is upload `debug.txt` tail + exception string to a Worker. |
| Cloudflare Workers / R2 / Pages | `marketplaces/claude-code-workflows/plugins/database-cloud-optimization` + `context7` (live CF docs) | Partial | — | No dedicated CF skill; `context7` covers docs query. Sufficient. |
| SEO / website audit | `seo-audit`, `seo-technical`, `seo-geo`, `seo-schema`, `seo-page`, `core-web-vitals`, `web-quality-audit`, `analytics-cookie-consent`, `gdpr-policy-framework` + 3 SEO workflow plugins | No (overkill) | — | Already saturated. Pick one: `web-quality-audit` for the campaign. |
| CI/CD audit (release.ps1) | `cicd-automation:deployment-pipeline-design` + `cicd-automation:secrets-management` | No | — | Will catch Azure Trusted Signing token reauth gotchas, R2 upload retry logic, version-sync race conditions. |
| Multi-monitor / hotkey / IPC | — | YES — but no skill solves this | None | Inherently AHK-specific. Manual test plan only. |
| PM strategy / pricing / launch | `pm-product-strategy:pricing-strategy`, `marketing-skills:pricing-strategy`, `marketing-skills:launch-strategy`, `marketing-skills:paywall-upgrade-cro`, `ceo-advisor` | No | — | Strong coverage for the $39.99 + 14-day trial decision and paywall modal design. |
| Legal / privacy / compliance | `ai-privacy-assessment`, `gdpr-policy-framework`, `direct-collection-notice`, `analytics-cookie-consent`, `edge-function-compliance-audit` | No | — | Already covered in existing `docs/Legal_Report_*.md`. |
| Documentation / CLAUDE.md health | `claude-md-management:claude-md-improver` + `gardening-skills-wiki` | No | — | Run before campaign kickoff. |

---

## 4. Skills to Install Before Campaign Starts (shortlist — 6 items)

Ordered by ROI. Stop at #6 — anything more is gold-plating.

### 1. Activate `payment-processing` plugin (`claude-code-workflows` marketplace, already cloned)
```bash
claude plugin install payment-processing@claude-code-workflows
```
Adds `stripe-integration`, `paypal-integration`, `billing-automation`, `pci-compliance` skills. ~70% transfers to LemonSqueezy webhook handling, order verification, and refund/cancel flows.

### 2. Activate `security-scanning` plugin (`claude-code-workflows` marketplace, already cloned)
```bash
claude plugin install security-scanning@claude-code-workflows
```
Adds `threat-modeling-expert` agent + `attack-tree-construction`, `sast-configuration`, `stride-analysis-patterns`, `threat-mitigation-mapping` skills. Use STRIDE on license-key flow + DPAPI key storage + crash-report endpoint.

### 3. Activate `accessibility-compliance` plugin (`claude-code-workflows` marketplace, already cloned)
```bash
claude plugin install accessibility-compliance@claude-code-workflows
```
Adds `wcag-audit-patterns` and `screen-reader-testing` skills for the website + WebView2 settings UI.

### 4. Activate `observability-monitoring` plugin (`claude-code-workflows` marketplace, already cloned)
```bash
claude plugin install observability-monitoring@claude-code-workflows
```
Adds `slo-implementation` + `distributed-tracing` skills. Repurpose for designing the crash-report telemetry contract (event schema, sampling, retention).

### 5. Activate `audit-project` plugin (`awesome-claude-plugins` marketplace, already cloned)
```bash
claude plugin install audit-project@awesome-claude-plugins
```
Provides `/audit-project`, `/audit-project-agents`, `/audit-project-github` slash commands — a structured codebase-wide audit driver that fits this campaign exactly.

### 6. Write a custom `quicksay-installer-audit` skill
Use `skill-creator` to scaffold. Codifies the Inno Setup + Azure Code Signing + SmartScreen + upgrade-path checklist. Marketplaces don't have anything that targets Windows desktop installers. Same skill should cover the LemonSqueezy + license-key activation checklist since those are equally bespoke.

Defer (don't install):
- Anything React Native / mobile (`expo`, `react-native-best-practices`) — out of scope
- More SEO plugins — already at 9 SEO skills, use `web-quality-audit` and stop
- A second debugging plugin (`error-debugging`, `error-diagnostics`, `debugging-toolkit`) — `superpowers:systematic-debugging` is sufficient

---

## 5. Notes on Coverage Quality

- **Strong (no action needed):** code review, debugging, UX/UI critique, SEO, PM strategy, marketing, CI/CD, legal/privacy. The campaign is well-tooled here.
- **Activation-only (skills cloned, not active):** payments, security threat-modeling, accessibility, observability, audit-driver. Five `claude plugin install` commands close most of the gap.
- **Genuine custom-skill territory:** Inno Setup installer audit, LemonSqueezy integration specifics, license-key activation server design, AHK-native performance profiling. The first three should be one consolidated `quicksay-go-to-paid` skill rather than three separate skills — they're all one workstream.
- **Inherently manual (no skill will fix):** AHK tray-process testing, multi-monitor positioning, hotkey conflict detection on real Windows installs, DirectShow device enumeration. Build a manual QA checklist instead.
