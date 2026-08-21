<p align="center">
  <img src="Sources/Trans/Resources/TransIcon.svg" width="144" alt="Trans app icon">
</p>

<h1 align="center">Trans for macOS</h1>

<p align="center"><strong>A native macOS tool for translation and OCR.</strong></p>

[简体中文](README.md) · English

Trans brings text input, selected text, screenshots, clipboard content, and image OCR into one macOS app. Choose cloud services, local models, or Apple's on-device capabilities, then use shortcuts or the URL scheme to invoke Trans from other apps.

## Features

- Text, selected-text, silent selected-text, screenshot, clipboard OCR, and in-place translation
- Floating OCR and translation panels with editable text, source/target language switching, and automatic retranslation after edits
- Apple on-device translation, plus Google, Microsoft, Baidu, Youdao, Caiyun, Niu, LibreTranslate, DeepL, and OpenAI-compatible endpoints
- Local Ollama models through Ollama's OpenAI-compatible Chat Completions API
- Offline macOS Vision OCR, language detection, smart paragraphs, QR-code recognition, multi-image OCR, and stitched OCR
- Text-to-speech, copy, and source/target language swapping
- Translation history with search, favorites, restore, and JSON export
- Menu bar access and global shortcuts: `⌥S`, `⌥D`, `⌥A`, `⌥F`, `⌥T`
- Native Trans JavaScript plugins with import, configuration, enable/disable, and removal
- Built-in Chinese conversion, text tools, and AI writing plugins (disabled by default)

## Requirements

- macOS 14 or later
- Xcode 16 or later
- Apple on-device translation requires macOS 15+; the system may ask to download a language pack on first use

## Quick start

Run the development build:

```bash
swift run Trans
```

Build a local app bundle:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Trans.app
```

Selected-text translation requires Accessibility permission. Screenshot features require Screen Recording permission; macOS will prompt when needed.

## Configure services

Open the **Services** page, expand a service card, and enter its endpoint, model, and API key. Multiple services can be enabled at the same time. Apple on-device translation needs no configuration; whether LibreTranslate needs a key depends on the instance, while cloud services generally require provider credentials. Credentials are managed by the macOS Keychain.

### Ollama local models

1. Install and start [Ollama](https://ollama.com/), then download a model:

   ```bash
   ollama pull llama3.2
   ```

2. Enable **Ollama** on Trans's **Services** page.
3. Use `http://127.0.0.1:11434/v1/chat/completions` as the endpoint, set the model to one installed locally (for example, `llama3.2`), and leave the API key empty.

Requests use the local Ollama server by default. For another gateway that exposes an OpenAI-compatible Chat Completions endpoint, use the **OpenAI-compatible** service instead.

## Plugins

The **Plugins** page accepts `.zip` archives or Trans plugin directories containing `manifest.json` and `main.js`. Plugins can be enabled or disabled independently; fields, secrets, and menu items declared in the manifest generate their configuration UI.

Native text-translation plugins can use the JavaScript context names `transInfo`, `transOptions`, `transEnv`, `transLog`, and `transHTTP`, together with local CommonJS modules. OCR and TTS plugin types can be recognized and imported, but remain disabled until those extension points are connected. Third-party plugins execute JavaScript and may access the network, so install only plugins from sources you trust.

See [Examples/EchoPlugin](Examples/EchoPlugin) for a minimal plugin:

```javascript
function translate(request) {
  return { text: request.text, detectedLanguage: request.from };
}
```

`request` contains `text`, `from`, and `to`.

## URL scheme

PopClip, Raycast, AppleScript, and other tools can call Trans with:

```bash
open 'trans://translate?text=Hello%20world'
open 'trans://screenshot'
open 'trans://ocr'
open 'trans://selection'
```

## Development and tests

```bash
swift test
swift build -c release
```

Application code lives in `Sources/Trans/`, and tests live in `Tests/TransTests/`. Before submitting changes, run the test suite and `git diff --check`; generated `.build/` and `dist/` contents should not be committed.

## License

This project is released under the [MIT License](LICENSE).
