# QuickSay Legal & Copyright Risk Analysis — Master Report

**Date:** February 7, 2026
**Product:** QuickSay v1.0 — $29 one-time-purchase voice-to-text Windows application
**Developer:** Calgary, Alberta, Canada (sole developer)
**Target Markets:** Canada and United States

> ⚠️ **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

---

## Executive Summary

This report is the consolidated output of a six-agent legal analysis covering every layer of the QuickSay product and marketing website. Each section was researched independently with web searches for current laws, terms of service, pricing data, and trademark databases.

### Issue Count

| Priority | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 18 | Must fix before launch — legal exposure risk |
| 🟡 Moderate | 14 | Should fix before launch — best practice / risk reduction |
| 🟢 Low | 8 | Address when convenient — minor or precautionary |

### 🔴 Critical Issues (Must Fix Before Launch)

1. **Competitor pricing is WRONG across the entire website** — Wispr Flow is $144/yr (not $180), Aqua Voice is ~$96/yr (not $120), and all 3-year cost projections are therefore incorrect. This exposes QuickSay to Lanham Act and Competition Act claims. *(Section 3)*

2. **All 6 testimonials are fabricated placeholders** — one even makes comparative claims about Wispr Flow. FTC and Competition Bureau prohibit fake testimonials. Must be removed before launch. *(Section 3)*

3. **"Zero data retention" claim is misleading** — Groq retains data up to 30 days by default. Users must opt-in to Zero Data Retention. QuickSay also stores history, audio recordings, and debug logs locally. *(Sections 2, 3, 4)*

4. **Privacy policy contains factual inaccuracies** — Claims audio is "not stored" (but `save_recordings` defaults to `true`). Claims QuickSay "does not record which applications you use" (but `history.json` stores active window titles). *(Section 4)*

5. **No cross-border data transfer disclosure** — Audio data is sent to Groq's US-based servers (GCP). PIPEDA and Alberta PIPA require disclosure of foreign data processing. *(Section 4)*

6. **Privacy policy missing required elements** — No data controller identification, no user rights section (access/correction/deletion), no breach notification procedure. Required by PIPEDA and PIPA. *(Section 4)*

7. **GPL license files are summaries, not full texts** — The GPL v3.0 and GPL v2.0 files in LICENSES/ are 58-line summaries instead of the required full license texts (~674 and ~339 lines respectively). *(Section 1)*

8. **No formal written offer for GPL source code** — GPL v3 Section 6 requires the distributor to provide source code or a written offer valid for 3+ years. Currently only links to upstream websites. *(Section 1)*

9. **FFmpeg is a GPL v3.0 build with GPL video codecs** — QuickSay only needs audio recording but bundles an FFmpeg with libx264/libx265/libxvid. Switching to an LGPL-only build eliminates the GPL compliance burden entirely. *(Section 1)*

10. **Refund policy not finalized** — ToS says "details will be finalized before launch." Canadian Internet Sales Contract Regulation and consumer protection laws require a clear refund policy. *(Section 6)*

11. **Terms of Service missing 11+ required elements** — No governing law/jurisdiction clause, no IP ownership clause, no dispute resolution mechanism, no third-party service disclaimers, no BYOK liability terms, no age restrictions, no modifications clause. *(Section 6)*

12. **No EULA** — QuickSay needs a click-through End User License Agreement covering API key responsibility, data processing disclosure, transcription accuracy disclaimers, and open-source component notices. *(Section 6)*

13. **Blog post math errors** — "Pays for itself in two weeks of Aqua Voice" and "ten days of Wispr Flow" — actual calculations yield months, not days/weeks. *(Section 3)*

14. **Aqua Voice free tier claim is wrong** — Website says 4K words/week; actual is 1,000 words total (a brief trial, not ongoing). *(Section 3)*

15. **Sound files have undocumented provenance** — Three .wav files bundled with the app have no documented origin or license. *(Sections 1, 5)*

