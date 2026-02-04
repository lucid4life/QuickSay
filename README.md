# QuickSay

**Voice-to-text dictation for Windows.** Press a hotkey, speak, and your words appear as text wherever your cursor is.

QuickSay uses Groq's Whisper API for fast, accurate speech-to-text transcription with optional AI-powered text cleanup that adds punctuation, fixes grammar, and removes filler words.

## Features

- **Global hotkey activation** - Press `Ctrl+Win` (customizable) from any application
- **Fast transcription** - Powered by Groq's Whisper Large V3 Turbo model
- **AI text cleanup** - Automatic punctuation, grammar fixes, and filler word removal
- **Works with any microphone** - Built-in, USB, Bluetooth, or headset
- **Audio device selection** - Choose your preferred microphone in Settings
- **Visual overlay** - Shows recording status with a floating indicator
- **Custom dictionary** - Map spoken words to specific written forms (e.g., "groq" -> "Groq")
- **Sound feedback** - Audio cues for recording start, stop, and errors
- **System tray integration** - Runs quietly in the background
- **Onboarding wizard** - Guided setup for first-time users

## Requirements

- Windows 10 or Windows 11
- A [Groq API key](https://console.groq.com/keys) (free tier available)
- A microphone

## Installation

1. Download the latest installer from the [Releases](https://github.com/lucid4life/QuickSay/releases) page
2. Run `QuickSay_Setup_v2.3.exe`
3. Follow the onboarding wizard to enter your Groq API key
4. Start dictating with `Ctrl+Win`

The installer bundles FFmpeg (for audio device support) and will automatically install the WebView2 runtime if needed (Windows 10).

## Usage

1. **Start recording**: Press `Ctrl+Win` (or your custom hotkey)
2. **Speak**: Talk naturally - QuickSay will transcribe your speech
3. **Stop recording**: Press the hotkey again or release after a pause
4. **Text appears**: Your transcribed text is typed at the cursor position

### Settings

Right-click the system tray icon and select **Settings** to configure:

- **API Key** - Your Groq API key
- **Hotkey** - Custom keyboard shortcut
- **Audio Device** - Select your microphone
- **AI Cleanup** - Toggle smart punctuation and grammar fixes
- **Recording Quality** - Low, medium, or high
- **Sound Effects** - Enable/disable audio feedback
- **Custom Dictionary** - Add word mappings
- **Launch at Startup** - Auto-start with Windows

## How It Works

1. QuickSay captures audio using FFmpeg (DirectShow) or Windows MCI
2. Audio is sent to Groq's Whisper API for transcription
3. Optionally, the transcript is cleaned up by Groq's LLM (Llama 3.3 70B)
4. The final text is typed into the active application via simulated keystrokes

## Project Structure

```
QuickSay-Launcher.ahk    # App launcher and tray menu
QuickSay-Next.ahk        # Core engine (recording, transcription, text output)
onboarding_ui.ahk        # First-run setup wizard
settings_ui.ahk          # Settings panel
config.example.json      # Default configuration template
dictionary.json          # Custom word mappings
setup.iss                # Inno Setup installer script
build_release.ps1        # Build automation
record.bat               # FFmpeg recording helper
gui/
  onboarding.html         # Onboarding wizard UI
  settings.html           # Settings panel UI
  settings.css            # Settings styles
  styles.css              # Shared styles
  assets/                 # Icons and logos
lib/
  WebView2.ahk            # WebView2 integration
  WebView2Loader.dll      # WebView2 native loader
  web-overlay.ahk         # Recording overlay
  GDI.ahk                 # Graphics helpers
  JSON.ahk                # JSON parser
  ComVar.ahk              # COM variant helpers
  Promise.ahk             # Async helpers
sounds/
  start.wav               # Recording start sound
  stop.wav                # Recording stop sound
  error.wav               # Error sound
```

## Building from Source

### Prerequisites

- [AutoHotkey v2.0](https://www.autohotkey.com/) (64-bit)
- [Inno Setup 6](https://jrsoftware.org/isinfo.php)
- [FFmpeg](https://www.gyan.dev/ffmpeg/builds/) (essentials build)
- [WebView2 Evergreen Bootstrapper](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)

### Build Steps

1. Download FFmpeg essentials and place `ffmpeg.exe` in `ffmpeg/`
2. Download WebView2 bootstrapper and place it in `redist/`
3. Run the build script:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build_release.ps1
   ```
4. The installer will be created in `installer/`

## Tech Stack

- **AutoHotkey v2.0** - Application framework and hotkey management
- **WebView2** - Modern HTML/CSS/JS UI rendering
- **Groq API** - Speech-to-text (Whisper) and text cleanup (Llama)
- **FFmpeg** - Audio capture from any device via DirectShow
- **Windows MCI** - Fallback audio recording for default device
- **Inno Setup** - Windows installer packaging

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Groq](https://groq.com/) for lightning-fast AI inference
- [AutoHotkey](https://www.autohotkey.com/) community
- [FFmpeg](https://ffmpeg.org/) project
