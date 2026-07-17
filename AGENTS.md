# 仓库指南

## 项目结构与模块组织

Trans 是一个原生 macOS Swift Package。应用代码位于 `Sources/Trans/`：`TransApp.swift` 定义应用场景（scenes），`ContentView.swift` 包含 SwiftUI 视图，`AppModel.swift` 负责协调翻译、OCR、历史记录和设置。服务集成分别拆分在 `TranslationClient.swift`、`OCRService.swift`、`PluginManager.swift` 和 `SystemServices.swift` 中。测试位于 `Tests/TransTests/`。打包元数据在 `Resources/Info.plist`；`Examples/EchoPlugin/` 演示了 JavaScript 插件格式。生成的 `.build/` 和 `dist/` 内容不得提交。

## 构建、测试与开发命令

- `swift run Trans` 构建并启动开发版可执行文件。
- `swift test` 运行完整的 XCTest 测试套件。
- `swift build -c release` 验证优化构建。
- `./scripts/build-app.sh` 创建并本地签名 `dist/Trans.app`。
- `open dist/Trans.app` 启动打包后的应用，用于权限和 UI 测试。

请使用 macOS 14+ 和最新的 Xcode 工具链。Apple 本地翻译需要 macOS 15+，无需配置；缺少语言包时会在主窗口弹出系统下载确认。

## 代码风格与命名约定

使用四空格缩进和标准 Swift API 命名：类型使用 `UpperCamelCase`，属性和函数使用 `lowerCamelCase`。优先创建小型服务类型，而不是把不相关的行为塞进 `AppModel`。保持用户可见的中文字符串简洁，并将可复用状态放在 `Models.swift` 中。网络和 OCR 工作使用 Swift 并发；AppKit 操作和已发布的 UI 变更保持在 `@MainActor` 上。项目未配置格式化工具，请与周围代码风格保持一致，并在提交前运行 `git diff --check`。

## 测试指南

测试使用 XCTest，命名格式为 `test<Behavior>`，例如 `testParsesMicrosoftResponse`。请为响应解析、持久化、权限策略决策和默认服务配置添加回归测试。测试中绝不能调用付费 API；请使用有代表性的 JSON fixture。每次提交 pull request 前运行 `swift test`，然后在默认窗口尺寸和 `450×310` 最小窗口尺寸下手动验证打包后的应用。

## 提交与 Pull Request 指南

本仓库尚无既定的提交历史。请使用简短的祈使句式提交信息，可选用 Conventional Commit 前缀，例如 `fix: preserve selection hotkey input`。Pull request 应说明行为变更、列出测试结果、指出对 macOS 权限的影响，并为 UI 变更附上截图。请关联相关 issue，并明确指出迁移事项或新的服务凭据。

## 安全与配置提示

API 密钥应存放在 macOS 钥匙串中，绝不能放在源文件或 fixture 里。除非变更明确包含权限迁移，否则请保持 bundle identifier `com.trans.mac`、URL scheme `trans` 和签名行为不变。不要提交导出的历史记录、语言数据、证书或本地 application-support 文件。
