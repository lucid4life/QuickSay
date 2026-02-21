#!/bin/bash
# Test the complete beta feedback flow end-to-end
# Tests all three NPS scenarios: detractor, passive, promoter

set -e

WEBHOOK_URL="https://n8n.beekz.uk/webhook/beta-feedback"

echo "============================================"
echo "QuickSay Beta Feedback Flow — Full Test Suite"
echo "============================================"
echo ""

# ─── Test 1: Promoter (NPS 10) ───
echo "Test 1/3: PROMOTER (NPS 10, testimonial candidate)"
echo "────────────────────────────────────────────"
PROMOTER_PAYLOAD='{
  "name": "Test Promoter",
  "email": "test-promoter@example.com",
  "referralSource": "reddit",
  "installEase": "5",
  "groqSetupEase": "5",
  "setupIssues": "",
  "onboardingHelpfulness": "5",
  "mode": "hot-key-hold-to-talk",
  "apps": ["vs-code-code-editor", "slack", "chrome-browser"],
  "transcriptionAccuracy": "5",
  "transcriptionSpeed": "5",
  "textCleanup": "5",
  "performanceIssues": "",
  "nps": "10",
  "favoriteThing": "The speed is incredible! Best dictation tool I have ever used.",
  "topImprovement": "Add support for more languages",
  "bugs": "",
  "testimonialConsent": "yes-public",
  "testimonialText": "QuickSay has completely changed how I write code. The transcription is so fast I forget I am not typing.",
  "anythingElse": "This is amazing software!",
  "followUpConsent": "yes"
}'

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PROMOTER_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | grep HTTP_CODE | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:.*//g')

if [ "$HTTP_CODE" == "200" ]; then
    echo "  OK — Webhook accepted (HTTP 200)"
    echo "  Response: $BODY"
    echo "  Expected: Notion page (green callout, Testimonial Candidate=true)"
    echo "           Auto tags should include 'praise', 'feature_request'"
    echo "           Notify Adrian email with promoter highlight"
else
    echo "  FAIL — HTTP $HTTP_CODE"
    echo "  $BODY"
fi

echo ""
sleep 3  # Give n8n time to process

# ─── Test 2: Passive (NPS 7) ───
echo "Test 2/3: PASSIVE (NPS 7)"
echo "────────────────────────────────────────────"
PASSIVE_PAYLOAD='{
  "name": "Test Passive",
  "email": "test-passive@example.com",
  "referralSource": "google",
  "installEase": "4",
  "groqSetupEase": "3",
  "setupIssues": "Had to figure out the API key on my own",
  "onboardingHelpfulness": "3",
  "mode": "hot-key-hold-to-talk",
  "apps": ["chrome-browser"],
  "transcriptionAccuracy": "4",
  "transcriptionSpeed": "4",
  "textCleanup": "3",
  "performanceIssues": "",
  "nps": "7",
  "favoriteThing": "Decent speed",
  "topImprovement": "Better onboarding for the API key step",
  "bugs": "",
  "testimonialConsent": "no",
  "testimonialText": "",
  "anythingElse": "",
  "followUpConsent": "no"
}'

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PASSIVE_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | grep HTTP_CODE | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:.*//g')

if [ "$HTTP_CODE" == "200" ]; then
    echo "  OK — Webhook accepted (HTTP 200)"
    echo "  Expected: Notion page (yellow callout, Testimonial Candidate=false)"
    echo "           Auto tags should include 'setup_difficulty', 'ux_issue'"
    echo "           Standard Notify Adrian email"
else
    echo "  FAIL — HTTP $HTTP_CODE"
    echo "  $BODY"
fi

echo ""
sleep 3

# ─── Test 3: Detractor (NPS 3) ───
echo "Test 3/3: DETRACTOR (NPS 3)"
echo "────────────────────────────────────────────"
DETRACTOR_PAYLOAD='{
  "name": "Test Detractor",
  "email": "test-detractor@example.com",
  "referralSource": "friend",
  "installEase": "2",
  "groqSetupEase": "1",
  "setupIssues": "Could not figure out how to get the API key, took 30 minutes",
  "onboardingHelpfulness": "2",
  "mode": "hot-key-hold-to-talk",
  "apps": ["chrome-browser"],
  "transcriptionAccuracy": "2",
  "transcriptionSpeed": "3",
  "textCleanup": "2",
  "performanceIssues": "App freezes for 2-3 seconds after recording",
  "nps": "3",
  "favoriteThing": "The concept is good",
  "topImprovement": "Make the setup much simpler, I almost gave up",
  "bugs": "Recording widget sometimes appears behind other windows",
  "testimonialConsent": "no",
  "testimonialText": "",
  "anythingElse": "I want to like this but the setup is too hard for normal people",
  "followUpConsent": "yes"
}'

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$DETRACTOR_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | grep HTTP_CODE | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:.*//g')

if [ "$HTTP_CODE" == "200" ]; then
    echo "  OK — Webhook accepted (HTTP 200)"
    echo "  Expected: Notion page (red callout, Testimonial Candidate=false)"
    echo "           Auto tags should include 'bug_report', 'setup_difficulty', 'performance_issue', 'ux_issue'"
    echo "           URGENT: Notify Adrian email (red, action required)"
else
    echo "  FAIL — HTTP $HTTP_CODE"
    echo "  $BODY"
fi

echo ""

# ─── Summary ───
echo "============================================"
echo "Test Summary"
echo "============================================"
echo ""
echo "Verification checklist:"
echo "  1. Check Notion Feedback DB for 3 new pages:"
echo "     - Test Promoter (green, testimonial candidate)"
echo "     - Test Passive  (yellow, no testimonial)"
echo "     - Test Detractor (red, no testimonial)"
echo "  2. Check each page has Auto Tags populated"
echo "  3. Check a.beeksma21@gmail.com for emails:"
echo "     - URGENT detractor alert (red styling)"
echo "     - Standard passive notification"
echo "     - Standard promoter notification (with testimonial highlight)"
echo "  4. Check test-*@example.com for confirmation emails (all 3)"
echo "  5. Check Google Sheets for 3 new rows (backup)"
echo ""
echo "Notion Feedback DB:"
echo "  https://www.notion.so/30a762ba3bc180beae59ec7eac37d2d1"
