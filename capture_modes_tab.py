"""Capture QuickSay Settings Modes tab screenshot using Playwright (headless)."""
import json
from playwright.sync_api import sync_playwright

SETTINGS_HTML = "/mnt/c/QuickSay/development/gui/settings.html"
OUTPUT_PATH = "/mnt/c/QuickSay/marketing-screenshots/QuickSay_Settings_Modes.png"

# Mock config data so the page renders properly
MOCK_CONFIG = {
    "groqApiKey": "gsk_xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "language": "en",
    "hotkey": "^LWin",
    "hotkeyMode": "hold",
    "autoPaste": 1,
    "showOverlay": 1,
    "showWidget": 1,
    "launchAtStartup": 1,
    "playSounds": 1,
    "soundTheme": "default",
    "audioDevice": "Default",
    "recordingQuality": "medium",
    "saveAudioRecordings": 0,
    "keepLastRecordings": 10,
    "sttModel": "whisper-large-v3-turbo",
    "llmModel": "openai/gpt-oss-20b",
    "enableLLMCleanup": 1,
    "autoRemoveFillers": 1,
    "smartPunctuation": 1,
    "contextAwareModes": 1,
    "historyRetention": 100,
    "accessibilityMode": 0,
    "debugLogging": 0,
    "stickyMode": 0,
}

# Mock built-in modes
MOCK_MODES = {
    "modes": [
        {
            "id": "standard",
            "name": "Standard",
            "icon": "wand",
            "description": "General-purpose cleanup with grammar and punctuation fixes",
            "prompt": "Clean up...",
            "builtIn": True,
        },
        {
            "id": "email",
            "name": "Email",
            "icon": "mail",
            "description": "Format as a professional email with greeting and sign-off",
            "prompt": "Format as email...",
            "builtIn": True,
        },
        {
            "id": "code",
            "name": "Code",
            "icon": "code",
            "description": "Preserve technical terms, variable names, and code syntax",
            "prompt": "Code mode...",
            "builtIn": True,
        },
        {
            "id": "casual",
            "name": "Casual",
            "icon": "message-circle",
            "description": "Light cleanup for chat messages and social media",
            "prompt": "Casual mode...",
            "builtIn": True,
        },
    ],
    "currentMode": "standard",
}

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 800, "height": 700})

    # Intercept postToAHK calls so the page doesn't error
    page.add_init_script("""
        window.chrome = window.chrome || {};
        window.chrome.webview = window.chrome.webview || {
            postMessage: function(msg) { console.log('postToAHK:', msg); },
            addEventListener: function() {}
        };
    """)

    page.goto(f"file://{SETTINGS_HTML}")
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(500)

    # Inject config data (simulates what AHK sends on load)
    page.evaluate(f"window.receiveConfig({json.dumps(MOCK_CONFIG)})")
    page.wait_for_timeout(300)

    # Click the Modes tab
    page.click('.tab-btn[data-tab="modes"]')
    page.wait_for_timeout(300)

    # Inject modes data (simulates what AHK sends when Modes tab is clicked)
    page.evaluate(f"window.receiveModes({json.dumps(MOCK_MODES)})")
    page.wait_for_timeout(500)

    # Capture the screenshot
    page.screenshot(path=OUTPUT_PATH)
    print(f"Screenshot saved to: {OUTPUT_PATH}")

    browser.close()