16. **MIT license for QuickSay + GPL compiled binary = potential conflict** — The compiled .exe bundles the AHK v2 runtime (GPL v2) inside a binary licensed as MIT. This may be non-compliant. *(Section 5)*

17. **"Your words. Your machine. Period." is misleading** — Words transit through Groq's US servers twice (audio + text cleanup). The tagline implies everything stays local. *(Section 4)*

18. **Wispr Flow screen capture listed as "Yes" without qualification** — It's actually an optional context feature, not constant surveillance. Presenting it as a binary "Yes" could be seen as disparaging. *(Section 3)*

### 🟡 Moderate Issues (Should Fix Before Launch)

1. **"8 hours free daily" depends on Groq's free tier** — Must be attributed to Groq with disclaimers that limits are subject to change at any time. *(Sections 2, 3)*

2. **"800 MB" Wispr Flow install size is unverifiable** — No current source confirms this figure. *(Section 3)*

3. **"BEST VALUE" badge on comparison table** — In context of specific price comparisons (some of which are wrong), this may require substantiation beyond puffery. *(Section 3)*

4. **3-year cost projections assume static competitor pricing** — Projecting $540 for Wispr Flow assumes no price changes over 3 years. *(Section 3)*

5. **Red text styling on competitor negatives** — Approaches visual disparagement; consider neutral styling. *(Section 3)*

6. **Platform dependency risk** — Entire product depends on Groq's continued service, free tier, and pricing. Should build alternative provider support. *(Section 2)*

7. **AHK script GPL exemption claim needs better sourcing** — LICENSES/README.md says it's "explicitly stated" but the actual AHK license page has no explicit exemption. Supported by copyright holder statements, not license text. *(Section 1)*

8. **Lumi Global "QuickSay" product (2016)** — Potential common-law trademark conflict. Different market (mobile surveys) but same name. *(Section 5)*

9. **quicksay.com not controlled** — Registered since 2002 by a third party on Afternic marketplace. Users may navigate there expecting the official site. *(Section 5)*

10. **Copyright holder inconsistency** — LICENSE says "lucid4life", compiler directives say "QuickSay". Should standardize. *(Section 5)*

11. **No W-8BEN filed** — Required to avoid 30% US withholding tax on payments from US-based payment processors. Canada-US treaty reduces to 0-10%. *(Section 6)*

12. **GST/HST registration needed above $30K CAD** — Must register when cumulative sales exceed $30K in any 12-month period. *(Section 6)*

13. **GPT-OSS 20B and Whisper attribution** — Not legally required (accessed via Groq), but recommended as best practice for transparency. *(Section 2)*

14. **BYOK section in privacy policy overstates responsibility shift** — QuickSay is exclusively BYOK but likely remains data controller under PIPEDA. *(Section 4)*

### 🟢 Low Risk (Address When Convenient)

1. **WebView2 and thqby library compliance** — Already properly attributed. No action needed. *(Section 1)*

2. **OpenAI Whisper trademark** — USPTO application suspended since August 2023; not registered. No Canadian registration found. Nominative fair use applies. *(Section 2)*

3. **GPT-OSS 20B license** — Accessed via Groq; end-user integrated product exemption applies; well under 700M MAU threshold. *(Section 2)*

4. **Visual asset licensing** — Logo/icon appear original. Should confirm and document. *(Section 5)*

5. **AI-generated code IP** — Evolving legal landscape. Human-directed AI-assisted code likely protectable. Don't disclose AI use in LICENSE file. *(Section 5)*

6. **CCPA/CPRA compliance** — QuickSay almost certainly below revenue/user thresholds. Low exposure. *(Section 4)*

7. **GDPR exposure** — Low unless actively targeting EU. Prepare if expanding. *(Section 4)*

8. **Accessibility (ADA/AODA)** — Low current risk for indie software. WCAG 2.1 AA recommended for website as best practice. *(Section 6)*

---

## Section 1: Dependencies & Licensing

*Full report: `Legal_Report_Section1_Dependencies.md`*

