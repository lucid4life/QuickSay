# Section 4: Privacy Policy & Data Protection Compliance

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

**Prepared:** February 2026
**Scope:** QuickSay desktop application (Windows), quicksay.app website
**Developer Location:** Calgary, Alberta, Canada
**Target Markets:** Canada and United States

---

## Table of Contents

1. [4A. Data Flow Mapping](#4a-data-flow-mapping)
2. [4B. Privacy Law Requirements](#4b-privacy-law-requirements)
3. [4C. Privacy Policy Audit](#4c-privacy-policy-audit)
4. [4D. "Privacy-First" Claim Assessment](#4d-privacy-first-claim-assessment)
5. [4E. BYOK Privacy Implications](#4e-byok-privacy-implications)
6. [Summary of Recommendations](#summary-of-recommendations)

---

## 4A. Data Flow Mapping

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 4A.1 Audio Recording Lifecycle

| Stage | Details |
|-------|---------|
| **Recording Method** | FFmpeg (DirectShow) for custom audio devices; Windows MCI (winmm) for default device |
| **Audio Format** | WAV (PCM signed 16-bit, mono) |
| **Sample Rates** | High: 44100 Hz, Medium: 22050 Hz, Low: 16000 Hz |
| **Temp File** | `raw.wav` in the application directory (`ScriptDir`) |
| **Temp File Lifecycle** | Deleted at the start of each new recording (`FileDelete("raw.wav")` at line 1938); overwritten by next session |
| **Permanent Storage** | If `save_recordings` is enabled (default: `true`), a copy is saved to `data\audio\QS_YYYYMMDD_HHMMSS.wav` (line 2011-2015) |

**Key Finding:** Audio recordings can be permanently saved locally. The `save_recordings` setting defaults to `true`, meaning audio files accumulate indefinitely in `data\audio\` unless the user disables this or manually deletes them.

### 4A.2 Data Sent to Groq API

#### Whisper Transcription Request (line 2035)
```
curl -s --connect-timeout 10 --max-time 30 -X POST
  -H "Authorization: Bearer {API_KEY}"
  -F "file=@raw.wav"
  -F "model={stt_model}"
  -F "language={lang}"
  https://api.groq.com/openai/v1/audio/transcriptions
```

**Data transmitted:**
- The complete audio recording (WAV file)
- The API key (in Authorization header)
- The model identifier (e.g., `whisper-large-v3-turbo`)
- The language code (e.g., `en`)

**No additional metadata** (no user ID, device ID, app version, or IP-identifying headers) is explicitly added by QuickSay beyond what curl includes by default (User-Agent header).

#### GPT-OSS 20B Text Cleanup Request (line 2130-2131)
```
curl -s --connect-timeout 10 -X POST
  -H "Authorization: Bearer {API_KEY}"
  -H "Content-Type: application/json"
  -d @payload.json --max-time 15
  https://api.groq.com/openai/v1/chat/completions
```

**Data transmitted in `payload.json`:**
- The LLM model identifier (e.g., `openai/gpt-oss-20b`)
- A system/user prompt for cleanup instructions
- The raw transcribed text (from Whisper output)

**Key Finding:** The transcript text is sent to a second Groq endpoint for LLM cleanup when `llm_cleanup` is enabled (default: `true`). This means the user's spoken content transits through Groq's servers **twice** -- once as audio and once as text.

#### API Key Validation (line 2871-2876)
```
GET https://api.groq.com/openai/v1/models
Authorization: Bearer {API_KEY}
```
Used only in the Settings UI to test API key validity. No user data is transmitted.

### 4A.3 Data Stored Locally

| File/Directory | Contents | Location |
|----------------|----------|----------|
| `config.json` | User settings, DPAPI-encrypted API key, hotkey, audio device, preferences | `ScriptDir\config.json` |
| `dictionary.json` | Custom word replacements | `ScriptDir\dictionary.json` |
| `data\history.json` | Full dictation history: raw text, cleaned text, timestamp, active window title, duration, audio file path, word count | `ScriptDir\data\history.json` |
| `data\statistics.json` | Usage stats: total words, sessions, WPM, per-day and per-app breakdowns, daily streak, first/last use timestamps | `ScriptDir\data\statistics.json` |
| `data\audio\` | Saved WAV recordings (when `save_recordings` enabled) | `ScriptDir\data\audio\` |
| `data\logs\debug.txt` | Debug log including API responses, error details | `ScriptDir\data\logs\debug.txt` |
| `debug_log.txt` | Runtime debug log with recording events, API responses, clipboard operations | `ScriptDir\debug_log.txt` |
| `response.txt` | Last Whisper API response (JSON with transcribed text) | `ScriptDir\response.txt` |
| `clean_response.txt` | Last LLM cleanup response | `ScriptDir\clean_response.txt` |
| `log.txt` | Last curl error log | `ScriptDir\log.txt` |
| `payload.json` | Last LLM request payload (contains transcript text) | `ScriptDir\payload.json` |

**Key Findings:**

1. **History contains sensitive metadata:** `history.json` stores the active window title (`appContext`) for each dictation, revealing which applications the user was using (e.g., "Claude - Google Chrome", "Ubuntu", "WhatsApp"). This is usage-pattern data that could be considered personal information.

2. **Temporary files persist:** `response.txt`, `clean_response.txt`, `payload.json`, and `log.txt` remain in the application directory between sessions. These contain raw API responses with transcript content.

3. **Debug logs contain transcript data:** Both `debug_log.txt` and `data\logs\debug.txt` contain raw Whisper responses and LLM cleanup responses, effectively creating a secondary record of all transcriptions.

4. **No automatic cleanup:** There is no TTL, scheduled purge, or automatic cleanup mechanism for history, audio files, or debug logs.

### 4A.4 Network Calls Inventory

| Destination | Purpose | Data Sent |
|-------------|---------|-----------|
| `api.groq.com/openai/v1/audio/transcriptions` | Speech-to-text | Audio WAV file, model, language |
| `api.groq.com/openai/v1/chat/completions` | Text cleanup | Transcript text, prompt, model |
| `api.groq.com/openai/v1/models` | API key validation (Settings only) | API key only |

**No other network calls were found.** There is:
- No telemetry or analytics in the desktop app
- No update-checking mechanism
- No crash reporting service
- No other third-party API calls
- No phone-home functionality

This is consistent with the "zero telemetry" marketing claim for the desktop application.

### 4A.5 Data Flow Diagram

```
User speaks
    |
    v
[FFmpeg/MCI records audio] --> raw.wav (local temp)
    |                              |
    | (if save_recordings=true)    |
    v                              v
data/audio/QS_*.wav          [curl POST to Groq Whisper API]
(permanent local copy)             |
                                   v
                            response.txt (Groq returns JSON)
                                   |
                                   v
                            [Parse transcript text]
                                   |
                            (if llm_cleanup=true)
                                   |
                                   v
                            payload.json (transcript + prompt)
                                   |
                                   v
                            [curl POST to Groq GPT-OSS 20B API]
                                   |
                                   v
                            clean_response.txt (cleaned text)
                                   |
                                   v
                            [Apply dictionary, shortcuts, voice commands]
                                   |
                                   v
                            [Paste to active application via clipboard]
                                   |
                                   v
                            history.json (raw + cleaned text, metadata)
                            statistics.json (usage stats)
                            debug_log.txt (API responses)
```

---

## 4B. Privacy Law Requirements

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 4B.1 PIPEDA (Personal Information Protection and Electronic Documents Act)

**Applicability:** PIPEDA applies to private-sector organizations that collect, use, or disclose personal information in the course of commercial activity across Canada (except in provinces with substantially similar legislation -- Alberta is one such province; see PIPA below). For interprovincial and international data transfers, PIPEDA applies regardless of provincial legislation.

**Reference:** [PIPEDA Fair Information Principles](https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/p_principle/)

#### Does QuickSay "collect" personal information?

**Yes.** Under PIPEDA, audio recordings containing a person's voice constitute personal information. The [Office of the Privacy Commissioner (OPC)](https://www.priv.gc.ca/en/privacy-topics/surveillance/02_05_d_14/) has confirmed that audio recordings where an individual can be heard are personal information.

QuickSay collects:
- **Voice recordings** (audio WAV files) -- biometric-adjacent data
- **Transcribed speech content** -- may contain any personal information the user dictates (names, addresses, medical information, etc.)
- **Usage metadata** -- active window titles, timestamps, word counts, application usage patterns
- **API keys** -- credentials linked to the user's Groq account

#### PIPEDA's 10 Fair Information Principles -- Compliance Assessment

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| 1 | **Accountability** | :yellow_circle: | No privacy officer designated. No documented privacy policies or practices beyond the website privacy page. |
| 2 | **Identifying Purposes** | :yellow_circle: | The privacy policy states audio is used for transcription, but does not clearly identify all purposes (e.g., history storage, statistics tracking, active window recording, debug logging). |
| 3 | **Consent** | :yellow_circle: | Implied consent via use of the app. No explicit consent mechanism for sending audio to a third-party cloud service. No opt-in for history/statistics collection. |
| 4 | **Limiting Collection** | :yellow_circle: | Active window titles (`appContext`) are collected but not strictly necessary for transcription. Debug logs retain API responses beyond what is needed. |
| 5 | **Limiting Use/Disclosure/Retention** | :red_circle: | No automatic data retention limits. History, audio files, and debug logs accumulate indefinitely. No purge mechanism. |
| 6 | **Accuracy** | :green_circle: | Users can edit/delete their local data directly. Dictionary allows corrections. |
| 7 | **Safeguards** | :yellow_circle: | API key uses DPAPI encryption (good). But local data files (history, audio, logs) have no encryption and are stored as plaintext JSON/WAV in the app directory. |
| 8 | **Openness** | :yellow_circle: | Privacy policy exists but has gaps (see Section 4C). |
| 9 | **Individual Access** | :green_circle: | All data is stored locally; users have direct file access. History is viewable in the Settings UI. |
| 10 | **Challenging Compliance** | :yellow_circle: | Contact email provided (privacy@quicksay.app) but no formal complaint process documented. |

#### Cross-Border Data Transfer Requirements

PIPEDA does not prohibit cross-border transfers but requires:

1. **Notice:** Users must be informed that their data may be processed in a foreign jurisdiction ([OPC Guidelines](https://www.priv.gc.ca/en/privacy-topics/airports-and-borders/gl_dab_090127/))
2. **Comparable protection:** Contractual safeguards must ensure equivalent protection
3. **Foreign government access disclosure:** Users should be told that data in foreign jurisdictions may be accessible to courts, law enforcement, and national security authorities

**Current Status:** :red_circle: The privacy policy does not disclose that:
- Groq's servers are located in the United States (Google Cloud Platform)
- Audio data transits to and is processed on US servers
- US law enforcement may access data under US legal authorities (CLOUD Act, etc.)

### 4B.2 Alberta PIPA (Personal Information Protection Act)

**Applicability:** PIPA applies to provincially regulated private-sector organizations in Alberta. Since QuickSay's developer is based in Calgary, PIPA applies to its Alberta operations. For interprovincial and international commercial activities, PIPEDA would apply in addition to or instead of PIPA.

**Reference:** [Alberta PIPA Overview](https://www.alberta.ca/personal-information-protection-act)

**Key Additional Requirements Beyond PIPEDA:**

| Requirement | Status | Notes |
|-------------|--------|-------|
| Consent at time of collection | :yellow_circle: | Alberta is an "opt-out" consent jurisdiction, but consent must still be obtained. No explicit consent mechanism exists in QuickSay. |
| 45-day response to access requests | :yellow_circle: | No formal process documented for handling access requests. |
| Breach notification to Commissioner | :red_circle: | No breach notification procedure documented. PIPA requires notification "without unreasonable delay." |
| Reasonable privacy policies | :yellow_circle: | The website privacy policy exists but does not fully meet PIPA requirements. |
| Data destruction when no longer needed | :red_circle: | No automatic data destruction. Audio files and history accumulate without limit. |

**Penalties:** Up to $10,000 for individuals, $100,000 for organizations per offence.

**Reference:** [OIPC Alberta - PIPA](https://oipc.ab.ca/legislation/pipa/)

### 4B.3 CCPA/CPRA (California Consumer Privacy Act / California Privacy Rights Act)

**Applicability Thresholds:**

The CCPA applies to for-profit businesses that do business in California AND meet one of:
1. Annual gross revenue exceeding **$26,625,000** (2025-2026 threshold, adjusted for inflation)
2. Buy, sell, or share personal information of **100,000+** California consumers/households annually
3. Derive **50%+** of annual revenue from selling/sharing personal information

**Reference:** [CCPA FAQ - California AG](https://oag.ca.gov/privacy/ccpa), [CPPA Updated Thresholds](https://cppa.ca.gov/regulations/cpi_adjustment.html)

**Assessment for QuickSay:**

| Threshold | Likely Met? | Reasoning |
|-----------|-------------|-----------|
| Revenue > $26.6M | :green_circle: No | $29 one-time purchase; would need ~920,000 sales |
| 100,000+ CA consumers | :green_circle: No | Unlikely for a niche desktop app at launch |
| 50%+ revenue from data sales | :green_circle: No | QuickSay does not sell data |

**Conclusion:** :green_circle: QuickSay almost certainly does **not** meet CCPA thresholds currently. However:

#### Best Practices Even Below Threshold

1. **Audio as biometric information:** Under CPRA, "biometric information" includes physiological characteristics that can be used to establish identity. Voice recordings could qualify if voiceprints could be extracted, though QuickSay does not extract voiceprints.

   **Reference:** [CPRA Biometric Information Treatment](https://www.bytebacklaw.com/2022/02/how-do-the-cpra-cpa-vcdpa-treat-biometric-information/)

2. **Sensitive personal information:** If audio is used to uniquely identify a consumer, it becomes "sensitive personal information" with heightened requirements. QuickSay's use case (dictation) does not identify consumers, reducing this risk.

3. **Recommended best practices:**
   - Provide a privacy policy disclosing data practices (already done)
   - Offer data deletion capabilities (users have local access)
   - Do not sell personal information (already the case)
   - Monitor growth -- if QuickSay scales to 100K+ California users, full CCPA compliance would be required

### 4B.4 GDPR (General Data Protection Regulation)

**Applicability:** GDPR applies if QuickSay:
1. Has an establishment in the EU, **OR**
2. Offers goods or services to individuals in the EU (Article 3(2)), **OR**
3. Monitors the behavior of individuals in the EU

**Could EU users access QuickSay?** Yes -- the website is publicly accessible, and payment via LemonSqueezy could process EU payments. However, simply having a website accessible from the EU does not automatically trigger GDPR. The key question is whether QuickSay **targets** EU users (e.g., EU pricing, EU-language marketing, EU-specific features).

**Current GDPR Exposure:** :yellow_circle: Low but not zero. If any EU resident purchases and uses QuickSay, their audio data would be sent to Groq's US-based servers.

#### Minimal GDPR Compliance Needed

If QuickSay does not actively target the EU:

| Requirement | Priority | Notes |
|-------------|----------|-------|
| Legal basis for processing | Medium | Legitimate interest or consent for transcription |
| Data Processing Agreement with Groq | High | Required under Article 28 if Groq processes EU personal data on QuickSay's behalf |
| Privacy policy updates | Medium | Must include GDPR-specific disclosures if EU users are served |
| Cross-border transfer mechanism | High | US is not an "adequate" country under GDPR; Standard Contractual Clauses (SCCs) needed |
| Data subject rights | Medium | Right to access, erasure, portability |

**Data Processing Agreement (DPA) with Groq:**

Groq offers a [Customer Data Processing Addendum](https://console.groq.com/docs/legal/customer-data-processing-addendum) that addresses GDPR, CCPA, and other privacy law requirements. **If QuickSay uses its own Groq API key (non-BYOK scenario), a DPA relationship with Groq would be necessary.**

**Reference:** [Groq Data Processing Addendum](https://console.groq.com/docs/legal/customer-data-processing-addendum)

#### COPPA Considerations (Children's Online Privacy Protection Act)

COPPA applies to operators of websites or online services directed to children under 13, or who have actual knowledge of collecting information from children under 13.

**Reference:** [FTC COPPA Guidance on Voice Recordings](https://www.fenwick.com/insights/publications/ftcs-new-coppa-guidance-on-recording-childrens-voices-five-tips-for-app-developers-and-toymakers-to-comply)

**Assessment:** :yellow_circle: QuickSay is not directed at children, but a general-purpose dictation tool could be used by children. Under COPPA's 2025 amendments (effective June 23, 2025):
- Voice recordings are "personal information"
- An exception exists for audio collected solely to respond to a request and deleted immediately -- but QuickSay stores history and may save recordings
- If QuickSay has actual knowledge a child is using it, COPPA obligations would apply

**Recommendation:** Add a minimum age requirement (13+) to the Terms of Service and privacy policy to mitigate COPPA risk.

---

## 4C. Privacy Policy Audit

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

**Reviewed Document:** `/mnt/c/QuickSay/Website/src/pages/privacy.astro`
**Last Updated:** February 2026

### 4C.1 What the Current Policy Covers

The existing privacy policy covers:
- Audio recordings sent to Groq for transcription (:green_circle:)
- Custom dictionary stored locally (:green_circle:)
- Dictation history stored locally (:green_circle:)
- No personal information collected during purchase (:green_circle:)
- Groq API as third-party service (:green_circle:)
- LemonSqueezy as payment processor (:green_circle:)
- Plausible Analytics on website (:green_circle:)
- "Does NOT" list (no screen capture, no app tracking, no server storage, no data sales, no cookies) (:green_circle:)
- Data retention basics (:yellow_circle:)
- BYOK section (:yellow_circle:)
- Contact email (:green_circle:)
- Updates notification (:green_circle:)

### 4C.2 Missing Elements -- Critical

| Missing Element | Risk Level | Details |
|-----------------|------------|---------|
| **Data controller identification** | :red_circle: | No legal entity name, business address, or controller designation. PIPEDA Principle 1 (Accountability) requires identifying who is responsible. The policy does not state who "we" is. |
| **Cross-border data transfer disclosure** | :red_circle: | No mention that audio data is processed on US-based servers (Groq uses Google Cloud Platform in the US). PIPEDA and PIPA require disclosure of foreign processing. OPC guidelines specifically require notice that data may be "accessible to the courts, law enforcement and national security authorities" of foreign jurisdictions. |
| **Legal basis for processing** | :red_circle: | No stated legal basis. Under PIPEDA, this is consent; under GDPR, this could be legitimate interest or consent. Neither is identified. |
| **Active window title collection** | :red_circle: | History records the active window title (e.g., "Claude - Google Chrome") for each dictation. This is not disclosed anywhere in the privacy policy. This reveals application usage patterns. |
| **Statistics collection** | :red_circle: | The `statistics.json` file tracks per-app word counts, daily usage, streaks, first/last use -- none of this is disclosed. |
| **Debug logging** | :red_circle: | Debug logs contain raw API responses (including transcript text). Not disclosed. |
| **Temporary file persistence** | :yellow_circle: | `response.txt`, `payload.json`, `clean_response.txt` persist between sessions containing transcript data. Not disclosed. |
| **Data breach notification procedures** | :red_circle: | No breach notification procedure. PIPA requires notification to the Alberta Privacy Commissioner "without unreasonable delay." |
| **User rights** | :red_circle: | No mention of user rights to access, correct, or delete data. Under PIPEDA Principle 9, individuals must be able to access their personal information. Under PIPA, organizations must respond to access requests within 45 days. |
| **Data retention periods** | :yellow_circle: | The policy says audio is "discarded immediately after transcription" but does not mention: (1) the optional permanent saving of audio recordings (`save_recordings` default true), (2) indefinite history retention, (3) indefinite debug log retention. |
| **Children's data** | :yellow_circle: | No age restriction or COPPA-related disclosures. |
| **Cookie/tracking policy** | :green_circle: | Adequately covered for Plausible Analytics. |

### 4C.3 Missing Elements -- Groq-Specific

| Missing Element | Risk Level | Details |
|-----------------|------------|---------|
| **Groq's data retention specifics** | :red_circle: | The policy does not disclose that Groq may retain data for up to 30 days for system reliability and abuse monitoring (unless ZDR is enabled). Reference: [Groq Data Handling](https://console.groq.com/docs/your-data) |
| **Groq server location** | :red_circle: | Groq stores data in "Google Cloud Platform (GCP) buckets located in the United States." Not disclosed. |
| **Dual transmission** | :yellow_circle: | The policy mentions Groq for "Whisper transcription and GPT-OSS 20B text cleanup" but does not clearly explain that data is sent to Groq twice (once as audio, once as text). |
| **Groq's DPA availability** | :yellow_circle: | Does not mention that Groq has a Data Processing Addendum available, relevant for users in jurisdictions requiring DPAs. |

### 4C.4 Accuracy Issues in Current Policy

| Claim in Policy | Accuracy | Issue |
|-----------------|----------|-------|
| "Audio is processed in real-time and is **not stored by QuickSay** after transcription completes" | :red_circle: Inaccurate | When `save_recordings` is enabled (default: `true`), audio IS stored permanently in `data\audio\`. The raw.wav is deleted, but a copy may already have been saved. |
| "Audio is processed in real-time and discarded immediately after transcription" (Section 4) | :red_circle: Inaccurate | Same issue -- audio can be saved permanently. Also, Groq may retain data for up to 30 days. |
| "QuickSay does not maintain server-side logs of your dictation content" | :green_circle: Accurate | QuickSay itself does not maintain servers. However, Groq may retain data. |
| "Your local dictation history and custom dictionary remain on your machine until you choose to delete them" | :yellow_circle: Incomplete | True but omits: statistics, debug logs, temporary response files, and saved audio recordings. |
| "QuickSay does not record which applications you use" | :red_circle: Inaccurate | QuickSay records the active window title in `history.json` (field: `appContext`). This directly reveals which applications the user is using. |
| "QuickSay acts only as the interface -- we never see or store your API key on our servers" | :green_circle: Accurate | The API key is stored locally with DPAPI encryption. No server-side storage. |

### 4C.5 PIPEDA Compliance Summary

| PIPEDA Requirement for Privacy Policy | Met? |
|---------------------------------------|------|
| Identify the organization responsible | :red_circle: No |
| Describe what personal information is collected | :yellow_circle: Partial (misses app context, stats, debug logs) |
| Explain purposes for collection | :yellow_circle: Partial |
| Describe how consent is obtained | :red_circle: No |
| Explain limits on collection | :yellow_circle: Partial |
| Describe safeguards | :red_circle: No (no mention of DPAPI encryption or security measures) |
| Provide access to one's own information | :red_circle: No process described |
| Provide ability to challenge compliance | :yellow_circle: Contact email only; no formal process |

---

## 4D. "Privacy-First" Claim Assessment

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 4D.1 Claim: "Zero screen capture"

**Assessment:** :green_circle: **Accurate and defensible.**

Code review confirms there is no screen capture, screenshot, or screen-reading functionality in QuickSay. The only screen-related data collected is the active window title (for history context), which is not "screen capture" in the conventional sense. However, this should still be disclosed.

### 4D.2 Claim: "Zero telemetry"

**Assessment:** :green_circle: **Accurate for the desktop app.**

No telemetry, analytics, crash reporting, or phone-home functionality exists in the desktop application. The website uses Plausible Analytics (cookieless), which is properly disclosed. The claim specifically refers to the app, not the website.

### 4D.3 Claim: "Zero data retention"

**Assessment:** :red_circle: **Potentially misleading.**

This claim has significant issues:

1. **QuickSay retains data locally:**
   - Dictation history (`history.json`) -- indefinite retention
   - Audio recordings (`data\audio\`) -- indefinite retention when enabled (default: on)
   - Usage statistics (`statistics.json`) -- indefinite retention
   - Debug logs containing transcripts -- indefinite retention
   - Temporary API response files -- persist between sessions

2. **Groq retains data:**
   - By default, Groq may retain data for up to 30 days for system reliability and abuse monitoring
   - Zero Data Retention (ZDR) is an **opt-in** setting on Groq's platform -- it is not the default
   - QuickSay does not enable ZDR automatically and cannot do so on behalf of BYOK users

3. **Interpretation risk:**
   - A reasonable consumer might interpret "zero data retention" to mean their dictation content is not stored anywhere after use
   - The reality is that both QuickSay (locally) and Groq (on servers, potentially for 30 days) retain data

**Risk Level:** :red_circle: A privacy regulator or consumer advocacy group could argue this claim is misleading under Canada's Competition Act (false or misleading representations, s. 74.01) or US FTC Act (deceptive advertising, s. 5).

### 4D.4 Claim: "Your words. Your machine. Period."

**Assessment:** :red_circle: **Potentially misleading.**

- "Your words" transit through Groq's servers (US-based) as audio and potentially as text
- Groq processes the audio on their infrastructure and may retain it for up to 30 days
- The words are not exclusively on "your machine" during processing
- The period of transit and potential retention on Groq's servers contradicts the absoluteness of "Period."

**Suggested revision:** This claim could be made defensible with qualifiers such as: "Your dictation content is processed through Groq's cloud API for transcription, then returned to your machine. QuickSay does not operate its own servers or store your data remotely."

### 4D.5 Could a regulator or consumer group challenge these claims?

**Assessment:** :yellow_circle: **Yes, potentially.**

| Jurisdiction | Risk | Mechanism |
|--------------|------|-----------|
| **Canada (Competition Bureau)** | Medium | Section 74.01(1)(a) of the Competition Act prohibits representations that are "false or misleading in a material respect." The "zero data retention" claim could be challenged if Groq retains data for up to 30 days. |
| **Canada (OPC)** | Medium | The Privacy Commissioner could investigate if complaints are filed about misleading privacy representations under PIPEDA Principle 8 (Openness). |
| **Alberta (OIPC)** | Medium | Alberta's Information and Privacy Commissioner could investigate under PIPA. |
| **US (FTC)** | Low-Medium | The FTC considers claims deceptive if they are "likely to mislead consumers acting reasonably" and are "material." Privacy claims are a current FTC enforcement priority. |
| **California (AG)** | Low | Even below CCPA thresholds, the California AG can pursue deceptive privacy claims under the Unfair Competition Law (Bus. & Prof. Code 17200). |

### 4D.6 Recommended Disclaimers to Make Claims Defensible

1. **Replace "Zero data retention"** with: "Zero server-side data retention by QuickSay" or "QuickSay does not operate servers or retain your data remotely"
2. **Add Groq disclaimer:** "Audio is processed through Groq's cloud API. Groq may temporarily retain data for up to 30 days unless Zero Data Retention is enabled on your Groq account. See Groq's privacy policy for details."
3. **Clarify "Your words. Your machine.":** Add context: "All your dictation history and files stay on your machine. QuickSay uses Groq's API for transcription -- no QuickSay servers ever touch your data."
4. **Disclose local storage:** "QuickSay stores your dictation history and usage statistics locally on your computer. You can delete this data at any time through the Settings menu."

---

## 4E. BYOK Privacy Implications

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### 4E.1 Who is the Data Controller?

The BYOK model creates an unusual privacy structure:

**Traditional model (QuickSay provides API key):**
```
User --> QuickSay (Controller) --> Groq (Processor)
```
QuickSay determines the purposes and means of processing. Groq processes on QuickSay's instructions. QuickSay is the data controller.

**BYOK model (User provides their own API key):**
```
User --> QuickSay (Processor/Tool?) --> Groq (Processor for User)
```

In the BYOK model, the user:
- Provides their own API key
- Has a direct contractual relationship with Groq
- Controls the means of accessing Groq's API (through their own account)

**Analysis:** :yellow_circle: The controller/processor relationship in BYOK is ambiguous.

Arguments that QuickSay remains a controller:
- QuickSay determines **what** data is sent (the audio file format, content)
- QuickSay determines **how** data is processed (choice of Whisper model, GPT-OSS 20B cleanup)
- QuickSay determines **when** data is sent (upon recording completion)
- The user has no control over these processing decisions

Arguments that the user is the controller:
- The user provides the API credentials
- The user has a direct agreement with Groq
- The user initiates the recording
- QuickSay is merely a tool/instrument the user employs

**Likely legal interpretation:** Under PIPEDA, QuickSay would likely be considered a **joint controller** or remain the **primary controller** even in BYOK mode, because QuickSay determines the purposes and means of processing (what data is collected, how it is processed, where it is sent). The user's provision of an API key is analogous to a user providing login credentials -- it does not transfer data controller status.

Under GDPR, the [Article 29 Working Party guidance](https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2010/wp169_en.pdf) on controllers and processors indicates that the entity determining the "purposes and means" of processing is the controller. QuickSay determines both.

### 4E.2 Does BYOK Shift Privacy Obligations?

**Partially, but not entirely:**

| Obligation | Shifted to User? | Reasoning |
|------------|-------------------|-----------|
| Consent for collection | :red_circle: No | QuickSay still collects the audio and initiates the API call |
| Groq's data handling | :yellow_circle: Partially | The user's Groq account terms govern Groq's retention; the user can enable ZDR |
| Data breach notification | :red_circle: No | QuickSay still processes the data locally |
| Privacy policy obligations | :red_circle: No | QuickSay must still disclose its own data handling |
| Cross-border transfer notice | :yellow_circle: Partially | The user chose to use Groq (a US service) but QuickSay facilitates the transfer |

### 4E.3 Disclosures Needed About BYOK

The current privacy policy's BYOK section states:

> "If you bring your own Groq API key, your audio is sent directly to Groq under your own account. In this case, Groq's data handling is governed entirely by your direct agreement with them. QuickSay acts only as the interface -- we never see or store your API key on our servers."

**Issues with this disclosure:**

1. :red_circle: **"governed entirely by your direct agreement"** -- This implies QuickSay has no privacy obligations for BYOK users, which is likely incorrect. QuickSay still collects, processes, and stores data locally.

2. :red_circle: **"QuickSay acts only as the interface"** -- This understates QuickSay's role. QuickSay determines what data to send, how to process it, and stores history/statistics locally. It is more than a passive interface.

3. :yellow_circle: **"we never see or store your API key on our servers"** -- Accurate (no servers), but the API key IS stored locally in `config.json` with DPAPI encryption. This should be clarified: "Your API key is stored locally on your computer, encrypted with Windows DPAPI. It is never transmitted to QuickSay's servers."

4. :red_circle: **Missing:** No mention that QuickSay still collects and stores history, statistics, and debug logs for BYOK users in the same way as non-BYOK users.

### 4E.4 Should the Privacy Policy Differentiate BYOK vs. Non-BYOK?

**Yes**, but the differentiation should be limited because:

1. **Data collection is identical:** QuickSay collects the same data regardless of API key source
2. **Local storage is identical:** History, statistics, audio, and logs are stored the same way
3. **The only difference is the Groq relationship:** BYOK users have a direct Groq account; non-BYOK users would use QuickSay's API key (if one existed)

**Note:** Based on the code review, QuickSay appears to be **exclusively BYOK**. There is no built-in API key -- the `config.json` default has `"apiKey":""` (line 3265), and the app requires the user to provide their own Groq API key during onboarding. This means the BYOK distinction in the privacy policy may be misleading, as there is no "non-BYOK" option.

**Recommended approach:**
- Clarify that QuickSay is a BYOK-only application
- State clearly that users must have their own Groq account
- Disclose QuickSay's data handling obligations regardless of API key ownership
- Reference Groq's privacy policy and DPA for server-side data handling

---

## Summary of Recommendations

> **DISCLAIMER:** This analysis identifies potential legal risk areas for informational purposes only. It is NOT legal advice. Consult a qualified attorney in your jurisdiction before making legal decisions.

### Priority 1 -- Critical (Address Before Launch)

| # | Issue | Risk | Action Required |
|---|-------|------|-----------------|
| 1 | **Privacy policy inaccuracies** | :red_circle: | Fix the claim that audio is "not stored" -- it can be saved permanently. Fix the claim that QuickSay does "not record which applications you use" -- active window titles are recorded. |
| 2 | **Cross-border transfer disclosure** | :red_circle: | Add explicit disclosure that audio data is processed on Groq's US-based servers (Google Cloud Platform), and that US legal authorities may have access to this data. |
| 3 | **"Zero data retention" claim** | :red_circle: | Revise or add disclaimers. QuickSay retains data locally, and Groq may retain data for up to 30 days unless ZDR is enabled. |
| 4 | **Data controller identification** | :red_circle: | Add legal entity name, business address, and designated privacy contact to the privacy policy. |
| 5 | **User rights disclosure** | :red_circle: | Add section on user rights: right to access, correct, and delete personal information (required by PIPEDA and PIPA). |
| 6 | **Breach notification procedure** | :red_circle: | Document and disclose a data breach notification procedure (required by Alberta PIPA). |

### Priority 2 -- Important (Address Shortly After Launch)

| # | Issue | Risk | Action Required |
|---|-------|------|-----------------|
| 7 | **Data retention limits** | :yellow_circle: | Implement automatic data retention limits: configurable history retention period, automatic debug log cleanup, audio recording cleanup. |
| 8 | **Groq data retention disclosure** | :yellow_circle: | Add specific disclosure about Groq's default 30-day retention and how users can enable ZDR on their Groq account. |
| 9 | **Complete data inventory in policy** | :yellow_circle: | Disclose all data collected: active window titles, usage statistics, debug logs, temporary API response files. |
| 10 | **BYOK section rewrite** | :yellow_circle: | Clarify that QuickSay is BYOK-only, and that QuickSay retains local data handling obligations regardless of API key source. |
| 11 | **"Your words. Your machine." claim** | :yellow_circle: | Add clarifying context that audio transits through Groq's cloud for processing. |
| 12 | **Security measures disclosure** | :yellow_circle: | Describe security safeguards: DPAPI encryption for API keys, local-only data storage, no server infrastructure. |

### Priority 3 -- Recommended (Best Practices)

| # | Issue | Risk | Action Required |
|---|-------|------|-----------------|
| 13 | **Age restriction** | :yellow_circle: | Add 13+ age requirement to mitigate COPPA risk. |
| 14 | **Groq DPA** | :yellow_circle: | If QuickSay ever provides its own API key (non-BYOK), execute Groq's Customer Data Processing Addendum. |
| 15 | **Debug log cleanup** | :yellow_circle: | Implement automatic cleanup of debug logs, response files, and payload files that contain transcript data. |
| 16 | **Local data encryption** | :green_circle: | Consider encrypting `history.json` and other local data files, not just the API key. |
| 17 | **GDPR readiness** | :green_circle: | If expanding to EU market, prepare GDPR-compliant privacy policy, execute DPA with Groq, implement Standard Contractual Clauses. |
| 18 | **Privacy policy versioning** | :green_circle: | Maintain a changelog of privacy policy updates with specific changes noted. |

---

## Appendix A: Groq Data Handling Reference

| Feature | Groq Policy |
|---------|-------------|
| **Default retention** | May retain inputs/outputs for up to 30 days for system reliability and abuse monitoring |
| **Zero Data Retention (ZDR)** | Available to all customers via Data Controls settings; prevents Groq from retaining data |
| **Data location** | Google Cloud Platform (GCP) buckets in the United States |
| **Training on customer data** | Groq does not use customer data to train models |
| **DPA available** | Yes -- [Customer Data Processing Addendum](https://console.groq.com/docs/legal/customer-data-processing-addendum) |
| **Supported regulations** | GDPR, CCPA, PDPL (Saudi Arabia) |

**Source:** [Groq - Your Data in GroqCloud](https://console.groq.com/docs/your-data)

## Appendix B: Applicable Privacy Law References

| Law | Jurisdiction | Key URL |
|-----|-------------|---------|
| PIPEDA | Canada (Federal) | [PIPEDA Principles](https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/p_principle/) |
| PIPEDA Requirements | Canada | [PIPEDA in Brief](https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/pipeda_brief/) |
| Cross-Border Transfer Guidelines | Canada | [OPC Guidelines](https://www.priv.gc.ca/en/privacy-topics/airports-and-borders/gl_dab_090127/) |
| PIPA | Alberta, Canada | [Alberta PIPA](https://www.alberta.ca/personal-information-protection-act) |
| PIPA Overview | Alberta | [OIPC Alberta](https://oipc.ab.ca/legislation/pipa/) |
| CCPA/CPRA | California, US | [California AG - CCPA](https://oag.ca.gov/privacy/ccpa) |
| CCPA Thresholds (2026) | California | [CPPA Thresholds](https://cppa.ca.gov/regulations/cpi_adjustment.html) |
| CPRA Biometric Info | California | [Biometric Information Under CPRA](https://www.bytebacklaw.com/2022/02/how-do-the-cpra-cpa-vcdpa-treat-biometric-information/) |
| GDPR Article 28 (Processors) | EU | [Groq DPA](https://console.groq.com/docs/legal/customer-data-processing-addendum) |
| COPPA | US (Federal) | [FTC COPPA FAQ](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) |
| COPPA Voice Guidance | US | [FTC Voice Recording Guidance](https://www.fenwick.com/insights/publications/ftcs-new-coppa-guidance-on-recording-childrens-voices-five-tips-for-app-developers-and-toymakers-to-comply) |

## Appendix C: Source Code References

All code references are from `/mnt/c/QuickSay/Development/QuickSay.ahk`:

| Function/Location | Line(s) | Relevance |
|-------------------|---------|-----------|
| Audio recording (FFmpeg) | 1924-1971 | StartRecording() -- records to raw.wav |
| Audio saving | 2010-2017 | Copies raw.wav to data\audio\ if save_recordings enabled |
| Whisper API call | 2019-2035 | Sends audio + model + language to Groq |
| GPT-OSS 20B API call | 2102-2151 | Sends transcript text to Groq for cleanup |
| History storage | 1125-1181 | SaveToHistory() -- stores raw/cleaned text, app context, metadata |
| Statistics tracking | 1192-1249 | UpdateStatistics() -- per-app, per-day usage tracking |
| API key validation | 2871-2880 | Settings UI API key test |
| DPAPI encryption | 2262-2309 | API key encryption |
| Config defaults | 3265 | Default config including save_recordings: true |
| Active window capture | 1134 | `activeWindow := WinGetTitle("A")` stored in history |
| Debug logging | Throughout | FileAppend to debug_log.txt with API responses |
