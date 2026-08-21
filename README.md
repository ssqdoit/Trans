<p align="center">
  <img src="Resources/Brand/TransIcon.png" width="144" alt="Trans app icon">
</p>

<h1 align="center">Trans for macOS</h1>

<p align="center"><strong>随处取词，看图识字，选择你的翻译引擎。</strong></p>

简体中文 · [English](README.en.md)

Trans 是一款原生 macOS 翻译与 OCR 效率工具。它把输入、划词、截图、剪贴板和图片中的文字汇集到一个轻巧工作台，并可同时调用多个翻译服务，方便快速使用或对照结果。常用功能都有全局快捷键；OCR、历史和非敏感配置留在本机，服务密钥安全保存在 macOS 钥匙串。

## Logo 设计

新图标是一杯平静的清水，表达“停一下、喝口水，再轻松继续”的舒适感。它不绑定翻译或 OCR 等具体功能，而是传达清醒、补充能量和从容完成工作的产品性格。视觉延续几何化、高对比和充足留白的风格，只用一处浅蓝色水面增加温度；未来扩展 AI、写作或自动化能力时，这个品牌符号仍然成立。

## 已实现功能

- 输入翻译、划词翻译、静默划词、截图翻译、输入框原位翻译，多翻译服务并发返回
- 划词/OCR 浮动小窗：原文可编辑（停顿自动重翻）、源/目标语言即时切换
- Apple 本地离线翻译、Google、Microsoft、百度、有道、彩云、小牛、LibreTranslate、DeepL、OpenAI 兼容接口
- 截图 OCR、静默截图 OCR（浮动小窗展示识别与翻译）、多图 OCR、剪贴板 OCR、连续拼接 OCR
- macOS Vision 离线文字识别、语言检测、智能分段、二维码识别
- 原文和译文语音朗读、复制、语言互换
- 翻译历史、搜索、收藏、恢复、JSON 导出
- 菜单栏入口和全局快捷键：`⌥S`、`⌥D`、`⌥A`、`⌥F`、`⌥T`
- Trans `.zip`/`.zip` 与 Trans JavaScript 翻译插件的导入、配置、启用和卸载
- 内置“简繁与拼音”“文本格式工具”“AI 写作助手”插件（默认关闭，按需开启）
- 本地设置与服务配置持久化

## 运行

要求 macOS 14+ 和 Xcode 16+。

```bash
swift run Trans
```

构建可双击运行的应用：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Trans.app
```

首次使用划词翻译时，请在“系统设置 → 隐私与安全性 → 辅助功能”中授权；首次截图时按系统提示授予录屏权限。

## 外部调用

PopClip、Raycast 和 AppleScript 可通过 URL Scheme 调用：

```bash
open 'trans://translate?text=Hello%20world'
open 'trans://screenshot'
open 'trans://ocr'
open 'trans://selection'
```

## 配置翻译服务

打开“服务”，展开服务卡片并填写接口地址和 API Key。可以同时启用多个服务。Apple 本地翻译是系统内置服务，无需任何配置（macOS 15+，首次使用某个语言组合时系统会提示下载语言包）；LibreTranslate 是否需要密钥取决于你配置的实例；DeepL 和 OpenAI 兼容服务通常需要密钥。

## 插件

“插件”页面可以直接导入 Trans 的 `.zip`、`.zip`，也可以选择一个插件目录。每个插件都能单独开启或关闭；Trans `manifest.json` 中声明的输入框、密钥和菜单选项会自动生成配置界面，其中密钥保存在 macOS 钥匙串。

目前可运行 Trans 的文本翻译插件，兼容常用的 `transInfo`、`transOptions`、`transEnv`、`transLog`、`transHTTP` 和本地 CommonJS 模块。OCR 与 TTS 类型可以识别和导入，但会保持关闭并标明暂未接入。第三方插件会执行 JavaScript 且可能访问网络，只应导入可信来源的插件。

Trans 自身的简化插件格式仍然可用：

插件是包含 `manifest.json` 和 `main.js` 的文件夹。`main.js` 导出同步函数：

```javascript
function translate(request) {
  return { text: request.text, detectedLanguage: request.from };
}
```

`request` 包含 `text`、`from` 和 `to`。可直接安装 [Examples/EchoPlugin](Examples/EchoPlugin) 体验。

## 测试

```bash
swift test
```

服务密钥安全保存在 macOS 钥匙串；历史与非敏感配置保存在 `~/Library/Application Support/Trans/`，不会提交到仓库。
