<p align="center">
  <img src="Sources/Trans/Resources/TransIcon.svg" width="144" alt="Trans 应用图标">
</p>

<h1 align="center">Trans for macOS</h1>

<p align="center"><strong>原生 macOS 翻译与 OCR 工具。</strong></p>

简体中文 · [English](README.en.md)

Trans 将文本输入、划词、截图、剪贴板和图片 OCR 汇集到一个 macOS 应用中。你可以按需选择云端服务、本地模型或 Apple 的系统能力，也可以通过快捷键和 URL Scheme 在其他应用中调用。

## 功能

- 文本翻译、划词翻译、静默划词、截图翻译、剪贴板 OCR 和输入框原位翻译
- OCR 与翻译浮动窗口：编辑识别结果、切换源语言和目标语言，并在停顿后自动重翻
- Apple 本地翻译，以及 Google、Microsoft、百度、有道、彩云、小牛、LibreTranslate、DeepL 和 OpenAI 兼容接口
- Ollama 本地模型支持，可直接使用 Ollama 的 OpenAI 兼容 Chat Completions API
- macOS Vision 离线 OCR、语言检测、智能分段、二维码识别和多图/连续拼接 OCR
- 原文与译文朗读、复制和语言互换
- 翻译历史：搜索、收藏、恢复和 JSON 导出
- 菜单栏入口和全局快捷键：`⌥S`、`⌥D`、`⌥A`、`⌥F`、`⌥T`
- Trans 原生 JavaScript 插件：导入、配置、启用和卸载
- 内置“简繁与拼音”“文本格式工具”“AI 写作助手”插件（默认关闭，可按需开启）

## 系统要求

- macOS 14 或更高版本
- Xcode 16 或更高版本
- Apple 本地翻译需要 macOS 15+；首次使用某个语言组合时，系统可能提示下载语言包

## 快速开始

直接运行开发版：

```bash
swift run Trans
```

构建可双击运行的应用包：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Trans.app
```

首次使用划词翻译时，请在“系统设置 → 隐私与安全性 → 辅助功能”中授权。首次截图时，按系统提示授予录屏权限。

## 配置翻译服务

打开 Trans 的“服务”页面，展开服务卡片后填写接口地址、模型和 API Key，即可启用一个或多个服务。Apple 本地翻译无需配置；LibreTranslate 是否需要密钥取决于所使用的实例，云端服务通常需要对应服务商的凭据。凭据由 macOS 钥匙串管理。

### 使用 Ollama 本地模型

1. 安装并启动 [Ollama](https://ollama.com/)，下载一个模型：

   ```bash
   ollama pull llama3.2
   ```

2. 在 Trans 的“服务”页面启用 **Ollama**。
3. 确认接口地址为 `http://127.0.0.1:11434/v1/chat/completions`，模型填写本机已下载的模型名称（例如 `llama3.2`），API Key 留空。

Ollama 请求默认只发送到本机。如果你使用的是其他兼容 OpenAI Chat Completions 的网关，可选择“OpenAI 兼容”服务并填写对应地址。

## 插件

“插件”页面支持导入 `.zip` 文件，或包含 `manifest.json` 与 `main.js` 的 Trans 插件目录。插件可以单独启用或关闭；清单中声明的输入框、密钥和菜单选项会自动生成配置界面。

Trans 原生文本翻译插件可使用以下 JavaScript 上下文：`transInfo`、`transOptions`、`transEnv`、`transLog`、`transHTTP`，并支持本地 CommonJS 模块。OCR 与 TTS 类型可以识别和导入，但当前会保持关闭并标明尚未接入。第三方插件能够执行 JavaScript 并访问网络，请只安装可信来源的插件。

最小插件示例位于 [Examples/EchoPlugin](Examples/EchoPlugin)：

```javascript
function translate(request) {
  return { text: request.text, detectedLanguage: request.from };
}
```

`request` 包含 `text`、`from` 和 `to` 字段。

## URL Scheme

PopClip、Raycast、AppleScript 或其他工具可以调用以下 URL：

```bash
open 'trans://translate?text=Hello%20world'
open 'trans://screenshot'
open 'trans://ocr'
open 'trans://selection'
```

## 开发与测试

```bash
swift test
swift build -c release
```

应用代码位于 `Sources/Trans/`，测试位于 `Tests/TransTests/`。提交前请运行测试并检查 `git diff --check`；生成的 `.build/` 和 `dist/` 不应提交。

## 开源协议

本项目以 [MIT License](LICENSE) 发布。
