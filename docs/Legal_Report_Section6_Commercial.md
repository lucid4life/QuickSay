# Section 6: Payment Processing & Commercial Compliance

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

**Prepared:** February 2026
**Product:** QuickSay v1.0 — $29 one-time-purchase voice-to-text Windows application
**Developer Location:** Calgary, Alberta, Canada (sole developer / indie software)
**Target Market:** Canada and United States
**License Model:** Perpetual license — pay once, use forever, free updates
**API Model:** BYOK (Bring Your Own Key) — users supply their own Groq API key

---

## Table of Contents

1. [6A. Payment Processor Comparison](#6a-payment-processor-comparison)
2. [6B. Canadian Tax Obligations](#6b-canadian-tax-obligations)
3. [6C. US Tax Obligations](#6c-us-tax-obligations)
4. [6D. Consumer Protection Requirements](#6d-consumer-protection-requirements)
5. [6E. Terms of Service Audit](#6e-terms-of-service-audit)
6. [6F. EULA Requirements](#6f-eula-requirements)
7. [6G. Business Structure Considerations](#6g-business-structure-considerations)
8. [6H. Accessibility Considerations](#6h-accessibility-considerations)
9. [Summary of Action Items](#summary-of-action-items)

---

## 6A. Payment Processor Comparison

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### Comparison Table for a $29 Digital Product Sold from Canada

| Factor | Gumroad | LemonSqueezy | Stripe (Standard) | Paddle |
|--------|---------|--------------|-------------------|--------|
| **Handles sales tax/VAT?** | Yes (since Jan 2025) | Yes | No (unless using Stripe Managed Payments beta) | Yes |
| **Acts as Merchant of Record?** | Yes | Yes | No (beta MoR in private preview) | Yes |
| **Available in Canada?** | Yes | Yes | Yes | Yes |
| **Refund handling** | Seller-initiated; Gumroad does not refund its fees on refunds | Full refund management; $15 dispute fee deducted from next payout | Seller handles; dispute fees apply | Full refund management included |
| **Provides legal templates?** | No | No | No | No |
| **Fraud protection** | Basic seller controls | AI-powered fraud system; handles chargebacks | Stripe Radar (additional cost for advanced) | Included; handles chargebacks |
| **Fee on $29 sale** | 10% + $0.50 = **$3.40** (~11.7%) | 5% + $0.50 + 1.5% intl = **$1.95–$2.39** (~6.7–8.2%) | 2.9% + $0.30 = **$1.14** (~3.9%) | 5% + $0.50 = **$1.95** (~6.7%) |
| **License key generation?** | Yes (basic) | Yes (built-in, full management) | No (requires third-party integration) | No (requires Keygen or similar integration) |
| **Digital product delivery?** | Yes (file hosting and delivery) | Yes (file hosting and delivery) | No (requires custom implementation) | Yes (basic) |

### Fee Breakdown for a $29 Sale

| Processor | Base Fee | Per-Transaction | International Surcharge | Total (Domestic) | Total (International) |
|-----------|----------|-----------------|------------------------|------------------|----------------------|
| **Gumroad** | 10% ($2.90) | $0.50 | Included | **$3.40** | **$3.40** |
| **LemonSqueezy** | 5% ($1.45) | $0.50 | +1.5% ($0.44) | **$1.95** | **$2.39** |
| **Stripe** | 2.9% ($0.84) | $0.30 | +1.5% ($0.44) + 1% currency conversion ($0.29) | **$1.14** | **$1.87** |
| **Paddle** | 5% ($1.45) | $0.50 | Included | **$1.95** | **$1.95** |

**Note:** Gumroad charges 30% (not 10%) for sales through Gumroad's Discover marketplace.

### Risk Assessment

#### Merchant of Record: Why It Matters

A Merchant of Record (MoR) is the entity legally responsible for the sale. The MoR:
- Appears on customer bank/credit card statements
- Is responsible for collecting and remitting sales tax, VAT, and GST/HST in every jurisdiction
- Handles chargebacks, disputes, and refunds
- Bears legal liability for consumer protection compliance in each market

Without an MoR, the developer is personally responsible for all of these obligations across every US state and Canadian province where sales occur.

#### Recommendation

| Processor | Recommendation | Rationale |
|-----------|---------------|-----------|
| **Paddle** | **Best overall for legal simplicity** | Full MoR, transparent flat pricing, handles all tax compliance globally, includes fraud protection and chargeback handling. Slightly higher fees than Stripe but eliminates all tax/legal complexity. |
| **LemonSqueezy** | **Strong alternative (especially post-Stripe acquisition)** | Full MoR, built-in license key generation and digital delivery (critical for QuickSay), lower fees than Gumroad. The 2026 Stripe Managed Payments integration adds infrastructure reliability. Best balance of features and cost for indie software. |
| **Stripe** | **Not recommended as primary** | Lowest fees but NO Merchant of Record capability (Stripe Managed Payments is still in private beta, limited access). Would require the developer to handle all tax compliance independently across 45+ US states and 13 Canadian provinces/territories. |
| **Gumroad** | **Not recommended** | MoR coverage is good, but 10% fees are nearly double competitors. On a $29 product, Gumroad takes $3.40 vs. $1.95 for Paddle/LemonSqueezy. |

**Primary recommendation: LemonSqueezy** — It offers MoR status (removing tax/legal burden), built-in license key generation (essential for QuickSay's distribution model), digital file delivery, AI fraud protection, and competitive pricing. The 2026 Stripe integration adds payment infrastructure reliability.

**Secondary recommendation: Paddle** — If LemonSqueezy's license key features are not needed or if the developer prefers Paddle's more established enterprise reputation.

---

## 6B. Canadian Tax Obligations

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6B.1 GST/HST on Digital Products

#### Does selling digital products in Canada require collecting GST/HST?

**Yes.** Digital products (including downloadable software) are subject to GST/HST in Canada. Software delivered electronically is classified as a taxable supply under the *Excise Tax Act*.

**Reference:** [Canada.ca — GST/HST for digital-economy businesses](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/digital-economy.html)

#### Registration Thresholds

| Threshold | Amount | Notes |
|-----------|--------|-------|
| **Small supplier threshold** | **$30,000 CAD** over any 12-month period | Below this, GST/HST registration is voluntary |
| **Calculation basis** | Worldwide taxable supplies from all businesses | Includes all revenue, not just Canadian sales |
| **Registration trigger** | Must register within 29 days of exceeding threshold | Retroactive obligation |

**Reference:** [Canada.ca — When to register for and start charging the GST/HST](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/when-register-charge.html)

#### Provincial Rate Variations

Yes, the rate varies significantly by province. The developer must charge the rate applicable to the **buyer's province**, not their own:

| Province/Territory | Tax Type | GST | PST/HST | Total Rate |
|-------------------|----------|-----|---------|------------|
| **Alberta** | GST only | 5% | 0% | **5%** |
| **British Columbia** | GST + PST | 5% | 7% | **12%** |
| **Ontario** | HST | — | — | **13%** |
| **Quebec** | GST + QST | 5% | 9.975% | **~15%** |
| **Nova Scotia** | HST | — | — | **14%** |
| **New Brunswick** | HST | — | — | **15%** |
| **Newfoundland & Labrador** | HST | — | — | **15%** |
| **PEI** | HST | — | — | **15%** |
| **Manitoba** | GST + PST | 5% | 7% | **12%** |
| **Saskatchewan** | GST + PST | 5% | 6% | **11%** |

**Reference:** [Canada.ca — Which rate to charge](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/charge-collect-which-rate.html)

#### If a Merchant of Record Handles This

If using an MoR like LemonSqueezy or Paddle:
- The **MoR collects and remits** sales tax on each transaction — the developer does not need to charge or remit GST/HST on those sales
- However, the developer **may still need to register** for GST/HST if total taxable supplies (including MoR payouts received as business income) exceed $30,000 CAD
- The payouts from the MoR to the developer are a separate transaction that may have GST/HST implications
- **Consult a Canadian tax professional** to determine if MoR payouts constitute taxable supplies requiring registration

**Risk Level:** GST/HST compliance with MoR

- Using an MoR: Tax collection/remittance on sales is handled
- Developer registration: May still be required above $30,000 threshold — **consult a tax professional**

### 6B.2 Alberta Provincial Tax

#### Alberta Has No Provincial Sales Tax — But What About Other Provinces?

Alberta has no PST or HST — only the federal 5% GST applies to Alberta buyers. However:

- If selling to buyers in **other provinces**, the developer (or their MoR) must charge that province's applicable rate
- Without an MoR, the developer would need to register for PST separately in BC, Saskatchewan, and Manitoba, and for QST in Quebec
- **This is a major reason to use an MoR** — it eliminates multi-provincial tax registration requirements

**Reference:** [Alberta.ca — About Tax and Revenue Administration](https://www.alberta.ca/about-tra)

#### Alberta Business Registration Requirements

| Requirement | Details |
|------------|---------|
| **Trade name registration** | Required if operating under any name other than the developer's full legal name (e.g., "QuickSay") |
| **Registration cost** | ~$60 through Alberta Registry |
| **NUANS search** | Not required for sole proprietors but recommended to avoid name conflicts (~$15–50) |
| **Timeline** | Must register within 6 months of starting business operations |
| **Business number** | Required for GST/HST registration — obtain from CRA |

**Risk Level:** Business name registration

- If selling as "QuickSay" (not the developer's legal name), trade name registration is **required**
- Cost is minimal (~$60) but failure to register is a compliance violation

**Reference:** [Alberta.ca — Register a business name](https://www.alberta.ca/register-business-name)

### 6B.3 Income Tax Obligations

#### How Is Digital Product Income Reported?

As a sole proprietor in Alberta:

| Aspect | Details |
|--------|---------|
| **Form** | **T2125** (Statement of Business or Professional Activities) |
| **Filed with** | Personal T1 income tax return |
| **Tax basis** | Net profit (revenue minus allowable expenses) |
| **Industry code** | Software publishers (NAICS 511210) |
| **Website income** | Must enter URLs generating income and percentage of gross from each |
| **CPP contributions** | Self-employed individuals pay both employer and employee portions |

**Deductible expenses** include:
- Computer hardware and software (CCA)
- Internet and phone costs (business portion)
- Home office expenses (if applicable)
- Domain registration, hosting, payment processor fees
- Professional services (accounting, legal)
- Marketing and advertising costs

**Reference:** [Canada.ca — Completing Form T2125](https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/sole-proprietorships-partnerships/report-business-income-expenses/completing-form-t2125.html)

#### Software Sales Income Considerations

- Revenue from software sales is **business income**, not royalty income, for Canadian tax purposes
- If using an MoR, the payouts received are the developer's gross revenue (less MoR fees)
- Quarterly **income tax installments** may be required if tax owing exceeds $3,000 in the current or either of the two preceding tax years
- **No Alberta provincial income tax return** — Alberta income tax is calculated on the federal T1 return

---

## 6C. US Tax Obligations

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6C.1 Sales Tax Nexus

#### Does a Canadian Developer Have US Sales Tax Obligations?

**Potentially yes**, depending on sales volume. Since the 2018 *South Dakota v. Wayfair* decision, **economic nexus** rules apply to foreign sellers.

#### What Is Economic Nexus?

Economic nexus is triggered when a seller exceeds a state's threshold for sales volume or transaction count, **regardless of physical presence**. The landmark *South Dakota v. Wayfair, Inc.* (2018) Supreme Court ruling overturned the previous physical-presence requirement, allowing states to require remote sellers (including foreign sellers) to collect and remit sales tax.

**Key thresholds vary by state:**

| State | Revenue Threshold | Transaction Threshold |
|-------|------------------|-----------------------|
| Most states | $100,000 | 200 transactions |
| California | $500,000 | No transaction threshold |
| New York | $500,000 | 100 transactions |
| Texas | $500,000 | No transaction threshold |

**Reference:** [Sales Tax Institute — Economic Nexus State Guide](https://www.salestaxinstitute.com/resources/economic-nexus-state-guide)

#### Does It Apply to Digital Products from Canada?

**Yes.** Economic nexus rules apply to foreign vendors selling into US states, including digital products. However:

- At $29 per sale, reaching $100,000 in a single state would require ~3,448 sales in that state
- For an indie product, this threshold is unlikely to be reached in individual states in the near term
- **However**, some states have lower thresholds or count transactions, not just revenue

#### How a Merchant of Record Solves This

An MoR (Paddle, LemonSqueezy, Gumroad) **completely eliminates US sales tax obligations** for the developer because:
- The MoR is the seller of record — they have the nexus obligations, not the developer
- The MoR registers, collects, and remits sales tax in all applicable US states
- The developer receives net payouts with no US sales tax filing obligations

**Risk Level:** US sales tax without MoR vs. with MoR

- **Without MoR:** Potentially required to register and file in 45+ states — **extremely high compliance burden**
- **With MoR:** Zero US sales tax obligations for the developer

**Reference:** [TaxConnex — U.S. sales tax requirements for Canadian sellers](https://www.taxconnex.com/blog-/us-sales-tax-requirements-canadian-sellers)

### 6C.2 Withholding Taxes

#### Is There US Withholding Tax on Payments to Canadian Developers?

**Potentially yes.** The default US withholding rate on payments to foreign persons is **30%**. However, the Canada-US Tax Treaty provides significant relief.

#### Canada-US Tax Treaty Relief

| Income Type | Default Rate | Treaty Rate | Article |
|-------------|-------------|-------------|---------|
| **Royalties** (software) | 30% | 0–10% | Article XII |
| **Business profits** | 30% | Generally exempt if no US permanent establishment | Article VII |
| **Other income** | 30% | Varies | Various |

Software license fees paid to a Canadian developer are generally classified as **royalties** under the treaty. With a properly completed W-8BEN form, the withholding rate can be reduced to **0–10%** depending on the classification.

**Key point:** If sales are made through an MoR, the MoR (not the US buyer) is paying the developer, and the payment structure may differ. The MoR handles the buyer-side transaction; the developer receives payouts from the MoR company.

#### Required Forms

| Form | Purpose | Who Files | Validity |
|------|---------|-----------|----------|
| **W-8BEN** | Certificate of Foreign Status (individuals) | Sole proprietor developer | 3 years from signing |
| **W-8BEN-E** | Certificate of Foreign Status (entities) | If incorporated | 3 years from signing |

The form must be submitted to any US entity making payments to the developer (payment processor, MoR, etc.) to claim treaty benefits and avoid the default 30% withholding.

**Risk Level:** US withholding tax

- Without W-8BEN: 30% withheld — **significant revenue loss**
- With W-8BEN + treaty claim: 0–10% — **must file this form with payment processor**

**Reference:** [SAL Accounting — A Guide To Withholding Taxes Under The U.S.-Canada Tax Treaty](https://salaccounting.ca/blog/withholding-tax-us-canada-tax-treaty/)

---

## 6D. Consumer Protection Requirements

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6D.1 Canadian Consumer Protection (Alberta)

#### Alberta Consumer Protection Act

The **Consumer Protection Act** (RSA 2000, c C-26.3) and the **Internet Sales Contract Regulation** (Alta Reg 81/2001) govern online sales in Alberta.

**Key requirements for internet sales:**

| Requirement | Details |
|------------|---------|
| **Pre-purchase disclosure** | Must clearly disclose: seller identity, product description, total price (including taxes), delivery terms, cancellation/refund policy |
| **Confirmation** | Must provide written confirmation of the contract within 15 days |
| **Cancellation rights** | Consumer may cancel if required disclosures were not provided |
| **Refund timeline** | Supplier must refund all consideration within 15 days of cancellation |

**Reference:** [CanLII — Internet Sales Contract Regulation](https://www.canlii.org/en/ab/laws/regu/alta-reg-81-2001/latest/alta-reg-81-2001.html)

#### Is "No Refunds" Legal for Digital Products in Alberta?

**Risky.** While Alberta law does not explicitly prohibit "no refund" policies for digital products:

- If the product is **defective or materially different** from what was described, the consumer has rights regardless of stated policy
- The **Internet Sales Contract Regulation** requires disclosure of the refund policy before purchase
- A "no refunds" policy that does not carve out exceptions for defective products or non-delivery may be **unenforceable**
- Courts generally look unfavorably on absolute "no refund" terms, especially where the consumer had no opportunity to test the product before purchase

**Risk Level:** "No refund" policy for digital software

- A blanket "no refunds" policy is legally questionable and damages consumer trust
- Recommendation: Offer a **reasonable refund window** (14–30 days) with clear conditions

#### Cooling-Off Periods

Alberta's **Direct Sales Cancellation and Exemption Regulation** provides a 10-day cooling-off period for direct sales contracts. For internet sales, the cancellation rights are tied to disclosure compliance rather than a fixed cooling-off period.

**Reference:** [Alberta.ca — Consumer Bill of Rights](https://www.alberta.ca/consumer-bill-of-rights)

### 6D.2 US Consumer Protection

#### FTC Regulations on Digital Product Sales

The Federal Trade Commission (FTC) does not mandate refunds for digital products specifically, but requires:

| Requirement | Details |
|------------|---------|
| **Clear disclosure** | Refund/return policy must be clearly posted before purchase |
| **Accurate advertising** | Product must perform as advertised; misleading claims create refund liability |
| **Delivery obligations** | Mail, Internet, or Telephone Order Merchandise Rule requires delivery within stated timeframe or offer of refund |
| **Subscription rules** | FTC "Click-to-Cancel" rule (effective July 2025) requires easy cancellation — not directly applicable to one-time purchases but relevant if any subscription features are added |

**Key point:** While there is no federal law requiring refund acceptance for digital products, a product that **does not work as advertised** creates FTC liability regardless of stated refund policy.

**Reference:** [FTC — Consumer Refunds](https://www.ftc.gov/terms/consumer-refunds)

#### State-Level Variations

Some states have additional consumer protection laws:
- **California:** Strong consumer protection; unfair business practices statute (Bus. & Prof. Code 17200) is broadly interpreted
- **New York:** General Business Law 349 prohibits deceptive acts
- Some states have enacted **Digital Goods Consumer Protection Acts** requiring specific disclosures about technical restrictions

### 6D.3 Refund Policy Recommendation

#### Current State

The existing Terms of Service states: *"Our refund policy details will be finalized before launch."* This **must be resolved before launch**.

#### Recommended Refund Policy

Based on legal requirements, industry standards, and consumer trust considerations:

| Element | Recommendation | Rationale |
|---------|---------------|-----------|
| **Refund window** | **14 days** from purchase | Balances consumer protection with digital product reality; aligns with EU standards (for future expansion) |
| **Conditions** | Full refund, no questions asked within 14 days | Reduces chargeback risk; builds trust; simplifies administration |
| **After 14 days** | Refunds considered on case-by-case basis for defective product | Meets consumer protection obligations for faulty goods |
| **Process** | Email hello@quicksay.app with order number | Simple, clear, documented |
| **MoR handling** | Let MoR (LemonSqueezy/Paddle) process refunds | Leverages their refund infrastructure |

**Why 14 days (not 30)?**
- A $29 product is low enough that dissatisfied customers will simply not re-engage rather than request refunds
- 14 days provides adequate time to evaluate the product
- Aligns with EU consumer protection standards (14-day right of withdrawal) if the developer later expands to European markets
- Most indie software products ($20–50 range) offer 14–30 day windows

**Risk Level:** Refund policy

- Current "TBD" state: Must be finalized before launch
- Recommended 14-day window reduces legal risk across jurisdictions
- "No refund" alternative would be higher risk and lower consumer trust

---

## 6E. Terms of Service Audit

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### Current Coverage Analysis

The existing Terms of Service at `/mnt/c/QuickSay/Website/src/pages/terms.astro` covers 8 sections:

| Section | Status | Assessment |
|---------|--------|------------|
| 1. License | Covered | Adequate but needs expansion |
| 2. Refund Policy | **Incomplete** | Placeholder — must be finalized |
| 3. Updates | Covered | Good — clear free updates promise |
| 4. Disclaimer | Covered | Adequate for Groq dependency |
| 5. Limitation of Liability | Covered | Good — $29 cap is reasonable |
| 6. No Warranty on Uptime | Covered | Good — third-party dependency disclaimer |
| 7. Acceptable Use | Covered | Minimal but adequate |
| 8. Termination | Covered | Good — perpetual with third-party caveat |

### What's Currently Missing

The following elements should be added before launch:

#### Missing (High Priority)

| Element | Risk Level | Why It's Needed |
|---------|-----------|-----------------|
| **Governing law and jurisdiction** | High | Must specify Alberta, Canada as governing law; without this, disputes default to buyer's jurisdiction |
| **Dispute resolution** | High | Should specify whether disputes go to Alberta courts or arbitration |
| **Intellectual property ownership** | High | Must clarify that the software is licensed, not sold; developer retains all IP |
| **Third-party service disclaimer (Groq)** | High | Must explicitly disclaim liability for Groq API availability, pricing changes, ToS changes |
| **BYOK liability** | High | Must address that the user is responsible for their own API key, usage costs, and compliance with Groq's terms |
| **Data handling / privacy reference** | High | Must reference the Privacy Policy and explain what data is processed |

#### Missing (Medium Priority)

| Element | Risk Level | Why It's Needed |
|---------|-----------|-----------------|
| **License scope** | Medium | "Personal use" is stated but commercial use is not addressed — can businesses use it? |
| **Number of devices/installations** | Medium | Currently says "unlimited personal Windows machines" — should clarify what "personal" means |
| **Export compliance** | Medium | Standard clause for software sold internationally |
| **Age restrictions** | Medium | Should state minimum age (13+ to comply with COPPA/PIPEDA guidance) |
| **Modifications to terms** | Medium | Must explain how users are notified of ToS changes |

#### Missing (Lower Priority)

| Element | Risk Level | Why It's Needed |
|---------|-----------|-----------------|
| **Transferability of license** | Low | Can the license be transferred to another person? Industry standard is non-transferable |
| **Severability clause** | Low | Standard clause — if one provision is invalid, the rest survive |
| **Entire agreement clause** | Low | Standard clause — ToS is the complete agreement |
| **Open-source acknowledgment** | Low | Should reference FFmpeg and other open-source components used |
| **Contact information** | Low | Currently only email; may need to add mailing address for some jurisdictions |

### Specific Section Assessments

#### Limitation of Liability (Section 5) — Adequate but Could Be Stronger

Current text: *"QuickSay is provided 'as is.' To the maximum extent permitted by law, we are not liable for any indirect, incidental, or consequential damages..."*

**Assessment:** This is a reasonable limitation. The $29 liability cap is appropriate. However, consider adding:
- Exclusion of **special and punitive damages**
- Explicit statement that the limitation applies **regardless of the legal theory** (contract, tort, negligence)
- Acknowledgment that **some jurisdictions do not allow limitation of liability**, and in those cases, liability is limited to the maximum extent permitted

#### Warranty Disclaimer (Section 4) — Needs Enhancement

Current text adequately disclaims transcription accuracy but should add:
- Explicit **"AS IS" and "AS AVAILABLE"** warranty disclaimer (using these legal terms of art)
- Disclaimer of **implied warranties of merchantability and fitness for a particular purpose**
- Statement that the developer does not warrant the software will be **error-free, secure, or uninterrupted**

### Recommended Additions (Draft Language)

#### Governing Law and Jurisdiction

> These Terms shall be governed by and construed in accordance with the laws of the Province of Alberta and the federal laws of Canada applicable therein, without regard to conflict of law principles. Any dispute arising from these Terms or your use of QuickSay shall be subject to the exclusive jurisdiction of the courts of the Province of Alberta, sitting in Calgary.

#### Intellectual Property

> QuickSay and all associated intellectual property rights remain the exclusive property of [Developer Name]. Your purchase grants you a license to use the software; it does not transfer ownership of the software or any intellectual property rights. You may not reverse engineer, decompile, disassemble, or otherwise attempt to derive the source code of QuickSay.

#### Age Restriction

> You must be at least 13 years of age to purchase or use QuickSay. If you are under 18, you represent that your parent or legal guardian has reviewed and agreed to these Terms on your behalf.

---

## 6F. EULA Requirements

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6F.1 EULA vs. ToS — Does QuickSay Need Both?

**Yes, QuickSay should have both**, because:

| Document | Purpose | Governs |
|----------|---------|---------|
| **Terms of Service** | Governs the **purchase transaction** and **website use** | The purchase, refund policy, website terms, general legal framework |
| **EULA** | Governs the **use of the installed software** | Software license grant, usage restrictions, IP protection, third-party components |

QuickSay is a **locally installed desktop application** (not SaaS), which means a EULA is the appropriate legal instrument for governing software use. The ToS on the website governs the purchase and website interaction.

**Key distinction:** A user encounters the ToS when purchasing. They encounter the EULA when installing/first running the software.

### 6F.2 What the EULA Should Cover

| Section | Content |
|---------|---------|
| **License grant** | Personal, non-exclusive, non-transferable, perpetual license to use on unlimited personal Windows machines |
| **License restrictions** | No redistribution, reverse engineering, decompilation, sublicensing, or resale |
| **Intellectual property** | All rights reserved; software is licensed, not sold |
| **Third-party components** | FFmpeg (LGPL), Groq API, other open-source components — reference LICENSES file |
| **API key responsibility** | User is solely responsible for their Groq API key, associated costs, and Groq ToS compliance |
| **Data processing** | What data the software sends to Groq's API; reference Privacy Policy |
| **No warranty** | Software provided "as is"; no warranty on transcription accuracy |
| **Limitation of liability** | Mirror the ToS liability cap of $29 |
| **Termination** | License is perpetual but can be terminated for ToS/EULA violations |
| **Governing law** | Alberta, Canada |
| **Updates** | Developer may update software; EULA applies to updates |
| **Export compliance** | Standard clause — user agrees not to export in violation of applicable laws |

### 6F.3 Specific EULA Considerations for QuickSay

#### Groq API Key and Associated Risks

The EULA should include language such as:

> QuickSay requires a Groq API key to function. You are solely responsible for obtaining, securing, and paying for your Groq API key. QuickSay does not store your API key on any server — it is stored locally on your device using Windows DPAPI encryption. You agree to comply with Groq's Terms of Service when using QuickSay. We are not responsible for any charges incurred through your Groq API usage, any changes to Groq's pricing or availability, or any actions taken by Groq regarding your API key or account.

#### Data Sent to Third-Party APIs

> When you use QuickSay's transcription features, your audio recordings are sent to Groq's servers for processing via their Whisper API. Transcribed text may also be sent to Groq's GPT-OSS 20B model for text cleanup. We do not control how Groq processes, stores, or retains your data. Please review Groq's Privacy Policy for details on their data handling practices.

#### No Warranty on Transcription Accuracy

> Transcription accuracy depends on numerous factors including audio quality, background noise, accent, speaking speed, and the performance of Groq's AI models. We do not warrant that transcriptions will be accurate, complete, or error-free. You should review all transcribed text before relying on it for any purpose.

#### FFmpeg and Open-Source Components

> QuickSay includes FFmpeg, which is licensed under the GNU Lesser General Public License (LGPL) version 2.1 or later. The FFmpeg source code and applicable license terms are available at ffmpeg.org. A complete list of open-source components and their licenses is included in the LICENSES directory distributed with QuickSay.

### 6F.4 How the EULA Should Be Presented

| Method | Recommendation | Notes |
|--------|---------------|-------|
| **Click-through during first launch** | **Recommended** | Most legally defensible; user must actively accept before using software |
| **Installer dialog** | Good alternative | Present during installation with "I Accept" checkbox |
| **In-app accessible** | Also needed | Always available via Help menu or About dialog |
| **Website** | Also needed | Host full EULA text on website for review before purchase |

**Best practice:** Present the EULA on **first launch** of the application with an "I Accept" / "I Decline" dialog. Log the acceptance (date/time) locally. This creates the strongest evidence of user consent.

---

## 6G. Business Structure Considerations

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6G.1 Sole Proprietor vs. Incorporation

| Factor | Sole Proprietorship | Alberta Corporation |
|--------|-------------------|-------------------|
| **Setup cost** | $60 (trade name registration) | $300–500 (incorporation fees + NUANS) |
| **Annual costs** | Minimal | ~$50/year (annual return filing) |
| **Liability** | **Unlimited personal liability** — personal assets at risk | **Limited liability** — personal assets generally protected |
| **Tax filing** | T1 personal return + T2125 | T2 corporate return + personal T1 for salary/dividends |
| **Tax rate** | Personal marginal rate (up to ~48% in Alberta) | Small business rate: ~11% combined (federal + Alberta) on first $500K |
| **Income splitting** | Not available | Can pay dividends to family shareholders |
| **Complexity** | Simple | More complex bookkeeping, separate bank accounts, annual filings |
| **Perception** | Less professional | More professional; "Inc." or "Ltd." in name |

### 6G.2 Liability Analysis for QuickSay

**Liability risks specific to QuickSay:**

| Risk | Scenario | Impact |
|------|----------|--------|
| **Transcription errors** | Inaccurate transcription causes user harm (medical, legal, financial context) | Potential lawsuit; personal assets at risk as sole proprietor |
| **Data breach** | API key or audio data compromised | Privacy liability; potential regulatory fines |
| **Third-party API failure** | Groq changes terms, increases prices, or discontinues service | Customer complaints; potential refund obligations |
| **Software defects** | Bug causes data loss or system issues | Product liability; personal assets at risk |

**Risk assessment:**
- The $29 price point and limitation of liability clause significantly reduce financial exposure
- Using an MoR further shields the developer from payment-related liability
- The BYOK model reduces data handling liability (no centralized API key storage)
- However, **personal liability for a software product is a real risk** as a sole proprietor

### 6G.3 Recommendation

| Revenue Stage | Recommendation | Rationale |
|--------------|---------------|-----------|
| **Pre-launch / Early (< $30K revenue)** | **Sole proprietorship** | Minimal setup cost; tax simplicity; low revenue doesn't justify incorporation costs |
| **Growing ($30K–100K revenue)** | **Consider incorporating** | GST/HST registration triggered anyway; liability protection becomes more important as user base grows |
| **Established (> $100K revenue)** | **Strongly recommend incorporation** | Tax advantages (11% vs. 48% marginal rate); liability protection essential; income splitting available |

**Immediate action:** Register trade name "QuickSay" as a sole proprietorship (~$60). Plan to incorporate when revenue justifies it or when the liability risk profile increases.

**Reference:** [Calgary Legal Guidance — Things to Consider When Organizing a Business](https://clg.ab.ca/index.php/legal-help/free-legal-info-formerly-dial-a-law/business-employment-wcb-intellectual-property/things-to-consider-when-organizing-a-business/)

### 6G.4 Alberta Business Registration Requirements

| Step | Details | Cost |
|------|---------|------|
| 1. Trade name search | NUANS search (recommended, not required for sole props) | $15–50 |
| 2. Register trade name | Declaration of Trade Name through Alberta Registry | ~$60 |
| 3. Business number | Apply for BN from CRA (required for GST/HST if applicable) | Free |
| 4. GST/HST registration | Required if taxable supplies exceed $30,000/year | Free |
| 5. Municipal business license | Check Calgary requirements for home-based businesses | Varies |

---

## 6H. Accessibility Considerations

> **This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.**

### 6H.1 Accessibility Law Requirements

#### Canadian Laws

| Law | Applies to QuickSay? | Details |
|-----|----------------------|---------|
| **Accessible Canada Act** (ACA) | **No** (currently) | Applies to federally regulated organizations (banks, telecoms, transportation, federal government). Does **not** apply to provincial businesses or indie software developers |
| **AODA** (Ontario) | **No** | Ontario-specific; only applies to organizations operating in Ontario with 50+ employees |
| **Alberta Human Rights Act** | **Indirectly** | Prohibits discrimination but does not have specific digital accessibility requirements for software products |
| **Accessible Canada Regulations (2025 amendments)** | **No** | New digital accessibility requirements (CAN/ASC-EN 301 549) apply to federally regulated entities only, with Phase 1 enforcement by December 2027 |

**Reference:** [Level Access — Canadian Accessibility Regulations & 2025 ACA Amendments](https://www.levelaccess.com/blog/canadian-accessibility-laws/)

#### US Laws

| Law | Applies to QuickSay? | Details |
|-----|----------------------|---------|
| **ADA** (Americans with Disabilities Act) | **Unlikely but possible** | Primarily applies to "places of public accommodation" (Title III). Courts are split on whether websites and software qualify. Risk increases with US market presence |
| **Section 508** | **No** | Applies only to federal government procurement |
| **State accessibility laws** | **Varies** | Some states (California, New York) have broader accessibility requirements |

**Risk Level:** Accessibility law compliance

- Currently low legal risk for an indie software product
- Voice-to-text software is inherently an **accessibility tool** — it helps users who have difficulty typing
- However, the software's UI itself should be reasonably accessible (keyboard navigation, screen reader compatibility)
- The **website** should meet WCAG 2.1 Level AA as a best practice

### 6H.2 Website WCAG Standards

While not legally required for an indie developer's website in Alberta, meeting **WCAG 2.1 Level AA** is:

| Consideration | Details |
|--------------|---------|
| **Legal risk reduction** | Reduces risk of accessibility-related complaints, especially from US users |
| **Market advantage** | Voice-to-text software marketed to accessibility-conscious users should have an accessible website |
| **EU expansion** | If ever expanding to EU, European Accessibility Act (EAA) takes effect June 2025, requiring WCAG 2.1 Level AA for many digital products |
| **SEO benefit** | Accessible websites tend to perform better in search rankings |

**Recommended WCAG 2.1 Level AA checklist for the QuickSay website:**
- Sufficient color contrast ratios (4.5:1 for normal text)
- Alt text on all images
- Keyboard navigation support
- Proper heading hierarchy
- Form labels and error messages
- Skip navigation links
- Responsive design

### 6H.3 Age Restrictions

#### COPPA (US — Children under 13)

| Factor | Assessment |
|--------|------------|
| **Does COPPA apply?** | Only if QuickSay is **directed at children** or **knowingly collects data from children under 13** |
| **Is QuickSay directed at children?** | No — it is a general-purpose productivity tool |
| **Does it collect data from children?** | In BYOK model, the developer does not collect user data; however, audio is sent to Groq's API |
| **Recommendation** | Add minimum age of **13** in ToS/EULA to explicitly exclude COPPA scope |

**Reference:** [TermsFeed — Child Privacy Laws](https://www.termsfeed.com/blog/child-privacy-laws/)

#### Canadian Equivalents (PIPEDA)

| Factor | Assessment |
|--------|------------|
| **PIPEDA approach** | No specific children's privacy law; OPC guidance treats under-13 data as highly sensitive |
| **Meaningful consent** | OPC position: children under 13 generally cannot provide meaningful consent |
| **Recommendation** | Same as COPPA — set minimum age at 13; require parental consent for users under 18 |

**Reference:** [OPC — Collecting from kids? Ten tips for services aimed at children and youth](https://www.priv.gc.ca/en/privacy-topics/business-privacy/bus_kids/02_05_d_62_tips/)

---

## Summary of Action Items

### Before Launch (Must-Do)

| Priority | Action | Risk If Skipped |
|----------|--------|-----------------|
| 1 | **Choose and integrate payment processor** (LemonSqueezy or Paddle recommended) — MoR is critical | Developer personally liable for tax collection/remittance in 50+ jurisdictions |
| 2 | **Finalize refund policy** — recommend 14-day no-questions-asked refund | Current ToS has placeholder text; launches without defined refund terms |
| 3 | **Register "QuickSay" trade name** in Alberta (~$60) | Operating under unregistered trade name is a compliance violation |
| 4 | **Add missing ToS sections**: governing law, IP ownership, dispute resolution, third-party disclaimers, BYOK liability, age restriction, modifications clause | Disputes default to buyer's jurisdiction; IP rights unclear; no third-party disclaimers |
| 5 | **Create and implement EULA** with click-through acceptance on first launch | No enforceable license agreement for the installed software |
| 6 | **File W-8BEN** with chosen payment processor | 30% US withholding tax on payments instead of 0–10% |

### After Launch / Revenue-Dependent

| Priority | Action | Trigger |
|----------|--------|---------|
| 7 | **Register for GST/HST** with CRA | Taxable supplies exceed $30,000 CAD in any 12-month period |
| 8 | **Consider incorporation** (Alberta corporation) | Revenue exceeds $30K–100K; or if liability concerns increase |
| 9 | **Review US state tax obligations** | If any individual state sales exceed $100K or 200 transactions |
| 10 | **WCAG 2.1 Level AA audit** of website | Before significant US market push |

### Ongoing

| Action | Frequency |
|--------|-----------|
| **Review ToS/EULA** for needed updates | Annually or after significant feature changes |
| **Monitor MoR compliance** | Quarterly — ensure tax handling is current |
| **Track revenue by jurisdiction** | Monthly — monitor GST/HST and US nexus thresholds |
| **Renew W-8BEN** | Every 3 years |
| **File T2125 with T1** | Annually (April 30 deadline) |

---

## Risk Summary Dashboard

| Area | Current Risk | With Recommended Actions |
|------|-------------|-------------------------|
| **Sales tax compliance (Canada)** | Medium — no MoR, no GST/HST registration | Low — MoR handles collection/remittance |
| **Sales tax compliance (US)** | High — no MoR means potential 45+ state obligations | Low — MoR eliminates US tax obligations |
| **Consumer protection** | High — no refund policy defined | Low — 14-day refund window + MoR handling |
| **Terms of Service** | Medium — missing critical sections | Low — add governing law, IP, disclaimers |
| **EULA** | High — no EULA exists | Low — click-through EULA on first launch |
| **Business registration** | Medium — trade name may be unregistered | Low — register trade name (~$60) |
| **US withholding tax** | High — 30% default rate | Low — W-8BEN reduces to 0–10% |
| **Accessibility** | Low — indie product, not federally regulated | Low — maintain reasonable accessibility |
| **Age restrictions** | Low — general-purpose tool | Low — add 13+ requirement to ToS/EULA |
| **Business structure** | Medium — unlimited personal liability | Low — incorporate when revenue justifies it |

---

*Report prepared February 2026. All legal research reflects laws and regulations as of this date. Laws, thresholds, and requirements may change. This report is for informational purposes only and does not constitute legal advice.*