### FFmpeg — 🔴 Critical

The bundled `ffmpeg.exe` (v8.0.1, gyan.dev essentials build) is compiled with `--enable-gpl --enable-version3 --enable-static`, making it **GPL v3.0 licensed**. GPL codecs enabled include libx264, libx265, and libxvid — none of which QuickSay actually uses (it only records audio).

**"Mere Aggregation" Analysis:** QuickSay invokes ffmpeg.exe as a separate subprocess via command-line execution. Under GPL v3.0 Section 5 and the GNU FAQ, this classifies as "mere aggregation" — meaning the GPL applies only to ffmpeg.exe, not to QuickSay itself. This interpretation is widely held but not conclusively tested in court.

**Strongest Recommendation:** Switch to an **LGPL-only FFmpeg build** (compiled without `--enable-gpl`). QuickSay only uses FFmpeg for audio recording and needs no GPL video codecs. This eliminates the GPL compliance burden entirely.

**Immediate Fix:** If not switching builds, replace the summary GPL text files with full license texts and add a formal written offer for source code.

### AutoHotkey v2 — 🟡 Moderate

GPL v2.0 licensed. The AHK creator has publicly stated scripts can be sold commercially under any license. The GNU FAQ supports this for interpreted languages. However, the compiled .exe bundles the AHK runtime (GPL v2), and the official license page has no explicit script exemption clause — it's based on copyright holder statements and GPL FAQ interpretation.

### WebView2, thqby Libraries — 🟢 Compliant

BSD-style and MIT licenses respectively. Properly attributed in LICENSES directory.

### Sound Files — 🔴 Undocumented

Three bundled .wav files have no documented origin or license.

---

## Section 2: API Terms of Service

*Full report: `Legal_Report_Section2_API_Terms.md`*

### Groq API — BYOK Model 🟢 / Privacy Claims 🔴

**BYOK Compliance:** The BYOK model (users provide their own Groq API keys) likely does not violate Groq's ToS. Each user is an independent Groq customer. QuickSay does not share, transfer, or sublicense its own API key. However, written confirmation from Groq is recommended.

**Free Tier Marketing:** The "8 hours free daily" claim is mathematically accurate (28,800 audio seconds/day) but misleading as presented. It's Groq's offering, not QuickSay's, and can change at any time. Must add disclaimers.

**Data Handling:** 🔴 Groq retains data up to 30 days by default for troubleshooting/abuse monitoring. Zero Data Retention (ZDR) is opt-in, not default. All data processed in the US (GCP). QuickSay's "zero data retention" and "privacy-first" claims are misleading without proper disclosures.

### GPT-OSS 20B — 🟢 Compliant

Accessed via Groq's API. The GPT-OSS 20B license's end-user integrated product exemption applies. Well under the 700M MAU threshold. No revenue restriction. Attribution not strictly required but recommended.

### OpenAI Whisper — 🟢 Low Risk

MIT licensed. No obligations when accessing via API. The "WHISPER" USPTO trademark application has been suspended since August 2023 — not registered. No Canadian registration found. Nominative fair use applies for marketing.

---

## Section 3: Marketing Claims & Comparative Advertising

*Full report: `Legal_Report_Section3_Marketing_Claims.md`*

### Legal Framework

**Canada:** Competition Act ss. 52 (criminal) and 74.01 (civil) prohibit misleading representations. Performance claims require "adequate and proper test." As of June 2025, competitors have private right of action.

**US:** Lanham Act s. 43(a) allows competitors to sue for false advertising in federal court. FTC encourages truthful comparative advertising but requires substantiation.

**Key principle:** Comparative advertising is legal and encouraged — but claims must be accurate, verifiable, and not misleading by omission.

### Critical Findings

