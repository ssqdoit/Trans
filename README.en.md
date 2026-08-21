<p align="center">
  <img src="Sources/Trans/Resources/TransIcon.svg" width="144" alt="Trans app icon">
</p>

<h1 align="center">Trans for macOS</h1>

<p align="center"><strong>A lightweight macOS workspace for translation and OCR.</strong></p>

[简体中文](README.md) · English

Trans brings text input, selected-text translation, screenshots, clipboard OCR, and image recognition into one native macOS workspace. It can call multiple cloud or local translation services in parallel, keeps history and non-sensitive settings locally, and stores service credentials in the macOS Keychain.

## Features

- Text, selected-text, screenshot, silent, clipboard, and in-place translation
- Floating translation and OCR panels with editable source text and language switching
- Apple on-device translation plus Google, Microsoft, Baidu, Youdao, Caiyun, Niu, LibreTranslate, DeepL, OpenAI-compatible services, and local Ollama models
- Vision-based offline OCR, language detection, smart paragraphs, and QR-code recognition
- Translation history with search, favorites, restore, and JSON export
- Menu bar access and global shortcuts: `⌥S`, `⌥D`, `⌥A`, `⌥F`, `⌥T`
- Trans `.zip`/`.zip` imports and JavaScript translation plugins
- Built-in Chinese conversion, text tools, and AI writing plugins

## Requirements

- macOS 14+
- Xcode 16+
- Apple on-device translation language packs require macOS 15+

## Run and build

```bash
swift run Trans
```

To build a signed local app bundle:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Trans.app
```

Run the test suite with:

```bash
swift test
```

The first selected-text translation requires Accessibility permission. Screenshot capture requires Screen Recording permission.

## URL scheme

Trans supports URL scheme calls from PopClip, Raycast, AppleScript, and other tools:

```bash
open 'trans://translate?text=Hello%20world'
open 'trans://screenshot'
open 'trans://ocr'
open 'trans://selection'
```

## Services and plugins

Open the **Services** page to configure endpoints, models, and API keys. Credentials are stored in the macOS Keychain. The **Plugins** page accepts Trans plugin archives or directories containing `manifest.json` and `main.js`. Third-party plugins can execute JavaScript and access the network, so only install trusted plugins.

### Ollama local models

Trans includes an **Ollama** preset and uses Ollama's OpenAI-compatible Chat Completions API. No cloud account or API key is required:

1. Install and start [Ollama](https://ollama.com/), then download a model:

   ```bash
   ollama pull llama3.2
   ```

2. Enable **Ollama** on Trans's **Services** page.
3. Use `http://127.0.0.1:11434/v1/chat/completions` as the endpoint, set the model to one installed locally (for example, `llama3.2`), and leave the API key empty.

Requests use the local Ollama server by default. Any gateway exposing an OpenAI-compatible Chat Completions endpoint can be configured through the **OpenAI-compatible** service instead.

See [Examples/EchoPlugin](Examples/EchoPlugin) for the minimal Trans plugin format.

## Privacy

Translation text is sent only to services you enable. History and non-sensitive settings stay on the local machine; service credentials are kept in the macOS Keychain.
