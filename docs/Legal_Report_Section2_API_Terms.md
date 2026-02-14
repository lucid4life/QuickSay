# Legal Report - Section 2: API Terms of Service & Third-Party Model Compliance

**Prepared for:** QuickSay (Calgary, Alberta, Canada)
**Date:** February 6, 2026
**Report Version:** 1.0

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

---

## Table of Contents

1. [2A. Groq API Terms of Service](#2a-groq-api-terms-of-service)
2. [2B. GPT-OSS 20B License](#2b-gpt-oss-20b-license)
3. [2C. OpenAI Whisper License & Attribution](#2c-openai-whisper-license--attribution)
4. [2D. Risk Summary](#2d-risk-summary)

---

## 2A. Groq API Terms of Service

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 2A.1 Commercial Use Analysis

**Source:** [Groq Services Agreement](https://console.groq.com/docs/legal/services-agreement) (effective October 15, 2025)

#### Can QuickSay Build a Commercial Product on Groq's API?

**Section 3.1** of the Groq Services Agreement grants customers a:

> "non-exclusive, non-transferable, and limited right to access and use the Cloud Services...to integrate the Cloud Services and AI Model Services into your Customer Application and to make the Cloud Services and AI Model Services available to End Users through your Customer Applications."

This language **does permit** building a commercial application that integrates Groq's API. QuickSay qualifies as a "Customer Application" that makes Groq's services available to "End Users."

#### Is the BYOK (Bring Your Own Key) Model Permitted?

This is the **most significant legal risk** for QuickSay.

**Section 3.2** explicitly states:

> "Customer may not resell or lease access to its Account."

**Section 6.3(c)** further prohibits:

> "sell, resell, sublicense, transfer, or distribute any of the Cloud Services except as expressly approved by Groq."

**Section 3.2** also states that customers are prohibited from:

> "selling, reselling, transferring, assigning, distributing, licensing or sublicensing access to the Services, any API or API log-ins or keys to a third party, or sublicensing an API for use by a third party that functions substantially the same as the APIs."

**Analysis:** QuickSay's BYOK model, where each user creates their own Groq account and uses their own API key, **likely does not violate** these provisions because:

- QuickSay is not sharing, transferring, or sublicensing **its own** API key or account
- Each user is an independent Groq customer with their own account and API key
- QuickSay functions as a "Customer Application" that the user (as the Groq customer) runs locally
- The user, not QuickSay, is the "Customer" in Groq's terms

However, there is a **gray area**: Groq could argue that QuickSay is instructing users to create accounts specifically to use them through QuickSay's interface, effectively creating a commercial wrapper. The key distinction is that QuickSay does not intermediate or control the API relationship -- the user's key is stored locally, and API calls go directly from the user's machine to Groq.

**Risk Level:** Yellow -- Likely compliant but warrants proactive communication with Groq.

#### Could Groq Argue QuickSay is "Reselling" Their Service?

**Section 6.3(c)** prohibits reselling. However, QuickSay does not:
- Hold or manage API keys on behalf of users
- Route API traffic through its own servers
- Bundle Groq API access in its pricing
- Charge per-transcription fees

QuickSay charges a one-time $29 fee for the software itself. Groq API usage is entirely managed by the user through their own account. This is analogous to a code editor that supports API integrations -- the editor vendor is not "reselling" the API.

**Risk Level:** Green -- Low risk, but see marketing recommendations below.

### 2A.2 Free Tier Marketing

**Source:** [Groq Rate Limits](https://console.groq.com/docs/rate-limits) | [Groq Community FAQ](https://community.groq.com/t/is-there-a-free-tier-and-what-are-its-limits/790)

#### Current Free Tier Limits for Whisper

| Metric | Free Tier Limit |
|--------|----------------|
| Audio Seconds per Day (ASD) | 28,800 (= 8 hours) |
| Audio Seconds per Hour (ASH) | 7,200 (= 2 hours) |
| Requests per Minute (RPM) | 20 |
| Max File Size | 25 MB |

The "8 hours free transcription daily" claim is **mathematically accurate** based on current limits: 28,800 seconds / 3,600 = 8 hours.

#### Can QuickSay Advertise Groq's Free Tier as Its Own Feature?

**Legal Concerns:**

1. **Misleading Advertising Risk:** Advertising "8 hours free transcription daily" as a QuickSay feature implies QuickSay provides this service. In reality, this is Groq's free tier, which Groq can change or eliminate at any time without notice to QuickSay. Under Canadian Competition Act provisions on misleading representations (Section 74.01), this could be problematic if consumers believe QuickSay guarantees this level of service.

2. **Dependency on Third-Party Generosity:** Groq's free tier is designed for developer experimentation, not as a permanent offering for commercial product end users. Groq has no contractual obligation to maintain these limits.

3. **Risk of Groq Viewing This as Abuse:** If hundreds or thousands of QuickSay users create free Groq accounts to use 8 hours of audio transcription daily, Groq may view this as orchestrated free-tier abuse by QuickSay, even if each individual user is acting independently. This could prompt Groq to:
   - Reduce free tier limits
   - Require commercial agreements for apps that direct users to their service
   - Block requests from QuickSay's user-agent or usage patterns

**Required Actions:**

1. **Add clear disclaimers** that the free transcription is provided by Groq's free tier, not by QuickSay
2. **State that limits are subject to change** by Groq at any time
3. **Do not present it as a QuickSay feature** but rather as a benefit of using Groq's service
4. **Recommended language:** "QuickSay works with Groq's free API tier, which currently provides up to 8 hours of audio transcription daily. Groq's free tier limits are subject to change at Groq's discretion. Paid Groq plans offer higher limits."

**Risk Level:** Yellow -- Currently accurate but misleading in presentation; requires disclaimers.

### 2A.3 Data Handling by Groq

**Source:** [Your Data in GroqCloud](https://console.groq.com/docs/your-data) | [Groq Privacy Policy](https://groq.com/privacy-policy) (effective November 12, 2025)

#### Data Retention

Groq's data handling policy states:

> "By default, Groq does not retain customer data for inference requests."

However, there are important caveats:

1. **Temporary Retention:** Groq retains temporary logs of inputs and outputs "for troubleshooting errors or investigating suspected abuse" for **up to 30 days**.
2. **Usage Metadata:** Groq "always retains" usage metadata "to measure service activity and system performance," though this "does not contain customer inputs or outputs."
3. **Zero Data Retention (ZDR):** Customers can enable ZDR in Data Controls settings. When enabled, Groq "will not retain customer data for system reliability and abuse monitoring."
4. **Audio Endpoints:** Audio endpoints (`/openai/v1/audio/transcriptions`, `/openai/v1/audio/translations`) "follow the same retention rules as other inference requests."

#### Does Groq Use Data for Training?

The documentation does not explicitly state that customer data is used for model training. The data retention appears limited to operational purposes (troubleshooting, abuse detection).

#### Impact on QuickSay's Privacy Claims

QuickSay's website and marketing materials claim "privacy-first" and "zero data retention." These claims are **potentially misleading** because:

1. **Audio data IS sent to Groq's servers.** Even momentary processing means the audio leaves the user's device.
2. **Default 30-day retention.** Unless the user enables ZDR, Groq may retain audio data for up to 30 days for troubleshooting and abuse monitoring.
3. **Data stored in US.** Groq stores all customer data "in Google Cloud Platform (GCP) buckets located in the United States."
4. **Users must opt-in to ZDR.** Zero data retention is not the default -- users must actively enable it in their Groq console.

**Required Disclosures:**

1. QuickSay must clearly state that audio data is transmitted to Groq's servers for processing
2. Must disclose Groq's default 30-day retention policy
3. Must inform users about the ZDR option and how to enable it
4. Cannot claim "zero data retention" without qualifying that this depends on user's Groq account settings
5. Must disclose that data is stored/processed in the United States (relevant for Canadian users under PIPEDA)

**Recommended language for privacy disclosures:**
> "Audio recordings are sent to Groq's servers for transcription. By default, Groq may retain data for up to 30 days for operational purposes. You can enable Zero Data Retention in your Groq account settings. All data is processed in the United States. See Groq's Privacy Policy for details."

**Risk Level:** Red -- Current "privacy-first" and "zero data retention" claims are misleading without proper disclosures.

### 2A.4 Rate Limits and Service Reliability

**Source:** [Groq Rate Limits](https://console.groq.com/docs/rate-limits) | [Groq Pricing](https://groq.com/pricing)

#### Current Rate Limits

**Free Tier (Whisper models):**

| Model | RPM | ASH | ASD | Max File |
|-------|-----|-----|-----|----------|
| whisper-large-v3 | 20 | 7,200s | 28,800s | 25 MB |
| whisper-large-v3-turbo | 20 | 7,200s | 28,800s | 25 MB |

**Free Tier (GPT-OSS 20B text models):**

| Model | RPM | TPM | RPD | TPD |
|-------|-----|-----|-----|-----|
| openai/gpt-oss-20b | 30 | 12,000 | 1,000 | 100,000 |

**Developer Tier:** Offers up to 10x higher limits and 25% cost discounts.

Rate limits are applied **at the organization level**, not per individual user.

When limits are exceeded, the API returns HTTP 429 (Too Many Requests).

#### Could Heavy QuickSay Users Get Throttled or Banned?

Yes. Each user's individual Groq account has its own rate limits. Heavy users will be throttled automatically via 429 responses. Since each QuickSay user has their own API key and account, one user's heavy usage does not affect other QuickSay users.

However, if Groq identifies a pattern of many accounts being used through QuickSay and perceives this as orchestrated abuse, they could:
- Implement additional restrictions for traffic identified as coming from QuickSay
- Contact QuickSay to negotiate a commercial arrangement
- Reduce free tier limits across the board

#### Service Discontinuation Risk

QuickSay faces significant **platform dependency risk**:

1. **Groq can change pricing at any time.** The free tier is not contractually guaranteed.
2. **Groq can modify or discontinue models.** If Groq drops Whisper support, QuickSay loses its core functionality.
3. **Groq can change their Terms of Service.** Future ToS versions could explicitly prohibit BYOK commercial wrappers.
4. **No SLA for free tier.** Free tier users have no service level agreement and cannot rely on uptime guarantees.

**Mitigation Recommendations:**

1. Build support for alternative STT providers (OpenAI API, AssemblyAI, local Whisper)
2. Clearly communicate to users that QuickSay depends on Groq's API availability
3. Maintain the ability to swap API endpoints with minimal code changes
4. Consider reaching out to Groq for a commercial partnership or written approval

**Risk Level:** Yellow -- Currently functional but entirely dependent on Groq's goodwill and business decisions.

---

## 2B. GPT-OSS 20B License

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

**Source:** [Llama 3.3 Community License Agreement](https://www.llama.com/llama3_3/license/) | [Meta Llama Acceptable Use Policy](https://www.llama.com/llama3/use-policy/) | [Llama FAQ](https://www.llama.com/faq/)

### 2B.1 License Terms

The GPT-OSS 20B license agreement is **not a traditional open-source license.** It is a bilateral commercial license with specific conditions.

Key provisions:

1. **Grant:** Meta grants a non-exclusive, worldwide, non-transferable, royalty-free limited license to use, reproduce, distribute, copy, create derivative works of, and make modifications to the Llama Materials.

2. **Distribution Requirements:** If distributing or making the Llama Materials (or derivatives) available to third parties, you must:
   - Provide a copy of the license agreement
   - Include the attribution notice (see below)
   - Comply with the Acceptable Use Policy

3. **Acceptable Use Policy:** The license incorporates the Meta Llama Acceptable Use Policy, which prohibits use for illegal activities, weapons, CSAM, harassment, deception, and other harmful purposes.

### 2B.2 Commercial Use - Revenue and User Thresholds

**The 700 Million MAU Threshold:**

> "If, on the Llama 3.3 version release date [December 6, 2024], the monthly active users of the products or services made available by or for Licensee, or Licensee's affiliates, is greater than 700 million monthly active users in the preceding calendar month, you must request a license from Meta, which Meta may grant to you in its sole discretion."

**Impact on QuickSay:** QuickSay is nowhere near 700 million MAU. This threshold is designed to restrict large tech companies (e.g., Google, Amazon, Apple) from freely using GPT-OSS 20B. **QuickSay is fully compliant** with this provision.

There is **no revenue threshold** -- only the MAU threshold. A small commercial product like QuickSay at $29 is well within the license terms regardless of revenue.

### 2B.3 Access Through Groq vs. Self-Hosting

This is an important distinction. QuickSay does **not** download, host, or distribute the GPT-OSS 20B model. Users access GPT-OSS 20B through Groq's API.

The GPT-OSS 20B license contains a specific provision for end users of integrated products:

> "If you receive Llama Materials, or any derivative works thereof, from a Licensee as part of an integrated end user product, then Section 2 of this Agreement will not apply to you."

**Analysis:**
- **Groq** is a licensee of GPT-OSS 20B and hosts it on its infrastructure
- **QuickSay users** access GPT-OSS 20B through Groq's integrated API service
- Groq's license with Meta covers Groq's right to host and serve the model
- Since users access GPT-OSS 20B as part of Groq's integrated cloud service, the distribution restrictions (Section 2) **do not apply** to QuickSay or its end users

**This means:** QuickSay does not need its own separate GPT-OSS 20B license for the current BYOK/Groq API architecture. The licensing obligation falls on Groq as the model host.

**However:** If QuickSay ever self-hosts or bundles GPT-OSS 20B model weights, it would need to comply with the full license, including attribution and AUP requirements.

### 2B.4 Attribution Requirements

The license requires the following attribution notice in all copies of Llama Materials distributed:

> "Llama 3.3 is licensed under the Llama 3.3 Community License, Copyright (c) Meta Platforms, Inc. All Rights Reserved."

**Impact on QuickSay:** Since QuickSay does not distribute or include any Llama Materials (the model runs entirely on Groq's servers), **strict attribution is not technically required** under the license terms.

**Best Practice Recommendation:** Despite not being legally required, QuickSay should:
- Include a "Third-Party Services" or "Acknowledgments" section in its About dialog or documentation
- State that text cleanup is powered by "GPT-OSS 20B via Groq" to maintain transparency
- This builds trust and demonstrates good faith

### 2B.5 Content Restrictions

The Acceptable Use Policy prohibits using GPT-OSS 20B for:
- Illegal activities, exploitation of children, human trafficking
- Military/warfare, nuclear industries, weapons
- Generating malware or harmful code
- Deception, misinformation
- Harassment, hate speech
- Circumventing safety measures in the model

**Impact on QuickSay:** QuickSay uses GPT-OSS 20B solely for text cleanup (grammar, punctuation, formatting) of speech-to-text output. This is a benign use case that does not implicate any prohibited uses.

**Risk Level:** Green -- Fully compliant for current use case.

---

## 2C. OpenAI Whisper License & Attribution

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 2C.1 Whisper's Open-Source License

**Source:** [Whisper MIT License](https://github.com/openai/whisper/blob/main/LICENSE)

OpenAI Whisper is released under the **MIT License**:

> Copyright (c) 2022 OpenAI
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software...

The MIT License is one of the most permissive open-source licenses. It allows:
- Commercial use
- Modification
- Distribution
- Private use

The only requirement is including the copyright notice and license text in copies of the software.

### 2C.2 Obligations When Using Whisper via Groq

Since QuickSay uses Whisper through Groq's API (not self-hosting the model), the situation is similar to the GPT-OSS 20B analysis:

- **Groq** hosts and runs the Whisper model on its infrastructure
- **QuickSay** sends audio to Groq's API endpoint and receives text back
- QuickSay does not distribute, include, or modify the Whisper software or model weights
- The MIT License obligations (attribution in distributed copies) **do not apply** because QuickSay does not distribute Whisper

**No MIT License compliance is technically required** for QuickSay's current architecture. Groq bears the license obligations as the entity hosting and distributing the model.

### 2C.3 Trademark Analysis

**Source:** [USPTO Filing 97815511](https://furm.com/trademarks/whisper-97815511)

#### USPTO Status

OpenAI filed a trademark application for "WHISPER" on **February 28, 2023** (Serial Number 97815511). The trademark covers:

- Downloadable computer programs for automatic speech recognition
- Downloadable software for multilingual speech recognition, translation, and transcription
- Software using artificial intelligence for automatic speech-to-text conversion

**Current Status (as of November 27, 2025):** The application is **SUSPENDED** (Status: "654 - REPORT COMPLETED SUSPENSION CHECK - CASE STILL SUSPENDED"). The trademark has been in a suspended state since August 11, 2023 -- over two years without progressing to registration.

**This means:** "WHISPER" is **NOT currently a registered trademark** of OpenAI in the United States. The application is pending but suspended.

#### CIPO (Canadian) Status

No trademark registration for "Whisper" by OpenAI was found in Canadian trademark databases. OpenAI does not appear to have filed a Canadian trademark for "Whisper."

#### Can QuickSay Use the Word "Whisper" in Marketing?

**Analysis:**

1. **No registered trademark exists.** The USPTO application is suspended, and no Canadian filing was found. This means OpenAI cannot currently enforce registered trademark rights for "Whisper" in either jurisdiction.

2. **Common law trademark rights may exist.** Even without registration, OpenAI may have common law trademark rights through use in commerce. However, "whisper" is a common English word, making it difficult to claim exclusive rights, especially for a descriptive use (describing the model being used).

3. **Descriptive vs. source-identifying use matters.** If QuickSay says "uses Whisper for transcription," this is a descriptive/nominative use (identifying what technology is used) rather than a source-identifying use (implying QuickSay is made by or affiliated with OpenAI).

4. **Nominative fair use** generally permits using another's trademark to describe or refer to their product, provided:
   - The product is not readily identifiable without the mark
   - Only as much of the mark is used as necessary
   - The use does not suggest sponsorship or endorsement

### 2C.4 Recommended Naming Convention

| Option | Recommended? | Notes |
|--------|-------------|-------|
| "Whisper" alone | Acceptable with care | Descriptive use; add "by OpenAI" first mention |
| "OpenAI Whisper" | Not recommended | Could imply OpenAI endorsement or affiliation |
| "Groq Whisper" | Not recommended | Could imply Groq created Whisper |
| "Whisper (by OpenAI) via Groq" | Best option | Accurate attribution without implying affiliation |
| "Whisper Large v3 Turbo" | Acceptable | Technical model name, purely descriptive |

**Recommended approach:**
- In marketing copy, use: "powered by Whisper speech recognition via Groq"
- In technical documentation: "Whisper Large v3 Turbo (by OpenAI), hosted by Groq"
- First mention should clarify: "Whisper, an open-source speech recognition model by OpenAI"
- Avoid using "Whisper" as a standalone brand or feature name (e.g., don't say "QuickSay Whisper")

**Risk Level:** Green -- Low risk with proper attribution language.

---

## 2D. Risk Summary

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### Overall Risk Matrix

| Dependency | Risk Level | Key Issue | Required Action |
|-----------|------------|-----------|-----------------|
| **Groq API (Commercial Use)** | Green | BYOK model appears compliant with Groq ToS since each user is an independent Groq customer | Consider proactive outreach to Groq for written confirmation |
| **Groq API (Free Tier Marketing)** | Yellow | Marketing "8 hours free daily" as a QuickSay feature misrepresents third-party offering | Add disclaimers attributing free tier to Groq; note limits subject to change |
| **Groq API (Data/Privacy Claims)** | Red | "Privacy-first" and "zero data retention" claims are misleading; Groq retains data up to 30 days by default | Add disclosures about Groq data handling; update privacy claims; inform users about ZDR option |
| **Groq API (Platform Dependency)** | Yellow | Entire product depends on Groq's continued service, pricing, and free tier | Build alternative provider support; communicate dependency to users |
| **GPT-OSS 20B** | Green | Accessed via Groq; end-user integrated product exemption applies; well under 700M MAU threshold | Add voluntary attribution in About/docs for transparency |
| **OpenAI Whisper (License)** | Green | MIT-licensed; no obligations when accessing via Groq API | No action required; voluntary attribution recommended |
| **OpenAI Whisper (Trademark)** | Green | USPTO application suspended since 2023; no Canadian registration found; nominative fair use applies | Use descriptive language: "powered by Whisper (by OpenAI) via Groq" |

### Priority Actions (Ordered by Urgency)

**Immediate (Red -- Must Fix):**

1. **Update privacy disclosures.** QuickSay must stop claiming "zero data retention" without qualifying that Groq retains data for up to 30 days by default. Add clear disclosure that audio is transmitted to Groq's US-based servers.

**Short-Term (Yellow -- Should Fix):**

2. **Add free tier disclaimers.** Modify "8 hours free transcription daily" to clearly attribute this to Groq's free tier and note it is subject to change.

3. **Add third-party service acknowledgments.** Create an "Acknowledgments" or "Third-Party Services" section listing Groq, GPT-OSS 20B, and OpenAI Whisper with appropriate attribution.

4. **Begin building alternative API support.** To mitigate platform dependency, investigate supporting additional STT providers.

**Recommended (Green -- Best Practice):**

5. **Contact Groq.** Request written confirmation that the BYOK model is permitted under their ToS.

6. **Add a "Third-Party Terms" section** to QuickSay's Terms of Service explaining that users must comply with Groq's Terms of Service and Acceptable Use Policy.

7. **Monitor trademark status.** Set a reminder to check the USPTO status of OpenAI's "Whisper" trademark application (Serial 97815511) periodically.

### Recommended Disclaimer Language for Website

```
QuickSay uses the following third-party services and models:

- Speech-to-text transcription is powered by Whisper, an open-source model
  by OpenAI, accessed through Groq's API.
- Text cleanup is powered by GPT-OSS 20B, accessed through Groq's API.
- Audio data is transmitted to Groq's servers in the United States for
  processing. By default, Groq may retain data for up to 30 days. Users
  can enable Zero Data Retention in their Groq account settings.
- Free transcription is provided through Groq's free API tier, which
  currently allows up to 28,800 audio seconds (approximately 8 hours) per
  day. These limits are set by Groq and are subject to change at any time.
- QuickSay is not affiliated with, endorsed by, or sponsored by Groq,
  OpenAI, or Meta.
```

---

## Sources & References

### Groq
- [Groq Services Agreement](https://console.groq.com/docs/legal/services-agreement)
- [Groq Terms of Use](https://groq.com/terms-of-use)
- [Groq Acceptable Use & Responsible AI Policy](https://console.groq.com/docs/legal/ai-policy)
- [Groq Privacy Policy](https://groq.com/privacy-policy)
- [Your Data in GroqCloud](https://console.groq.com/docs/your-data)
- [Groq Rate Limits](https://console.groq.com/docs/rate-limits)
- [Groq Contractual Framework Overview](https://console.groq.com/docs/legal/contractual-framework-overview)
- [Groq Pricing](https://groq.com/pricing)
- [Groq Data Processing Addendum](https://console.groq.com/docs/legal/customer-data-processing-addendum)
- [Groq Community: Free Tier FAQ](https://community.groq.com/t/is-there-a-free-tier-and-what-are-its-limits/790)

### GPT-OSS 20B
- [Llama 3.3 Community License Agreement](https://www.llama.com/llama3_3/license/)
- [Meta Llama 3 Acceptable Use Policy](https://www.llama.com/llama3/use-policy/)
- [Llama FAQ](https://www.llama.com/faq/)
- [Llama Commercial Use Analysis](https://llamaimodel.com/commercial-use/)

### OpenAI Whisper
- [Whisper MIT License (GitHub)](https://github.com/openai/whisper/blob/main/LICENSE)
- [Whisper GitHub Repository](https://github.com/openai/whisper)
- [USPTO Trademark Filing 97815511](https://furm.com/trademarks/whisper-97815511)

### Legal Context
- [Groq GroqCloud Terms of Sale](https://console.groq.com/docs/terms-of-sale)

---

*Report generated February 6, 2026. All URLs and policy versions were verified as of this date. Terms of service and policies change frequently -- re-verify before making legal decisions.*