| Claim | Actual | Risk |
|-------|--------|------|
| Wispr Flow: $180/year | ~$144/year ($12/mo annual) | 🔴 Wrong |
| Aqua Voice: $120/year | ~$96/year ($8/mo) | 🔴 Wrong |
| Aqua Voice free tier: 4K words/week | 1,000 words total (trial) | 🔴 Wrong |
| 3-year cost: Wispr $540 | Should be ~$432 | 🔴 Wrong |
| 3-year cost: Aqua $360 | Should be ~$288 | 🔴 Wrong |
| "Zero data retention" | Groq retains up to 30 days; local history stored | 🔴 Misleading |
| 6 testimonials | All fabricated placeholders | 🔴 Illegal |

### Trademark Usage

Competitor names (Wispr Flow, Aqua Voice, SuperWhisper) can be used in truthful comparisons under nominative fair use. The SEO comparison pages (`/quicksay-vs-wispr-flow` etc.) are a common and legally defensible practice — but only if the comparisons are accurate.

### Bottom Line

The comparative advertising approach is legally sound. The execution has critical data accuracy problems. Fixes are straightforward: correct pricing, qualify privacy claims, remove fake testimonials.

---

## Section 4: Privacy & Data Protection

*Full report: `Legal_Report_Section4_Privacy.md`*

### Data Flow Discovery

The source code analysis revealed significant discrepancies between the privacy policy and actual app behavior:

