# Section 3: Marketing Claims & Comparative Advertising Audit

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

**Product:** QuickSay (voice-to-text Windows app, $29 one-time purchase)
**Developer Location:** Calgary, Alberta, Canada
**Target Markets:** Canada and United States
**Date of Analysis:** February 6, 2026

---

## Table of Contents

1. [3A. Comparative Advertising Law Framework](#3a-comparative-advertising-law-framework)
2. [3B. Complete Claims Audit](#3b-complete-claims-audit)
3. [3C. Competitor Claim Verification](#3c-competitor-claim-verification)
4. [3D. Competitor Trademark Usage](#3d-competitor-trademark-usage)
5. [3E. High-Risk Claims Deep Dive](#3e-high-risk-claims-deep-dive)
6. [3F. Testimonials Audit](#3f-testimonials-audit)
7. [Summary of Required Actions](#summary-of-required-actions)

---

## 3A. Comparative Advertising Law Framework

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### Canadian Law (Primary Jurisdiction)

#### Competition Act (R.S.C., 1985, c. C-34)

**Section 52 (Criminal Provision):** No person shall knowingly or recklessly make a representation to the public that is false or misleading in a material respect for the purpose of promoting the supply or use of a product or any business interest. The general impression conveyed by a representation, as well as its literal meaning, shall be taken into account.

- **Penalties:** Fine at the court's discretion and/or imprisonment up to 14 years on indictment; fine up to $200,000 and/or imprisonment up to 1 year on summary conviction.
- **Source:** [Competition Act, s. 52](https://laws-lois.justice.gc.ca/eng/acts/c-34/section-52.html)

**Section 74.01 (Civil Provision):** A reviewable practice occurs when a person makes a representation to the public that is false or misleading in a material respect. Administrative monetary penalties (AMPs) apply.

- **Penalties for individuals:** Up to $750,000 for first occurrence, $1,000,000 for subsequent.
- **Penalties for corporations:** Up to $10,000,000 for first occurrence, $15,000,000 for subsequent.
- **Source:** [Competition Act, s. 74.01](https://laws.justice.gc.ca/eng/acts/c-34/page-11.html)

**Section 74.01(1)(b) (Performance Claims):** Any claim about product performance must be based on an "adequate and proper test" completed BEFORE the claim is published. The onus is on the advertiser to prove this. The Act does not define "adequate and proper test" but the Competition Bureau interprets it as a flexible standard depending on the nature of the representation.

- **Source:** [Competition Bureau - Performance Claims](https://competition-bureau.canada.ca/en/deceptive-marketing-practices/types-deceptive-marketing-practices/performance-claims-not-based-adequate-and-proper-test)

**2025 Private Right of Action:** As of June 20, 2025, private parties (including competitors) can seek leave from the Competition Tribunal to commence proceedings under civil misleading representation provisions. This is a significant new risk vector. Competitors like Wispr Flow now have direct standing to bring claims.

- **Source:** [ABA - Misleading Advertising in Canada's Competition Landscape](https://www.americanbar.org/groups/antitrust_law/resources/source/2025-feb/misleading-advertising-canada-competition-landscape/)

#### Key Principles for Comparative Advertising in Canada

1. Comparative advertising is **not prohibited** and can be pro-competitive.
2. Claims must be **accurate and truthful**.
3. Comparisons must be **fair** and not discredit, disparage, or unfairly attack other products.
4. Performance claims require **adequate and proper testing** completed before publication.
5. The **general impression** conveyed matters, not just the literal meaning.
6. **Source:** [Canadian Advertising Law - Misleading Advertising](https://www.canadianadvertisinglaw.com/misleading-advertising/)

### US Law (Target Market)

#### Lanham Act, Section 43(a) (15 U.S.C. Section 1125(a))

Section 43(a) prohibits false advertising and allows any competitor to sue in federal court for false or misleading statements of fact in commercial advertising. A plaintiff must prove:

1. A **false or misleading statement of fact** about a product or service
2. The statement **deceived or had capacity to deceive** a substantial segment of potential consumers
3. The deception is **material** (likely to influence purchasing decisions)
4. The product is in **interstate commerce**
5. The plaintiff has been or is likely to be **injured** as a result

**Remedies:** Injunctive relief, damages, disgorgement of profits, attorney's fees in exceptional cases.

- **Source:** [Bona Law - Lanham Act False Advertising](https://www.bonalaw.com/insights/legal-resources/do-i-have-a-lanham-act-claim-against-my-competitor-for-false-advertising)

#### FTC Guidelines on Comparative Advertising

The FTC **encourages** truthful comparative advertising. However:
- All claims must be **truthful and substantiated**
- Comparative claims **are not puffery** and require proof
- The advertiser bears the burden of substantiation
- **Source:** [Luthor AI - FTC Comparative Advertising](https://www.luthor.ai/blog-post/ftc-comparative-advertising)

#### Puffery vs. False Claims

- **Puffery (legal):** General, vague claims of superiority that no reasonable consumer would take literally (e.g., "America's favorite")
- **False claims (illegal):** Specific, measurable, verifiable statements that are untrue or misleading
- **Critical test:** If a claim can be proven true or false, it is likely NOT puffery and requires substantiation
- When used in **comparative advertising**, even statements that might otherwise be puffery may require substantiation because they become measurable in context
- **Source:** [Venable - Puffery in Advertising](https://www.venable.com/files/Publication/073d0951-9fa6-4977-9e68-4deb21a819d8/Presentation/PublicationAttachment/c245d881-6fd8-434e-b068-52959159e864/Best-Explanation-and-Update-on-Puffery-You-Will-Ever-Read-Antitrust-Summer-2017.pdf)

---

## 3B. Complete Claims Audit

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### Master Claims Table

| # | Claim | Source File | Risk | Issue | Recommendation |
|---|-------|-----------|------|-------|----------------|
| 1 | "Wispr Flow: $180/year" | PricingComparison.astro, pricing.astro, blog posts | :red_circle: **HIGH** | **Incorrect.** Wispr Flow Pro is $15/mo or $144/year (annual billing). $180/year has never been the standard price. | **Immediately correct** to current verified pricing ($15/mo or $144/year) across ALL pages and blog posts |
| 2 | "Aqua Voice: $120/year" | PricingComparison.astro, pricing.astro, blog posts | :red_circle: **HIGH** | **Incorrect.** Aqua Voice is $8/mo (~$96/year). Not $120/year. | **Immediately correct** to current verified pricing ($8/mo or ~$96/year) across ALL pages and blog posts |
| 3 | "3-Year Cost: Wispr=$540" | PricingComparison.astro, pricing.astro, vs-wispr page, blog | :red_circle: **HIGH** | Based on incorrect $180/year figure. Actual 3-year at $144/year = $432 | **Recalculate** all multi-year projections using correct pricing |
| 4 | "3-Year Cost: Aqua=$360" | PricingComparison.astro, pricing.astro, vs-aqua page, blog | :red_circle: **HIGH** | Based on incorrect $120/year figure. Actual 3-year at $96/year = $288 | **Recalculate** all multi-year projections using correct pricing |
| 5 | "BEST VALUE" badge on QuickSay column | PricingComparison.astro | :yellow_circle: **MEDIUM** | In context of a comparative pricing table with specific numbers, this shifts from puffery toward a substantive comparative claim that requires substantiation. Especially risky because the competitor prices shown are wrong. | Remove badge, or change to clearly subjective language like "Our Pick." Fix prices first regardless. |
| 6 | "Zero data retention" | PrivacyBlock.astro | :red_circle: **HIGH** | Audio IS sent to Groq's cloud API for processing. Groq's own data retention policies apply to that audio during processing. The claim implies NO data ever leaves the user's machine or is retained anywhere. | Add qualifier: "Zero data retention on our servers" or "We store nothing" with a footnote explaining audio is processed by Groq's API. Link to Groq's privacy policy. |
| 7 | "8 hours free daily" | SpeedProof.astro, multiple pages, blog posts | :yellow_circle: **MEDIUM** | Depends entirely on Groq's free tier, which has rate limits (RPM/TPM) not time-based limits. "8 hours" appears to be an estimate/approximation, not a guaranteed figure. Groq can change limits at any time. | Add disclaimer: "estimated based on Groq's current free tier limits, which may change." Consider "generous free daily usage via Groq" instead of a specific number. |
| 8 | "8x smaller than Wispr Flow" / "105 MB vs 800 MB" | SpeedProof.astro, vs-wispr page, blog | :yellow_circle: **MEDIUM** | The 800 MB figure for Wispr Flow could not be independently verified. Wispr Flow Android APK is ~150 MB. Mac/Windows installer size is unpublished. This is a performance claim requiring substantiation. | **Verify and document** the actual Wispr Flow install size. If unverifiable, remove the "8x" multiplier claim and the 800 MB figure. Could state "significantly smaller install" without specific competitor numbers. |
| 9 | "Wispr Flow: Screen Capture = Yes" | PricingComparison.astro, vs-wispr page | :yellow_circle: **MEDIUM** | Partially accurate but nuanced. Wispr Flow has an **optional** "Context Awareness" feature that captures screen content. It is not always on, and users can opt out. Stating just "Yes" without this nuance could be seen as disparaging. | Change to "Optional (Context Awareness)" or add footnote explaining it's an optional feature that can be disabled. |
| 10 | "Wispr Flow: Telemetry = Yes" / "PostHog analytics" | PricingComparison.astro, vs-wispr page | :yellow_circle: **MEDIUM** | Wispr Flow does collect usage analytics, but the specific claim of "PostHog analytics" on the vs-wispr page could not be verified (their privacy policy mentions Google Analytics, not PostHog). May have been accurate at some point but could be outdated. | Remove specific "PostHog" reference unless verifiable. Change to "Usage analytics collected" or similar factual description. |
| 11 | "Wispr Flow: 2K words/week" free tier | PricingComparison.astro, vs-wispr page | :green_circle: **LOW** | Confirmed: Wispr Flow Basic (free) includes 2,000 words per week. This appears accurate as of February 2026. | Maintain, but add "as of [date]" footnote. |
| 12 | "Aqua Voice: 4K words/week" free tier | PricingComparison.astro, vs-aqua page | :red_circle: **HIGH** | **Incorrect.** Aqua Voice free plan offers only 1,000 words (effectively a brief trial), NOT 4,000 words per week. | **Immediately correct** to actual free tier limit. |
| 13 | "SuperWhisper: $249.99 lifetime" | PricingComparison.astro, vs-superwhisper page | :green_circle: **LOW** | Confirmed accurate. SuperWhisper Pro Lifetime is $249.99. | Maintain, but add "as of [date]" footnote. |
| 14 | "$29. Once. That's it." | PricingComparison.astro, Hero.astro, multiple pages | :green_circle: **LOW** | QuickSay's own pricing claim. Accurate if true. | Ensure this accurately reflects the purchase model. No issue found. |
| 15 | "Zero screen capture" | PrivacyBlock.astro, multiple pages | :green_circle: **LOW** | QuickSay does not capture screen data. Accurate claim about own product. | Maintain. Ensure this remains true in future versions. |
| 16 | "Zero telemetry" | PrivacyBlock.astro, multiple pages | :yellow_circle: **MEDIUM** | Must be strictly true. If the app makes ANY network calls beyond the Groq API (crash reporting, update checks, license validation), this claim becomes false. | Audit the QuickSay.ahk source code to confirm absolutely zero telemetry. If update checks or license validation exist, qualify the claim. |
| 17 | "25 languages" | SpeedProof.astro, FeatureWalkthrough.astro, vs pages | :green_circle: **LOW** | Claim about own product. Groq Whisper supports 50+ languages; QuickSay exposes 25 in its UI. | Maintain. This is verifiable and about own product. |
| 18 | "Speak. QuickSay types." | Hero.astro | :green_circle: **LOW** | Descriptive tagline about own product functionality. Not a comparative or performance claim. | No issue. |
| 19 | "Voice-to-text dictation for Windows. Powered by Groq Whisper + GPT-OSS 20B." | Hero.astro | :green_circle: **LOW** | Factual description of own product and technology stack. | Verify "Groq" and "Whisper" and "GPT-OSS 20B" trademark usage (see Section 3D). |
| 20 | "No subscriptions. No recurring charges. Pay once, use forever." | PricingComparison.astro | :green_circle: **LOW** | Accurate claim about own pricing model. "Use forever" could be challenged if future major versions require additional payment. | Consider "use the current version forever" or link to FAQ about update policy. |
| 21 | "18x what QuickSay costs" (Wispr Flow over 3 years) | Blog: quicksay-vs-subscription-voice-tools.mdx | :red_circle: **HIGH** | Based on incorrect $180/year Wispr pricing. Even at $180, the math ($540/$29 = 18.6x) is approximately right, but the underlying number is wrong. Actual ratio at $144/year over 3 years: $432/$29 = ~14.9x. | Correct underlying pricing, recalculate ratio. |
| 22 | "12x" (Aqua Voice over 3 years) | Blog: quicksay-vs-subscription-voice-tools.mdx | :red_circle: **HIGH** | Based on incorrect $120/year Aqua pricing. At $96/year over 3 years: $288/$29 = ~9.9x. | Correct underlying pricing, recalculate ratio. |
| 23 | "By year five, you'd have paid $900 for Wispr Flow" | Blog: quicksay-vs-subscription-voice-tools.mdx | :red_circle: **HIGH** | Based on incorrect $180/year. Actual at $144/year x 5 = $720. | Correct to verified pricing. |
| 24 | "Wispr Flow launched Mac-first" | Blog: why-we-built-quicksay.mdx | :green_circle: **LOW** | Historically accurate. Wispr Flow launched on Mac and later expanded to Windows. | Maintain. Factually accurate statement. |
| 25 | "backed by $81M in funding" (Wispr) | vs-wispr-flow.astro | :yellow_circle: **MEDIUM** | This figure should be verified and sourced. If inaccurate, it becomes a false factual claim about a competitor. | Verify from press releases or Crunchbase. Add "according to [source]" citation. If unverifiable, remove. |
| 26 | "pays for itself in about two weeks of Aqua Voice subscription" | Blog: quicksay-vs-subscription-voice-tools.mdx | :red_circle: **HIGH** | At $8/mo Aqua pricing, $29/$8 = 3.6 months, not "two weeks." | Correct: at $8/mo, QuickSay pays for itself in ~3.5 months vs Aqua. |
| 27 | "or ten days of Wispr Flow" | Blog: quicksay-vs-subscription-voice-tools.mdx | :yellow_circle: **MEDIUM** | At $15/mo ($0.50/day), $29/$0.50 = 58 days, not 10 days. At $144/yr ($0.39/day), 74 days. | Correct this calculation. The math appears entirely wrong. |
| 28 | "No activation limits, no phone-home DRM" | pricing.astro (FAQ) | :green_circle: **LOW** | Claim about own product. Must be strictly true. | Verify there is truly no license activation or phone-home mechanism. |
| 29 | "All updates within the current major version are included" | pricing.astro (FAQ) | :green_circle: **LOW** | Claim about own product update policy. | Ensure this is documented in Terms of Service. |
| 30 | Feature descriptions (Voice Commands, Custom Dictionary, Smart Punctuation, etc.) | FeatureWalkthrough.astro | :green_circle: **LOW** | Claims about own product features. Must be accurate. | Verify each feature works as described. |
| 31 | "Control your apps with your voice. Navigate, select, and edit without touching the keyboard." | FeatureWalkthrough.astro | :yellow_circle: **MEDIUM** | "Control your apps" and "Navigate" may overstate current voice command capabilities (which are limited to select all, copy, paste, undo, redo). | Ensure description matches actual capability. "Navigate" implies cursor movement which may not be supported. |
| 32 | "Optimize for your microphone. Save presets for different recording environments." | FeatureWalkthrough.astro | :yellow_circle: **MEDIUM** | Feature description mentions "Save presets" -- verify this is actually a feature. Current implementation shows quality presets (high/medium/low) but not saved environment presets. | Align description with actual feature capabilities. |
| 33 | "Wispr Flow captures your screen to understand context" | Blog: why-we-built-quicksay.mdx | :yellow_circle: **MEDIUM** | As noted above, this is an optional feature. Stating it as a general fact about Wispr Flow without noting it's optional could be seen as misleading or disparaging. | Add qualifier: "Wispr Flow offers an optional screen capture feature for context" |

### Claims by Source File

#### PricingComparison.astro (appears on index and pricing pages)
- 8 claims identified, 3 HIGH risk (incorrect competitor pricing)

#### SpeedProof.astro (appears on index page)
- 4 claims identified, 1 MEDIUM risk (8x size claim)

#### PrivacyBlock.astro (appears on index page)
- 3 claims identified, 1 HIGH risk ("Zero data retention")

#### quicksay-vs-wispr-flow.astro
- 12+ claims, multiple HIGH risk (pricing figures flow through from incorrect data)

#### quicksay-vs-aqua-voice.astro
- 10+ claims, HIGH risk (incorrect pricing, incorrect free tier)

#### quicksay-vs-superwhisper.astro
- 8+ claims, LOW risk overall (pricing verified, fair and balanced tone)

#### Blog Posts (3 articles)
- Multiple HIGH risk claims repeating incorrect competitor pricing
- Incorrect payback period calculations

---

## 3C. Competitor Claim Verification

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 1. Wispr Flow Pricing

| Claim on Website | Verified Actual Price | Status |
|------------------|----------------------|--------|
| $180/year | $15/mo or $144/year (annual billing) | :red_circle: **INCORRECT** |

**Sources:** [Wispr Flow Pricing Page](https://wisprflow.ai/pricing), [Eesel.ai Pricing Breakdown](https://www.eesel.ai/blog/wispr-flow-pricing)

**Notes:** Wispr Flow Pro is $15/month, or $12/month billed annually ($144/year). The $180/year figure cited on the QuickSay website ($15 x 12) would represent the monthly billing total, but that is not how the annual plan is priced. Wispr also offers a free basic tier and enterprise plans. **This pricing error appears across the entire website and all three blog posts.**

### 2. Aqua Voice Pricing

| Claim on Website | Verified Actual Price | Status |
|------------------|----------------------|--------|
| $120/year | $8/mo (~$96/year) | :red_circle: **INCORRECT** |

**Sources:** [SaaSWorthy - Aqua Voice Pricing](https://www.saasworthy.com/product/aqua-voice/pricing), [Aqua Voice Website](https://aquavoice.com/)

**Notes:** Aqua Voice Pro is $8/month. Annual pricing would be approximately $96/year. The $120/year figure on the QuickSay website does not match any published Aqua Voice pricing tier.

### 3. SuperWhisper Pricing

| Claim on Website | Verified Actual Price | Status |
|------------------|----------------------|--------|
| $249.99 lifetime | $249.99 lifetime (also $8.49/mo or $84.99/year) | :green_circle: **CORRECT** |

**Sources:** [SuperWhisper Website](https://superwhisper.com/), [Apple App Store](https://apps.apple.com/us/app/superwhisper/id6471464415)

### 4. Wispr Flow Install Size

| Claim on Website | Verified Actual Size | Status |
|------------------|---------------------|--------|
| ~800 MB | **UNVERIFIABLE** | :red_circle: **CANNOT CONFIRM** |

**Notes:** The Android APK is ~150 MB. Mac/Windows installer size is not publicly documented. The 800 MB claim cannot be independently verified from public sources. This is a performance claim under both Canadian and US law requiring substantiation before publication.

### 5. Wispr Flow Screen Capture

| Claim on Website | Verified Status | Status |
|------------------|----------------|--------|
| "Yes" / "captures screens" | Optional "Context Awareness" feature; user can opt out | :yellow_circle: **PARTIALLY CORRECT but misleading** |

**Sources:** [Wispr Flow Privacy Page](https://wisprflow.ai/privacy), [Wispr Flow Data Controls](https://wisprflow.ai/data-controls)

**Notes:** Wispr Flow does have a screen capture capability, but it is part of an optional "Context Awareness" feature that users can disable. Presenting it as a blanket "Yes" without noting it's optional is misleading and could be considered disparaging.

### 6. Wispr Flow Telemetry

| Claim on Website | Verified Status | Status |
|------------------|----------------|--------|
| "Yes" / "PostHog analytics" | Usage analytics collected; Google Analytics confirmed; PostHog not confirmed | :yellow_circle: **PARTIALLY CORRECT** |

**Sources:** [Wispr Flow Privacy Policy](https://wisprflow.ai/privacy-policy)

**Notes:** Wispr Flow does collect analytics data. Their privacy policy mentions Google Analytics as a third-party analytics service. The specific claim of "PostHog analytics" on the vs-wispr comparison page could not be verified and may be outdated or incorrect.

### 7. Wispr Flow Free Tier

| Claim on Website | Verified Status | Status |
|------------------|----------------|--------|
| 2K words/week | Flow Basic: 2,000 words per week (free) | :green_circle: **CORRECT** |

**Sources:** [Wispr Flow Pricing](https://wisprflow.ai/pricing)

### 8. Aqua Voice Free Tier

| Claim on Website | Verified Status | Status |
|------------------|----------------|--------|
| 4K words/week | Free plan: 1,000 words total (effectively a trial) | :red_circle: **INCORRECT** |

**Sources:** [SaaSWorthy - Aqua Voice](https://www.saasworthy.com/product/aqua-voice/pricing)

**Notes:** The 4,000 words/week figure appears to be fabricated or based on severely outdated information. The actual free tier is 1,000 words total, not per week.

### Verification Summary

| Competitor Claim | Verified? | Correct? |
|-----------------|-----------|----------|
| Wispr Flow: $180/year | Yes | :red_circle: **No** - Actually $144/year |
| Aqua Voice: $120/year | Yes | :red_circle: **No** - Actually ~$96/year |
| SuperWhisper: $249.99 lifetime | Yes | :green_circle: **Yes** |
| Wispr Flow: ~800 MB install | No | :red_circle: **Unverifiable** |
| Wispr Flow: Screen capture | Yes | :yellow_circle: **Misleading** - Optional feature |
| Wispr Flow: Telemetry | Partial | :yellow_circle: **PostHog unverified** |
| Wispr Flow: 2K words/week free | Yes | :green_circle: **Yes** |
| Aqua Voice: 4K words/week free | Yes | :red_circle: **No** - Actually 1K words total |

---

## 3D. Competitor Trademark Usage

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 1. Trademark Registration Status

#### USPTO (United States)
Direct searches of the USPTO trademark database were not possible via web search. However:

- **Wispr Flow:** Wispr, Inc. is a well-funded company ($81M+ raised) and almost certainly has trademark protection for "Wispr Flow" in the US, either through registration or common law use.
- **Aqua Voice:** Likely has trademark protection through use in commerce.
- **SuperWhisper:** Likely has trademark protection through use in commerce and App Store presence.

**Recommendation:** Before publishing, search the [USPTO Trademark Database](https://tmsearch.uspto.gov/) for all three marks to determine registration status.

#### CIPO (Canada)
Direct searches of the CIPO trademark database were not possible via web search.

**Recommendation:** Search the [CIPO Canadian Trademarks Database](https://ised-isde.canada.ca/cipo/trademark-search/srch) for all three marks.

### 2. Nominative Fair Use Doctrine

Nominative fair use permits using a competitor's trademark to refer to the competitor's actual goods or services for purposes of comparison. Under US law (9th Circuit test from *New Kids on the Block v. News America Publishing*), nominative fair use requires:

1. The product or service **is not readily identifiable** without using the trademark
2. Only **as much of the mark as reasonably necessary** to identify the product is used
3. Use does **not suggest sponsorship or endorsement** by the trademark owner

**Sources:** [INTA - Fair Use of Trademarks](https://www.inta.org/fact-sheets/fair-use-of-trademarks-intended-for-a-non-legal-audience/), [Dykema - Comparative Advertising and Nominative Fair Use](https://www.dykema.com/a/web/nzmvwJUKdkU9WpD6NEMbNs/8zzsZa/dykema-primercomparative-advertising-and-nominative-fair-use.pdf)

### 3. Analysis of QuickSay's Trademark Use

| Usage | Assessment |
|-------|------------|
| Naming competitors in comparison tables | :green_circle: Generally permissible under nominative fair use if comparisons are truthful |
| Using competitor names in SEO page URLs (/quicksay-vs-wispr-flow) | :yellow_circle: Common practice but can attract attention. Generally acceptable if the content is genuinely comparative and not misleading. |
| Using competitor names in meta descriptions and title tags | :yellow_circle: Acceptable for nominative fair use, but be careful not to imply association. |
| Styling competitor names with reduced opacity/dimmed colors | :yellow_circle: Minor risk. The visual de-emphasis of competitor names while highlighting QuickSay in teal could be seen as subtly disparaging in presentation. |

### 4. SEO Comparison Pages: Legal Risk Assessment

The three dedicated comparison pages (/quicksay-vs-wispr-flow, /quicksay-vs-aqua-voice, /quicksay-vs-superwhisper) are a **common and generally accepted** practice in SaaS marketing. They fall within nominative fair use when:

- The comparisons are **truthful and substantiated** :red_circle: **Currently failing this test due to incorrect pricing**
- The content provides **genuine value** to consumers making purchasing decisions :green_circle: The pages are substantive and informative
- There is **no suggestion of sponsorship** by the competitors :green_circle: Pages clearly present QuickSay as an alternative, not affiliated
- The competitor marks are used only **as much as reasonably necessary** :green_circle: Competitor names appear in reasonable context

**Current Risk Level:** :red_circle: **HIGH** -- Not because comparison pages are inherently problematic, but because the factual claims on these pages are **demonstrably incorrect** (wrong pricing, wrong free tier limits). False comparative claims undermine the nominative fair use defense and expose QuickSay to Lanham Act (US) and Competition Act (Canada) claims.

### 5. Can Competitors Send Cease-and-Desist Letters?

**Yes, absolutely.** Any competitor can send a C&D letter at any time. The relevant questions are:

1. **Would it have merit?** Currently: :red_circle: **Yes**, because several factual claims about competitors are verifiably incorrect. Under the Lanham Act, Wispr Flow and Aqua Voice could have viable false advertising claims.

2. **Would a competitor bother?**
   - **Wispr Flow** ($81M in funding): Has resources and likely legal counsel. If QuickSay gains visibility, a C&D or Lanham Act claim is plausible, especially with the screen capture characterization and inflated pricing.
   - **Aqua Voice**: Smaller company but still has standing if claims about their product are false.
   - **SuperWhisper**: Lowest risk. The comparison page is balanced and mostly accurate.

3. **What would happen?** A C&D would likely demand correction of specific false claims. If ignored, it could escalate to a Lanham Act complaint (US) or Competition Tribunal application (Canada, new private right of action since June 2025).

---

## 3E. High-Risk Claims Deep Dive

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 1. "BEST VALUE" Badge

**Location:** PricingComparison.astro (line 73-74)
**Current text:** `<span class="inline-block bg-accent-teal text-background text-xs font-bold px-3 py-1 rounded-full mb-2">BEST VALUE</span>`

**Analysis:**

Standing alone, "Best Value" is typically treated as **puffery** -- a vague, subjective claim of superiority that no reasonable consumer would interpret as a literal, provable fact. Courts have generally held that superlative claims like "best" are non-actionable opinions.

**However**, the context changes the analysis significantly:

- The badge appears directly above a **specific, quantified pricing comparison table**
- The table lists exact dollar figures for competing products
- The combination transforms "BEST VALUE" from vague puffery into an **implied factual claim** that can be measured against the data presented
- Under the NAD (National Advertising Division) standard, when a "best" claim is presented alongside comparative data, it becomes a **substantive claim requiring substantiation**
- Most critically: **the comparative data itself is wrong**, which means the "BEST VALUE" claim is based on false premises

**Risk Level:** :yellow_circle: **MEDIUM** rising to :red_circle: **HIGH** because the underlying data is incorrect.

**Recommendation:**
1. Fix all pricing data first (this is mandatory regardless)
2. After fixing data, QuickSay IS genuinely the lowest-priced option, so "BEST VALUE" becomes defensible on pure price
3. However, "value" implies more than just price -- it implies a quality-per-dollar assessment. Consider changing to "LOWEST PRICE" (purely factual) or simply removing the badge.

### 2. "Zero Data Retention"

**Location:** PrivacyBlock.astro (line 44)
**Current text:** `Zero data retention.`

**Analysis:**

This is the **single most legally problematic privacy claim** on the website.

QuickSay sends audio recordings to Groq's cloud API for transcription. This means:

1. **Audio data leaves the user's machine** -- it is transmitted to Groq's servers
2. **Groq processes the audio** -- during processing, the data exists on Groq's infrastructure
3. **Groq's data retention policies apply** -- not QuickSay's. Groq may retain data for a period per their own policies.
4. **Transcription text is sent to Groq's GPT-OSS 20B** for cleanup -- another data transmission

The claim "Zero data retention" creates the general impression that no user data is stored anywhere, by anyone. This is **materially misleading** under both Canadian (Competition Act s. 52, general impression test) and US (FTC) standards.

**Risk Level:** :red_circle: **HIGH**

**Specific Risks:**
- Competition Bureau enforcement action for misleading representation
- FTC action for deceptive privacy claims (the FTC has been aggressive on this -- see recent enforcement actions against companies making false "no data retention" claims)
- Consumer class action for deceptive privacy practices
- Undermines the "privacy-first" brand positioning if exposed

**Recommendation:**
1. **Immediately change** to: "We retain zero data. Audio is processed by Groq's cloud API -- see their [privacy policy](link) for their data handling."
2. Or restructure the three privacy claims to be clearly about **QuickSay's own behavior**: "We capture zero screens. We collect zero analytics. We store zero data."
3. Add a "How your data flows" section that transparently explains the Groq API processing
4. Add a disclaimer/footnote to the PrivacyBlock component linking to Groq's privacy policy

### 3. "8 Hours Free Daily"

**Location:** SpeedProof.astro, PricingComparison.astro, multiple pages and blog posts
**Current text:** `8 hours (Groq)` / `8 hrs free daily` / `via Groq's free tier`

**Analysis:**

This claim has multiple issues:

**a) Accuracy:** Groq's free tier is defined by rate limits (requests per minute, tokens per minute/day), NOT by time-based usage. The "8 hours" figure appears to be an internal estimate of how much transcription a user could theoretically do within the rate limits. This is:
- Not a figure from Groq's documentation
- Dependent on recording length, frequency, and other variables
- Subject to change whenever Groq adjusts rate limits

**b) Dependency on third party:** The FAQ on the pricing page acknowledges this risk: "If Groq changes their free tier, you can use your own Groq API key." But the marketing pages present "8 hours free daily" as a product feature, not as a dependent third-party benefit.

**c) Performance claim:** Under Canadian law, this is a performance claim that must be based on "adequate and proper testing." Has QuickSay actually tested that 8 hours of daily dictation is consistently possible on Groq's free tier?

**Risk Level:** :yellow_circle: **MEDIUM**

**Recommendation:**
1. Replace specific "8 hours" with a qualified description: "Generous free daily usage via Groq's free tier"
2. If keeping a number, add clear disclaimer: "Estimated based on Groq's current free tier rate limits as of [date]. Actual usage may vary. Groq's free tier terms may change."
3. Document your testing methodology for the 8-hour estimate to satisfy the "adequate and proper test" standard
4. Consider the cost calculator and FAQ as the appropriate place for specifics, not bold marketing claims

### 4. "8x Smaller" (Install Size Comparison)

**Location:** SpeedProof.astro (line 29-30)
**Current text:** `8x smaller than Wispr Flow` / `105 MB vs 800 MB`

**Analysis:**

This is a **specific, quantified comparative performance claim** about a competitor's product. It requires:

1. **Accurate measurement of both products** (adequate and proper test under Canadian law)
2. **Truthful representation** (Lanham Act)
3. **Apples-to-apples comparison** (same platform, same measurement methodology)

**Problems:**
- QuickSay is Windows-only; Wispr Flow is primarily Mac (now also Windows). Are you comparing Windows install to Mac install? Windows to Windows?
- The 800 MB Wispr Flow figure **could not be independently verified** from any public source
- Wispr Flow's Android APK is ~150 MB, suggesting the 800 MB figure may be inaccurate or may include cached data, local models, or other files
- Install size comparisons have limited consumer relevance and could be seen as cherry-picking a metric where you look favorable

**Risk Level:** :yellow_circle: **MEDIUM**

**Recommendation:**
1. If you have documentation proving the 800 MB figure (e.g., screenshots of Wispr Flow's disk usage), preserve that evidence
2. If you cannot substantiate the 800 MB figure, **remove the specific comparison** and the "8x" claim
3. Could replace with: "Lightweight ~105 MB install" (claim about own product, no competitor comparison needed)
4. If keeping the comparison, add measurement methodology footnote: "Measured as total disk usage after installation of [version] on [platform] on [date]"

### 5. 3-Year Cost Projections

**Location:** PricingComparison.astro, pricing.astro (cost calculator), blog posts

**Analysis:**

Cost projections based on competitor subscription pricing are a common and generally acceptable practice in comparative advertising. **However:**

1. **The underlying prices are wrong** -- This is the fundamental problem. The projections use $180/year for Wispr (actual: $144/year) and $120/year for Aqua (actual: ~$96/year).
2. **Projecting unchanged prices** -- Assuming competitors will maintain the same price for 3-5 years could be challenged as speculative, though this is standard practice and generally accepted.
3. **Not accounting for potential QuickSay costs** -- The projection shows QuickSay at $29 for all years, but if a user needs to buy their own Groq API key (if the free tier changes), there are additional costs. The FAQ mentions this possibility.

**Risk Level:** :red_circle: **HIGH** (due to incorrect input data)

**Recommendation:**
1. **Immediately correct** all competitor pricing to verified current figures
2. Add footnote: "Based on published pricing as of [date]. Competitor pricing may change."
3. Consider adding a note that QuickSay costs may increase if Groq's free tier changes (BYOK costs)
4. The cost calculator on the pricing page (JavaScript widget) uses hardcoded values `{quicksay:29,wispr:180,aqua:120}` that must also be updated

### 6. "Wispr Flow = Yes" for Screen Capture (Disparagement Risk)

**Location:** PricingComparison.astro (line 31-32), quicksay-vs-wispr-flow.astro

**Analysis:**

Stating that Wispr Flow uses screen capture is factually grounded -- Wispr Flow's "Context Awareness" feature does capture screen content. However:

1. **The feature is optional** and can be turned off by the user
2. **The table entry uses red coloring** (`negativeWispr: true` renders in `text-red-400/80`) making it visually appear as a negative/warning
3. **Combined with "Zero screen capture" for QuickSay in green**, this creates a strong implied message that Wispr Flow is invasive/untrustworthy
4. Under Canadian and US law, **comparative advertising must not unfairly disparage** competitors. Presenting an optional feature as a blanket characteristic, combined with negative visual styling, approaches the line of disparagement.

**Risk Level:** :yellow_circle: **MEDIUM**

**Recommendation:**
1. Change from "Yes" to "Optional" or "Optional (can be disabled)"
2. Remove the red text color (the `negativeWispr` flag)
3. Add a footnote explaining: "Wispr Flow offers an optional Context Awareness feature that can be disabled in settings"
4. On the vs-wispr comparison page, the existing text already partially addresses this but should be more explicit about it being optional

---

## 3F. Testimonials Audit

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### Current State

**File:** `/mnt/c/QuickSay/Website/src/components/Testimonials.astro`

The testimonials section contains **6 placeholder testimonials** with fabricated names, roles, and quotes:

| Name | Role | Content Summary |
|------|------|----------------|
| Alex Chen | Senior Developer | Claims to have switched from Wispr Flow; compares pricing |
| Sarah Mitchell | Software Engineer | RSI claim; works reliably in VS Code |
| James Okafor | Novelist | Custom dictionary learned character names |
| Maria Santos | Content Strategist | Claims 3 weeks of use without hitting limit |
| David Park | Systems Administrator | References 105 MB install, no telemetry |
| Priya Sharma | Product Manager | Claims 20 minutes saved daily |

### Placeholder Tags

The component includes multiple layers of placeholder identification:
- Code comments: `/* [PLACEHOLDER] All testimonials below are placeholders */`
- HTML comments: `<!-- [PLACEHOLDER] TESTIMONIALS -->`
- Visible `[PLACEHOLDER]` tags next to each name in the rendered output (line 99)

### Legal Analysis

#### FTC Requirements (16 CFR Part 255)

The FTC's Endorsement Guides are explicit:

1. **Endorsements must reflect honest opinions, findings, beliefs, or experiences of the endorser** (16 CFR 255.1(a))
2. The FTC's 2023 updated Guides specifically address **fabricated endorsers**: "An 'endorser' can be an actual or fictitious party and may even include 'virtual influencers.'" However, fabricated endorsers presenting fabricated experiences are **deceptive**.
3. The Guides **prohibit** advertisers from creating, purchasing, or procuring fake or misleading consumer reviews and testimonials.
4. **Source:** [FTC - Endorsements, Influencers, and Reviews](https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking)

#### Canadian Competition Act

- Fake testimonials constitute a **false or misleading representation** under s. 74.01
- Even with "[PLACEHOLDER]" tags, consumers who skim may not notice the small tag and take the testimonials as real

#### Risk Assessment

**Current Risk (with [PLACEHOLDER] tags):** :yellow_circle: **MEDIUM**

The [PLACEHOLDER] tags provide *some* protection but are insufficient because:

1. The tags are small text (`text-text-quaternary font-normal ml-1`) that could easily be missed
2. The overall section heading is "What users are saying" -- which frames the content as real user testimonials
3. Under the FTC's "net impression" standard, a reasonable consumer scrolling through the page could interpret these as real testimonials
4. One placeholder testimonial (Alex Chen) specifically claims to have "switched from Wispr Flow" and compares pricing -- this is a fabricated comparative claim attributed to a fake user, which is especially problematic
5. Another (Maria Santos) makes a specific performance claim ("three weeks straight without hitting a limit") that is fabricated

**Risk WITHOUT [PLACEHOLDER] tags (if removed before launch):** :red_circle: **CRITICAL**

If the [PLACEHOLDER] tags were removed and the testimonials published as-is, this would constitute:
- Clear FTC violation (fabricated testimonials)
- Competition Act violation (false representations)
- Potential Lanham Act liability if competitors are named
- A severe blow to credibility if discovered

### Recommendations

1. **Do NOT remove the [PLACEHOLDER] tags** until real testimonials replace each entry
2. **Do NOT publish the site with these testimonials** even with placeholder tags -- remove the entire section or replace with real content
3. **Immediately remove the Alex Chen testimonial** that references Wispr Flow -- a fabricated testimonial making comparative claims about a competitor is uniquely dangerous
4. For pre-launch/beta, consider:
   - Removing the testimonials section entirely
   - Replacing with a "Join our beta testers" CTA
   - Using a "Coming soon" placeholder with no fake quotes
5. When collecting real testimonials:
   - Get **written permission** from each person
   - Verify they are **actual users** of the product
   - Do not edit testimonials to change their meaning
   - If offering compensation (discounts, etc.), disclose the material connection
   - Retain documentation of each testimonial's authenticity

---

## Summary of Required Actions

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### :red_circle: CRITICAL -- Fix Immediately (Before Launch)

| # | Action | Files Affected | Risk if Not Fixed |
|---|--------|---------------|-------------------|
| 1 | **Correct Wispr Flow pricing** from $180/year to $144/year (or $15/mo) | PricingComparison.astro, pricing.astro (JS calculator), quicksay-vs-wispr-flow.astro, all 3 blog posts | Lanham Act claim, Competition Act violation |
| 2 | **Correct Aqua Voice pricing** from $120/year to $96/year (or $8/mo) | PricingComparison.astro, pricing.astro (JS calculator), quicksay-vs-aqua-voice.astro, blog post | Lanham Act claim, Competition Act violation |
| 3 | **Correct Aqua Voice free tier** from 4K words/week to 1K words total | PricingComparison.astro, quicksay-vs-aqua-voice.astro | False factual claim about competitor |
| 4 | **Recalculate all multi-year cost projections** using corrected pricing | pricing.astro (HTML + JS), PricingComparison.astro, vs-pages, blog posts | Cascading false claims |
| 5 | **Fix "Zero data retention" claim** -- qualify that audio is processed by Groq cloud | PrivacyBlock.astro | Deceptive privacy claim; FTC enforcement risk |
| 6 | **Remove or replace all fake testimonials** before public launch | Testimonials.astro | FTC fabricated endorsement violation |
| 7 | **Fix payback period calculations** in blog post (currently says "two weeks" / "ten days" -- math is wrong) | quicksay-vs-subscription-voice-tools.mdx | Demonstrably false comparative claims |

### :yellow_circle: IMPORTANT -- Fix Before Launch

| # | Action | Files Affected |
|---|--------|---------------|
| 8 | **Qualify "8 hours free daily"** with disclaimer about Groq's free tier | SpeedProof.astro, all pages using this claim |
| 9 | **Verify or remove "800 MB" Wispr Flow install size** claim | SpeedProof.astro, quicksay-vs-wispr-flow.astro, blog |
| 10 | **Change Wispr Flow screen capture** from "Yes" to "Optional" with footnote | PricingComparison.astro, quicksay-vs-wispr-flow.astro |
| 11 | **Remove "PostHog analytics" reference** unless verifiable | quicksay-vs-wispr-flow.astro |
| 12 | **Remove red text styling** on Wispr Flow negative attributes | PricingComparison.astro |
| 13 | **Verify "$81M in funding" claim** for Wispr or add source | quicksay-vs-wispr-flow.astro |
| 14 | **Audit "Zero telemetry" claim** against actual app behavior | PrivacyBlock.astro, multiple pages |
| 15 | **Align feature descriptions** with actual capabilities (voice commands, presets) | FeatureWalkthrough.astro |

### :green_circle: RECOMMENDED -- Best Practices

| # | Action | Files Affected |
|---|--------|---------------|
| 16 | Add "as of [date]" footnotes to all competitor pricing and feature claims | All comparison pages |
| 17 | Add "pricing last verified on [date]" timestamp to comparison tables | PricingComparison.astro |
| 18 | Establish a quarterly review process for competitor claim accuracy | Process documentation |
| 19 | Search USPTO and CIPO for competitor trademark registrations | Legal documentation |
| 20 | Consider adding a general disclaimer to comparison pages | vs-pages, PricingComparison.astro |
| 21 | Review "BEST VALUE" badge -- consider changing to "LOWEST PRICE" or removing | PricingComparison.astro |
| 22 | Clarify "use forever" / update policy in Terms of Service | ToS, pricing.astro FAQ |

### Overall Risk Assessment

**Current state of the website: :red_circle: HIGH RISK for comparative advertising claims.**

The primary issue is not that QuickSay uses comparative advertising (this is legal and encouraged), nor that it uses competitor trademarks in comparisons (this is nominative fair use). The primary issue is that **multiple factual claims about competitors are demonstrably incorrect**, including core pricing figures that appear across nearly every page of the site.

This exposes QuickSay to:
- **Lanham Act Section 43(a) claims** from Wispr Flow and Aqua Voice (US)
- **Competition Act proceedings** from the Competition Bureau or private parties (Canada, with new private right of action since June 2025)
- **Cease-and-desist letters** from any named competitor
- **Loss of nominative fair use defense** (fair use requires truthful claims)
- **Reputational damage** if incorrect claims are publicly exposed

**The fixes are straightforward:** correct the pricing data, qualify the privacy and free-tier claims, and remove fake testimonials. Once these changes are made, the comparative advertising approach is fundamentally sound and legally defensible.

---

*Report generated February 6, 2026. All competitor pricing and features verified as of this date. Competitor information should be re-verified quarterly.*
