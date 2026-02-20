# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QuickSay marketing website — an Astro static site deployed to Cloudflare Pages.
- **Tech stack**: Astro v5.17 + Tailwind CSS v4 + Cloudflare Pages
- **Focus areas**: Conversion optimization, SEO, page copy, design
- **Do NOT**: Generate AHK code, N8N workflows, or social media posts here

## QuickSay Brand Voice

Write like Adrian — a solo developer who built a tool for himself and sells it honestly.

**Core principles:**
- Direct and declarative. Short sentences. State what QuickSay does, then stop.
- Specific over vague. Always use real numbers: "$39 one-time," "~200ms," "105 MB"
- Honest about limitations. Acknowledge tradeoffs upfront: "Requires internet," "Windows only"
- Conversational but not slangy. Like a smart coworker explaining a tool at lunch.
- Opinionated about pricing. "Voice typing is a tool, not a service you should rent month after month."

**Always use:** "$39 one-time" (never just "$39"), "voice to text" (not "speech to text"), "zero telemetry" (not "no telemetry")

**Never use:** revolutionary, game-changing, cutting-edge, powered by AI, leverage, seamlessly, robust, innovative, empower, thrilled, excited to announce

**Anti-AI-Slop:** Never start with "In today's world..." or "Imagine a world where..." or "Are you tired of...?" If a draft reads like it could be selling any product, it is wrong.

## Development Commands

```bash
npm run dev          # Dev server at http://localhost:4321
npm run build        # Production build → ./dist
npm run preview      # Preview production build locally
```

**Testing** — Playwright runs against production (`https://quicksay.app`), not local dev:
```bash
npx playwright test                           # All tests, all browsers
npx playwright test tests/seo-compliance.spec.ts  # Single test file
npx playwright test --project=chromium        # Single browser
npx playwright test --headed                  # With browser UI
```

**Deployment** — via wrangler, NOT git push:
```bash
npx wrangler pages deploy dist --project-name=quicksay-app
```
Requires `CLOUDFLARE_API_TOKEN` env var (set as permanent Windows user env var).

## Architecture

### Static Site with Edge Functions
- **Astro**: File-based routing, component islands, static HTML output
- **Tailwind CSS v4**: Theme defined via `@theme {}` in `src/styles/global.css` (NOT a JS config file)
- **MDX Content Collections**: Blog (`src/content/blog/`), docs (`src/content/docs/`), changelog (`src/content/changelog/`)
- **Cloudflare Pages Functions**: Serverless endpoints in `functions/api/` — export `onRequestPost()` + `onRequestOptions()` for CORS

### Layouts
- **`BaseLayout.astro`** — Base HTML shell. All pages use this. Props: `title`, `description`, `canonicalUrl`, `ogImage`, `faqItems`, `breadcrumbs`
- **`SEOLandingLayout.astro`** — Template for SEO landing pages (~14 pages). Includes Navbar, BuyButton hero, content slot, DownloadCTA, related pages, Footer. Props: `title`, `description`, `h1`, `canonicalUrl`, `relatedPages`
- **`BlogLayout.astro`** / **`DocsLayout.astro`** — For MDX content

### Key Components
- **`BuyButton.astro`** — Primary CTA link. Accepts `text`, `variant` (primary/secondary/ghost), `size`. Currently points to LemonSqueezy with `PRODUCT_ID` placeholder.
- **`Hero.astro`** + **`HeroDemo.astro`** — Homepage hero with animated typing demo
- **`PricingComparison.astro`** — Feature/price comparison table vs competitors
- **`OptimizedImage.astro`** — Responsive image component with srcset
- **`Testimonials.astro`** — Currently repurposed as beta CTA

### Content Collection Frontmatter

**Blog** (`src/content/blog/*.mdx`):
```yaml
title: "Post Title"
description: "SEO description"
date: "2026-02-01"
author: "QuickSay Team"
readingTime: "4 min read"
```

**Changelog** (`src/content/changelog/*.mdx`):
```yaml
version: "1.8.0"
date: "2026-02-16"
summary: "One-line summary..."
```

**Docs** (`src/content/docs/*.mdx`): `title`, `description`

### Beta System
- Signup: `/beta` → `BetaSignupForm.astro` → `/api/beta-signup` → N8N webhook
- Feedback: `/beta/feedback` → form → `/api/beta-feedback` → N8N webhook
- Honeypot spam protection (hidden `website` field)
- Success states replace form with download link

## Design System

- **Dark theme**: `#121214` background (never pure black)
- **Colors**: `bg-background`, `bg-surface`, `text-accent-teal`, `text-accent-orange`, `text-text-primary`, `text-text-secondary`
- **Fonts**: `font-headline` (Outfit), `font-body` (DM Sans), `font-mono` (JetBrains Mono) — self-hosted WOFF2 in `public/fonts/`, `font-display: optional`
- **CSS utilities**: `.fade-in-up`, `.card-hover`, `.btn-press`, `.cta-glow`
- **Animations**: CSS-only + IntersectionObserver (no JS animation libraries)

## Static Assets & Routing

- **Redirects**: `public/_redirects` — `/docs` → `/docs/getting-started`, `/downloads/*` → R2 bucket
- **Headers**: `public/_headers` — security headers, CORS, caching
- **Trailing slashes**: Disabled (`trailingSlash: 'never'` in astro.config.mjs)
- **Sitemap**: Auto-generated, excludes `/beta/*` pages

## Beta Conversion Backup

A backup of the purchase-ready website state exists before the open beta conversion:
- **Git branch**: `main-purchase-ready` (commit `58124f9`)
- **Directory backup**: `C:\QuickSay\Website-BACKUP-Purchase-Ready-Feb16-2026\`
- **Snapshot doc**: `BACKUP-SNAPSHOT-Feb16.md` — lists all files with BuyButton and $39 references
- **Restore guide**: `RESTORE-FROM-BACKUP.md` — step-by-step restoration instructions

## Related Workspaces

This is the website workspace of the QuickSay project. Other workspaces:
- `C:\QuickSay\Development\` — Desktop app (AutoHotkey v2)
- `C:\QuickSay\Automation\` — N8N workflows
- `C:\QuickSay\Marketing\` — Social media content