| Privacy Policy Claim | Actual Behavior |
|---------------------|-----------------|
| Audio is "not stored by QuickSay" | `save_recordings` defaults to `true`; WAV files saved permanently to `data\audio\` |
| "Does not record which applications you use" | `history.json` stores active window titles (`appContext` field) |
| "Zero data retention" | Local: history, statistics, audio, debug logs stored indefinitely. Remote: Groq retains up to 30 days |
| Data stays on "your machine" | Audio sent to Groq US servers; transcript text sent again for LLM cleanup |

### Local Data Storage (Not Disclosed)

- `data/history.json` — Full dictation history with timestamps, active window titles, durations
- `data/statistics.json` — Per-app usage breakdowns, daily streaks, word counts
- `data/audio/` — Permanent WAV recordings (when save_recordings enabled)
- `debug_log.txt` — API responses, error details
- `payload.json`, `response.txt`, `clean_response.txt` — Last API request/response data

### Privacy Law Gaps

**PIPEDA (Canada):** Multiple compliance gaps — no meaningful consent disclosure for sending audio to US servers, no data controller identification, no user rights (Principle 9), no data retention limits.

**Alberta PIPA:** No breach notification procedure (required by s. 34.1).

**CCPA/CPRA:** Below thresholds — low risk.

**GDPR:** Low exposure unless targeting EU.

### "Privacy-First" Claim Assessment

The claim is defensible only with significant qualification. QuickSay genuinely has no telemetry, no screen capture, no server-side data collection. But audio IS sent to Groq's cloud, local data IS retained, and Groq's retention policies must be disclosed. The current framing overstates the privacy position.

---

## Section 5: Copyright & Intellectual Property

*Full report: `Legal_Report_Section5_Copyright_IP.md`*

### Source Code — 🟢 Low Risk

No evidence of copied code from Stack Overflow, GitHub, or other sources. Third-party libraries (thqby) properly attributed under MIT. Minor gaps: `ComVar.ahk` and `GDI.ahk` lack license headers.

### Assets — 🟡 Medium Risk

Sound files (start.wav, stop.wav, error.wav) have undocumented provenance. Logo SVG has no metadata indicating origin. Website fonts (Outfit, DM Sans, JetBrains Mono) are SIL OFL 1.1 — properly licensed.

### Trademark "QuickSay" — 🟡 Medium Risk

- **Lumi Global** launched a product called "QuickSay" in 2016 (mobile survey tool). Different market but same name — potential common-law trademark conflict.
- No formal trademark registration found in USPTO, CIPO, or WIPO web searches.
- `quicksay.com` is owned by a third party since 2002 (parked on Afternic).
- Recommendation: Register "QuickSay" as a trademark in Canada (CIPO) and the US (USPTO) in Class 9.

### AI-Generated Code IP — 🟡 Medium Risk

- **Canada:** No specific legislation yet. Human-directed AI-assisted code likely protectable.
- **US:** *Thaler v. Perlmutter* (March 2025) affirmed human authorship required but permits AI-assisted works where human provides creative direction.
- OpenAI/Anthropic ToS assign output rights to the user.
- Recommendation: Document human creative contributions. Do NOT disclose AI use in LICENSE file.

### License Compatibility — 🔴 High Risk

The compiled .exe bundles the AHK v2 runtime (GPL v2) inside a binary licensed as MIT. This is a potential conflict. FFmpeg as a separate executable is fine (mere aggregation). Options: add formal GPL source code offer, consider clarifying that the MIT license applies to the script code only while the compiled binary includes GPL components.

---

## Section 6: Payment & Commercial Compliance

*Full report: `Legal_Report_Section6_Commercial.md`*

### Payment Processor Recommendation

| Processor | Recommendation | Key Reason |
|-----------|---------------|------------|
| **LemonSqueezy** | Primary choice | MoR, built-in license keys, digital delivery, 5%+$0.50 fees |
| **Paddle** | Secondary choice | Full MoR, global tax handling, flat 5%+$0.50 |
| **Stripe** | Not recommended | No MoR — developer handles all tax compliance |
| **Gumroad** | Not recommended | 10% fees are nearly double competitors |

A Merchant of Record eliminates sales tax/VAT collection and remittance obligations across all jurisdictions.

### Tax Obligations

- **Canadian GST/HST:** Registration required above $30K CAD/12 months. MoR handles collection.
- **US Sales Tax:** MoR eliminates state-level nexus obligations entirely.
- **W-8BEN:** Must file to avoid 30% US withholding tax. Canada-US treaty reduces to 0-10%.

### Consumer Protection

- **Refund Policy:** Recommend 14-day no-questions-asked refund policy. Current ToS has only a placeholder.
- **Alberta Internet Sales Contract Regulation:** Requires clear cancellation/refund rights disclosure.

### Terms of Service Gaps

The existing ToS is well-written in plain language but missing critical elements:
- Governing law and jurisdiction (Alberta, Canada)
- Intellectual property ownership clause
- Dispute resolution mechanism
- Third-party service disclaimers (Groq dependency)
- BYOK liability terms
- License scope clarity (personal use? commercial use?)
- Age restrictions (recommend 13+)
- Modifications/update clause

### EULA

QuickSay needs a separate EULA (in addition to ToS) with click-through acceptance on first launch, covering:
- API key responsibility
- Data processing disclosure
- Transcription accuracy disclaimer
- Open-source component notices

### Business Structure

Start as sole proprietorship. Consider incorporating when revenue reaches $30K-$100K CAD for tax advantages (11% corporate rate vs. 48% personal rate) and liability protection.

---

## Appendix A: Complete Action Item Checklist

### 🔴 Pre-Launch Critical (Must Do)

- [ ] **Correct Wispr Flow pricing** everywhere: $144/year (or verify current price), not $180/year
- [ ] **Correct Aqua Voice pricing** everywhere: ~$96/year, not $120/year
- [ ] **Correct Aqua Voice free tier**: 1,000 words total trial, not 4K words/week
- [ ] **Recalculate all multi-year cost projections** with correct figures
- [ ] **Fix blog post math errors** (payback period calculations)
- [ ] **Remove all 6 fabricated testimonials** immediately
- [ ] **Fix privacy policy**: Disclose that audio recordings can be saved locally (save_recordings default)
- [ ] **Fix privacy policy**: Disclose that active window titles are stored in history
- [ ] **Fix privacy policy**: Add cross-border data transfer disclosure (Groq US servers)
- [ ] **Fix privacy policy**: Add data controller identification (name, address, contact)
- [ ] **Fix privacy policy**: Add user rights section (access, correction, deletion)
- [ ] **Fix privacy policy**: Add breach notification procedure
- [ ] **Qualify "zero data retention"**: Add Groq's 30-day default retention and ZDR opt-in info
- [ ] **Qualify "Your words. Your machine."**: Acknowledge audio transits through Groq servers
- [ ] **Replace GPL license files** with full official texts (GPL v3.0 ~674 lines, GPL v2.0 ~339 lines)
- [ ] **Add written offers for source code** for FFmpeg and AutoHotkey (valid 3+ years)
- [ ] **Finalize refund policy** (recommend 14-day no-questions-asked)
- [ ] **Add missing ToS sections** (governing law, IP, disputes, third-party disclaimers, BYOK, age)
- [ ] **Create and implement EULA** with click-through on first launch
- [ ] **Document sound file origins** — confirm if original or sourced, add appropriate license
- [ ] **Qualify Wispr Flow screen capture claim** — note it's an optional feature, not constant

### 🟡 Pre-Launch Recommended (Should Do)

- [ ] **Switch to LGPL-only FFmpeg build** (eliminates GPL compliance burden entirely)
- [ ] **Add Groq free tier disclaimers**: "Currently provides up to 8 hours... subject to change by Groq"
- [ ] **Add third-party acknowledgments** section (Groq, Whisper by OpenAI, GPT-OSS 20B)
- [ ] **Choose MoR payment processor** (LemonSqueezy or Paddle)
- [ ] **File W-8BEN** with payment processor to avoid 30% US withholding tax
- [ ] **Register Alberta trade name** (~$60)
- [ ] **Standardize copyright holder** across all files (lucid4life vs. QuickSay)
- [ ] **Add license headers** to ComVar.ahk and GDI.ahk
- [ ] **Qualify AHK script exemption** claim with specific copyright holder citations
- [ ] **Remove red text styling** on competitor negatives in comparison table
- [ ] **Investigate Lumi Global "QuickSay"** for potential trademark conflict
- [ ] **Reach out to Groq** for written BYOK model confirmation
- [ ] **Add "Third-Party Terms" section** to ToS requiring users to comply with Groq's ToS
- [ ] **Consider BYOK data controller analysis** — clarify who is controller in privacy policy

### 🟢 Post-Launch (When Convenient)

- [ ] **Register "QuickSay" trademark** in Canada (CIPO) and US (USPTO), Class 9
- [ ] **Consider acquiring quicksay.com** (currently parked on Afternic)
- [ ] **Build alternative STT provider support** to mitigate Groq dependency
- [ ] **Add voluntary Whisper/GPT-OSS 20B attribution** in About dialog
- [ ] **Implement WCAG 2.1 AA** for the website
- [ ] **Add 13+ age restriction** for COPPA/PIPEDA compliance
- [ ] **Monitor OpenAI "Whisper" trademark** application (USPTO Serial 97815511)
- [ ] **Consider incorporation** when revenue reaches $30K-$100K CAD range

---

## Appendix B: Recommended Legal Documents to Create

### 1. Privacy Policy (Revised)
Current policy needs significant revision. Must add:
- Data controller identification
- Complete data collection inventory (including local storage)
- Cross-border transfer disclosure (Groq → US)
- Groq's data retention policies (30-day default, ZDR option)
- User rights (access, correction, deletion)
- Breach notification procedure
- BYOK implications
- Children's data (13+ restriction)

### 2. Terms of Service (Revised)
Current ToS has good foundation. Must add:
- Governing law: Province of Alberta, Canada
- Dispute resolution mechanism
- IP ownership clause
- Third-party service disclaimers (Groq)
- BYOK liability terms
- License scope (personal/commercial)
- Age restriction (13+)
- Modifications clause
- Finalized refund policy (14-day recommended)

### 3. End User License Agreement (New)
Click-through on first launch. Must cover:
- License grant (perpetual, personal, unlimited devices)
- API key responsibility
- Data processing disclosure
- Transcription accuracy disclaimer
- Open-source component notices (FFmpeg, AutoHotkey)
- Limitation of liability
- Third-party service terms

### 4. Third-Party License Notices (Revised)
Current LICENSES directory is a good start. Must:
- Replace GPL summary files with full texts
- Add formal source code written offers
- Document sound file licensing
- Add version pinning for FFmpeg

### 5. Cookie/Tracking Policy for Website
Minimal — Plausible Analytics is cookieless. Simple disclosure statement suffices.

---

## Appendix C: Sources

### Laws and Regulations
- [Competition Act (Canada), ss. 52, 74.01](https://laws-lois.justice.gc.ca/eng/acts/c-34/)
- [Lanham Act, 15 U.S.C. § 1125(a)](https://www.law.cornell.edu/uscode/text/15/1125)
- [PIPEDA (Canada)](https://laws-lois.justice.gc.ca/eng/acts/p-8.6/)
- [Alberta PIPA](https://www.qp.alberta.ca/documents/Acts/P06P5.pdf)
- [CCPA/CPRA (California)](https://oag.ca.gov/privacy/ccpa)
- [Alberta Consumer Protection Act](https://www.qp.alberta.ca/documents/Acts/C26P3.pdf)
- [Excise Tax Act (GST/HST)](https://laws-lois.justice.gc.ca/eng/acts/e-15/)

### Terms of Service and Policies
- [Groq Services Agreement](https://console.groq.com/docs/legal/services-agreement)
- [Groq Privacy Policy](https://groq.com/privacy-policy)
- [Groq Data Handling](https://console.groq.com/docs/your-data)
- [Groq Rate Limits](https://console.groq.com/docs/rate-limits)
- [GPT-OSS 20B License](https://www.llama.com/llama3_3/license/)
- [Meta Llama Acceptable Use Policy](https://www.llama.com/llama3/use-policy/)
- [OpenAI Whisper MIT License](https://github.com/openai/whisper/blob/main/LICENSE)

### License References
- [GNU GPL v3.0 Full Text](https://www.gnu.org/licenses/gpl-3.0.txt)
- [GNU GPL v2.0 Full Text](https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt)
- [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.en.html)
- [FFmpeg Legal](https://www.ffmpeg.org/legal.html)
- [AutoHotkey v2 License](https://www.autohotkey.com/docs/v2/license.htm)
- [Microsoft WebView2 Distribution](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)

### Trademark Databases
- [USPTO Trademark Search](https://tmsearch.uspto.gov/)
- [CIPO Trademark Search](https://ised-isde.canada.ca/cipo/trade-marks)
- [USPTO Filing 97815511 — "WHISPER" (Suspended)](https://furm.com/trademarks/whisper-97815511)

### Tax and Commercial
- [Canada.ca — GST/HST for digital products](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/digital-economy.html)
- [South Dakota v. Wayfair (2018)](https://www.supremecourt.gov/opinions/17pdf/17-494_j4el.pdf)

### AI and Copyright
- [Thaler v. Perlmutter (2025)](https://www.copyright.gov/rulings-filings/)
- [US Copyright Office — AI-Generated Works](https://www.copyright.gov/ai/)

### Individual Section Reports
- [Section 1: Dependencies & Licensing](Legal_Report_Section1_Dependencies.md)
- [Section 2: API Terms of Service](Legal_Report_Section2_API_Terms.md)
- [Section 3: Marketing Claims & Advertising](Legal_Report_Section3_Marketing_Claims.md)
- [Section 4: Privacy & Data Protection](Legal_Report_Section4_Privacy.md)
- [Section 5: Copyright & Intellectual Property](Legal_Report_Section5_Copyright_IP.md)
- [Section 6: Payment & Commercial Compliance](Legal_Report_Section6_Commercial.md)

---

*This report was generated on February 7, 2026 by a six-agent analysis team. All web searches, pricing verifications, and database lookups were performed on February 6-7, 2026. Laws, terms of service, pricing, and trademark statuses change frequently — re-verify before making legal or business decisions.*

*This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.*
