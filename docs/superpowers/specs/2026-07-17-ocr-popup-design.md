# 翻译小窗升级：后台 OCR 弹窗、可编辑、语言切换 — 设计文档

日期：2026-07-17

## 背景与目标

当前划词翻译已有一个跟随鼠标的浮动小窗（`SelectionPopupController` / `SelectionPopupView`，`.nonactivatingPanel` 不抢焦点）。而静默截图 OCR、连续 OCR、剪贴板 OCR 的结果只写入主窗口状态，应用在后台时用户看不到结果。

目标：

1. 应用在后台时，OCR 的识别与翻译结果也在小窗中展示（不展示图片，展示 OCR 文本 + 翻译结果），样式与划词小窗一致。
2. 小窗内源文本可编辑，编辑停顿后自动重新翻译。
3. 小窗内可切换源/目标语言，与全局设置同步。

## 方案

复用并升级现有划词小窗为通用"翻译小窗"，不新建窗口。划词与 OCR 共用同一个面板、同一套展示/编辑/语言切换能力。

### 1. OCR 结果进小窗

- **静默截图 OCR**（⌥F 快捷键、菜单栏、URL scheme `trans://ocr` 不受影响）：OCR 完成后在鼠标位置弹出小窗，标题"OCR 翻译"，展示可编辑的 OCR 文本与并发翻译结果。
- **连续 OCR、剪贴板 OCR**：仅当应用不在前台（`NSApp.isActive == false`）时弹小窗；应用在前台时维持现状（主窗口展示）。
- OCR 结果照旧写入主窗口 `ocrText` / `ocrBlocks` / `qrCodes`，"OCR 后自动复制"逻辑不变；历史记录照常写入，mode 沿用现有名称。
- OCR 未识别到文字时，小窗显示提示消息（复用 `showMessage`）。
- 小窗中不展示截图图片。

### 2. 小窗内编辑源文本

- 源文本从只读 `Text`（2 行截断）改为可编辑文本区，约 1–4 行自适应高度，超出可滚动。
- 编辑停顿 0.8 秒后自动重新翻译（防抖）；翻译中显示"翻译中…"；沿用"文本已变则丢弃过期结果"守卫。
- 面板 `canBecomeKey = true` 已支持点击输入，不激活主应用。
- 点击窗外任意处、按 Esc 仍关闭小窗（编辑场景不例外，不加图钉）。

### 3. 语言切换

- 源文本下方增加语言栏：源语言 Picker、交换按钮、目标语言 Picker。
- 直接绑定全局 `model.sourceLanguage` / `model.targetLanguage`，与主窗口联动。
- 切换语言或交换后立即对当前小窗文本重新翻译。

## 结构调整

- `SelectionPopupState`：增加 `mode`（标题：划词翻译 / OCR 翻译）；`sourceText` 变为可编辑绑定。
- `SelectionPopupController`：增加 `onRetranslate(text)` 回调（编辑防抖后、语言变化后触发）；防抖计时在 controller/view 层实现，新输入取消旧计时。
- `AppModel`：抽出统一的 `presentPopup(text:mode:at:)`，划词与 OCR 共用；OCR 各入口按策略决定弹窗或主窗口展示。
- 新增纯函数策略（如 `OCRPresentationPolicy`）：输入 silent 标志 / 应用是否前台，输出是否弹小窗，配单元测试；风格对齐现有 `SelectionInteractionTests`。

## 错误处理

- OCR 失败 / 无文字：小窗显示错误或提示消息。
- 翻译服务全部失败或未启用：沿用现有 `fail(message:)` 展示。
- 编辑为空文本：不触发翻译，清空结果区。

## 测试

- 单元测试：弹窗策略纯函数（silent / 前台组合）；防抖若抽为纯逻辑则一并测试。
- 手动验证：⌥F 静默 OCR 弹窗、后台连续 OCR 弹窗、小窗编辑后自动重翻、语言切换联动主窗口、点击窗外关闭。
