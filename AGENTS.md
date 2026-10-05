# PreviewX — AI Agent 核心开发与协作指南 (agent.md)

> 本文档为参与 **PreviewX** 项目开发与维护的 AI Coding Agent（及人类开发者）的最高操作规范与工程上下文索引。
> 在进行任何代码变更前，必须完整阅读并严格遵守本文档所规定的架构原则、安全红线和工程纪律。

---

## 1. 项目概览与核心理念

### 1.1 项目定位
**PreviewX** 是一款专为 macOS 开发者打造的 Quick Look 预览增强平台。通过将系统空格键预览（Finder Spacebar Preview）延伸至源码、各类配置文件、系统/应用日志、结构化数据（JSON/YAML/TOML/XML/CSV）、压缩包、数据库元数据及通用二进制，为开发者提供开箱即用、统一现代的即时预览体验。

### 1.2 核心设计哲学
- **Preview first, open later**（先预览，后打开）：预览必须瞬间呈现关键内容，辅助开发者决定是否要在大型 IDE 中启动该文件。
- **本地优先 (Local-First)**：所有核心预览逻辑 100% 运行在本地设备，基础预览不依赖任何网络调用。
- **只读原则 (Read-Only by Default)**：预览层绝对禁止修改源文件，严禁产生写盘副作用。
- **绝不隐式执行代码 (Never Execute File Content)**：被预览的文件纯粹作为数据/文本解析，绝对禁止为了预览而执行脚本或二进制。
- **默认隐私安全 (Privacy by Default)**：
  - 密钥与敏感信息（Private Key, API Key, Token 等）采用内置轻量规则进行本地检测并提示警告，绝不输出匹配值，绝不外发；
  - 远程 AI 增强分析默认完全禁用（`allowRemoteAI = false`），未经用户明确授权与主动触发严禁发起网络请求。
- **优雅降级与确定性兜底 (Graceful Degradation)**：面对畸形文件、超大文件、未知编码或未适配格式，系统提供确定性兜底渲染（如损耗 UTF-8 兜底、原始视图展示、通用二进制头信息卡片）。
- **零外部第三方依赖 (Zero External Dependencies)**：全面依托 Apple 原生框架（Foundation, AppKit, SwiftUI, QuickLookUI, UniformTypeIdentifiers, Darwin, zlib），无三方库臃肿，保证极轻量与长久稳定性。

### 1.3 核心架构纠偏（重要）
> **架构边界警示**：根据 Apple 的 macOS Quick Look Extension 规范，系统扩展运行在 OS 托管的沙箱容器中，所支持的文件类型必须在构建阶段由 `Info.plist` 的 `QLSupportedContentTypes` 静态声明。
> **PreviewX 绝不设计为“在 Quick Look 扩展进程中动态下载执行任意第三方二进制代码”**。Quick Look 扩展仅作为轻量系统适配层，核心能力由编译入宿主/扩展的 `PreviewRuntime` 与可控 Provider 矩阵提供。

---

## 2. 技术栈与环境要求

| 维度 | 要求 / 选型 | 说明 |
|---|---|---|
| **操作系统** | macOS 14.0 (Sonoma) 及以上 | 使用了较新的 SwiftUI、TaskGroup 与 UniformTypeIdentifiers 特性 |
| **编程语言** | Swift 6.0 | 严格并发安全检查 (`swiftLanguageModes: [.v6]`) |
| **构建工具** | Swift Package Manager (SPM) + Xcode 16+ | 双模支持：命令行极速构建测试与 Xcode App 打包 |
| **UI 框架** | SwiftUI + AppKit | `PreviewViewController : NSViewController, QLPreviewingController` 挂载 `NSHostingView` |
| **依赖体系** | 0 外部依赖 | 仅使用系统原生库，系统自带 `zlib` 处理压缩流 |
| **主要输出产物** | `PreviewX.app` (宿主App), `PreviewXQuickLook.appex` (扩展), `previewx` (CLI) |

---

## 3. 仓库代码库全景与模块架构

```text
PreviewX-docs/
├── App/                            # 宿主 App 的工程配置与资源
│   ├── Info.plist                  # 声明导出/导入的自定义 UTType（如 Dockerfile, Makefile）
│   └── PreviewX.entitlements       # App 沙箱与 App Group 权限声明
├── QuickLookExtension/             # Quick Look 扩展的工程配置与资源
│   ├── Info.plist                  # 声明 QLSupportedContentTypes（系统空格预览关联类型）
│   └── PreviewXQuickLook.entitlements
├── PreviewX.xcodeproj              # Xcode 工程（App Target 与 Embedded Appex Target）
├── Package.swift                   # SwiftPM 包管理定义，包含 6 个 Target
├── Makefile                        # 快捷编译、测试、代码检查与运行命令
├── DOCUMENT-MANIFEST.json          # 29 篇工程设计文档索引清单
├── docs/                           # 完备的系统设计、架构、安全与测试规格文档
├── mock/                           # 真实的测试样本目录（code, text, archives, database, structured）
├── Sources/
│   ├── PreviewXCore/               # 核心层：数据契约、运行时调度、分类器、安全与分词
│   │   ├── PreviewModels.swift     # PreviewDocument, PreviewBlock, PreviewResult, 资源预算模型
│   │   ├── ProviderContracts.swift # PreviewProvider 协议, ProviderDescriptor, ProviderRegistry
│   │   ├── Runtime.swift           # PreviewRuntime, 诊断存储 DiagnosticsStore, 语义版本排序
│   │   ├── FileAccess.swift        # 安全有界文件读取, FileClassifier (UTType+扩展名+特征签名)
│   │   ├── Security.swift          # SecretDetector (私钥、API Key、Bearer Token、密码本地正则检测)
│   │   ├── SyntaxHighlighting.swift# 零依赖行级语法分词器 (SyntaxHighlighter, 27+ 语言分词规则)
│   │   ├── MarkdownParsing.swift   # 轻量级 Markdown 树与大纲解析器
│   │   └── SettingsAndPlugins.swift# SettingsStore, PluginManifest 校验
│   ├── PreviewXProviders/          # 12 种内置 Provider 矩阵与语言目录
│   │   ├── TextAndCodeProviders.swift    # TextProvider, SourceCodeProvider, MarkdownProvider, LogProvider
│   │   ├── StructuredDataProviders.swift # JSONProvider, YAMLProvider, TOMLProvider, XMLProvider, CSVProvider
│   │   ├── ArchiveAndBinaryProviders.swift# ArchiveProvider, SQLiteMetadataProvider, BinaryMetadataProvider
│   │   └── ProviderSupport.swift   # LanguageCatalog (27+ 种语言定义), 截断/安全辅助方法
│   ├── PreviewXUI/                 # 跨 App 与扩展复用的 SwiftUI 视图层
│   │   ├── PreviewWorkspace.swift  # PreviewWorkspaceModel, PreviewWorkspaceView, 侧边栏/诊断面板
│   │   └── PreviewDocumentView.swift # PreviewResultView, CodeBlockView, TreeBlockView, TableBlockView
│   ├── PreviewXQuickLook/          # Quick Look 插件胶水层
│   │   └── PreviewViewController.swift # QLPreviewingController 实现，嵌入 QuickLookRootView
│   ├── PreviewXApp/                # 独立 macOS App 入口
│   │   └── PreviewXApp.swift       # 支持拖拽预览、命令行传参文件预览、配置管理
│   └── PreviewXCLI/                # 命令行独立调试工具
│       └── main.swift              # previewx CLI 入口（子命令：preview, providers, diagnostics, benchmark）
└── Tests/
    ├── Fixtures/                   # 专有自动化测试用例数据
    └── PreviewXTests/
        ├── PreviewXTests.swift     # 核心功能测试：JSON/CSV/Log/Archive/超时/安全/预算拦截/诊断
        ├── CustomTypeTests.swift   # 自定义文件扩展名与文件名映射规则测试
        └── MockFixturePreviewTests.swift # 遍历 mock 目录下所有真实样本的端到端解析断言
```

---

## 4. 核心数据结构与运作契约

### 4.1 统一规范文档模型 (`PreviewDocument`)
所有 Provider 无论解析何种文件，最终必须产出渲染无关的规范文档 `PreviewDocument`：
```swift
public struct PreviewDocument: Codable, Equatable, Sendable {
    public let title: String                   // 文件名
    public let subtitle: String?               // 格式说明（如 "Swift", "JSON", "ZIP Archive"）
    public let blocks: [PreviewBlock]          // 渲染块列表（文本、代码、大纲树、表格、Markdown、错误）
    public let metadata: [MetadataItem]        // 头部元数据（类型、大小、编码、行数、Provider名称等）
    public let capabilities: Set<PreviewCapability> // 支持能力（.search, .lineNavigation, .tree, .raw 等）
    public let warnings: [PreviewWarning]      // 警告信息（截断、格式畸形、敏感信息、性能提示）
}
```

### 4.2 统一结果枚举 (`PreviewResult`)
```swift
public enum PreviewResult: Equatable, Sendable {
    case success(PreviewDocument)                          // 完全成功
    case partial(PreviewDocument, warnings: [PreviewWarning]) // 部分解析（如大文件截断、JSON轻度畸形）
    case unsupported(String)                               // 明确不支持
    case failed(PreviewError)                              // 解析异常（超预算、超时、权限拒绝等）
}
```

### 4.3 Provider 契约与注册机制 (`PreviewProvider`)
```swift
public protocol PreviewProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func canPreview(_ request: PreviewRequest) async -> ProviderMatch
    func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument
}
```
- **路由决策打分 (`ProviderMatch`)**：包含 `confidence` (置信度) 与 `specificity` (专属性)。
- **路由仲裁顺序**：
  1. 用户偏好显式指定 (`policy.preferredProviderID`)；
  2. 匹配置信度 (`confidence`) 降序；
  3. 匹配特异度 (`specificity`) 降序；
  4. Provider 自身优先级 (`priority`) 降序；
  5. 内置 Provider 优先于第三方 (`isBuiltIn`)；
  6. 语义版本号 (`version`) 新版本优先；
  7. Provider ID 字典序确定性平局决胜。

### 4.4 资源预算与安全防护沙箱 (`ResourceBudget` & `PreviewResourceTracker`)
为了杜绝恶性文件引发 Finder 卡死或 OOM 崩溃，每次预览都分配严格的资源预算：
- **默认配置**：
  - `maxBytesRead`: 8MB（Quick Look 环境为 4MB）；
  - `maxMemoryBytes`: 64MB（Quick Look 环境为 32MB）；
  - `maxCPUTimeMs`: 2000ms（Quick Look 环境为 1500ms）；
  - `maxOutputNodes`: 10,000 个节点；
  - `maxArchiveEntries`: 10,000 个条目；
  - `maxTextLines`: 20,000 行。
- **文件读取监控**：必须通过 `FileAccess.read(...)`，并由 `PreviewResourceTracker` 累计预扣字节。超预算立即抛出 `PreviewError(.tooLarge)`。
- **压缩包安全**：严禁自动解压！ZIP/TAR 仅流式读取目录头；遇到 `../` 路径穿越、绝对路径、危险符号链接时，标记 `TreeNode.isUnsafe = true` 并在界面显著告警。

---

## 5. 开发常用命令速查

所有常规开发工作均可通过项目根目录下的 [Makefile](file:///Users/idcpj/workspace/PreviewX-docs/Makefile) 或 Swift CLI 驱动：

### 5.1 编译与语法校验
```bash
# 编译 SPM 全部 Target
make build
# 等同于: swift build

# 语法与配置 Lint（检查 Info.plist、pbxproj 并触发构建）
make lint
```

### 5.2 运行自动化测试
```bash
# 执行全部单元测试与 mock 样本断言（31+ 场景零失败）
make test
# 等同于: swift test
```

### 5.3 命令行预览与调试 (`previewx`)
```bash
# 使用 CLI 预览指定文件（控制台高亮输出）
swift run previewx preview mock/code/sample.swift

# 以 JSON 结构输出解析后的 PreviewDocument（排查数据块与元数据）
swift run previewx preview mock/structured/valid.json --format json

# 强制指定由特定 Provider 处理
swift run previewx preview mock/text/notes.txt --provider com.previewx.text

# 检查已注册的所有 Provider 状态
make providers
# 等同于: swift run previewx providers doctor

# 列出所有已启用的 Provider 及其扩展名映射
swift run previewx providers list

# 导出最近的预览性能与诊断日志
swift run previewx diagnostics export

# 验证第三方插件 Manifest 合法性
swift run previewx validate-plugin Plugins/Example.pxplugin/manifest.json

# 对指定样本目录运行性能基准测试
swift run previewx benchmark --path mock
```

### 5.4 宿主 App 与 Xcode 打包
```bash
# 启动独立预览 macOS 桌面应用
swift run PreviewXApp

# 编译包含 Quick Look 扩展的完整 Debug .app 包（无需开发者签名）
make xcode-build
# 产物位于 .build/xcode/Build/Products/Debug/PreviewX.app
```

---

## 6. AI Agent 开发纪律与红线守则 (Never Do)

作为 AI Coding Agent，在修改本仓库代码时**必须严格遵守以下红线**（违者视为不可接受的严重故障）：

1. **绝对不要杜撰 Apple API**：不得臆测不存在的 AppKit、QuickLook 或 SwiftUI API，所有调用必须在 macOS 14 SDK 范围内有效。
2. **绝对不要绕过资源预算与安全校验**：不得在 Provider 中擅自绕过 `FileAccess.read` 直接使用 `Data(contentsOf:)` 读入未知大小文件；不得随意增大测试中的 Timeout 阈值来掩盖性能退化。
3. **绝对不要隐式引入网络请求**：核心与内置 Provider 严禁引入任何网络发起代码；AI 模块必须严格受控于 `PreviewPolicy.allowRemoteAI`。
4. **绝对不要执行被预览的文件**：无论脚本（Shell, Python, Ruby）、二进制或插件代码，绝对不可调用 `Process`、`fork` 或 `dlopen` 来“执行”文件以获取预览。
5. **绝对不要修改用户被预览的原文件**：系统是纯只读观察器，不得产生任何就地写入或临时文件泄漏。
6. **绝对不要擅自破坏或修改既有公开契约**：`PreviewDocument`, `PreviewBlock`, `PreviewResult`, `PreviewProvider`, `ResourceBudget`, `PreviewPolicy` 属于稳定核心接口，无正式 ADR（架构决策记录）评审禁止破坏兼容性。
7. **绝对不要弱化既有测试用例**：如果修改导致既有测试失败，必须从根因修复代码逻辑，严禁删除断言或放宽测试标准。

---

## 7. 任务执行模板与变更规程

当接手一个功能开发或 Bug 修复任务时，AI Agent 必须按以下标准流程执行：

### 7.1 准备阶段 (Before Coding)
- [ ] 检索相关需求文档（阅读 [docs/](file:///Users/idcpj/workspace/PreviewX-docs/docs) 中对应章节，如 `07-Preview-Engine.md`, `08-BuiltIn-Providers.md`）；
- [ ] 明确对应的需求编号（如 `FR-006 源码高亮`, `S-3 归档路径校验`）；
- [ ] 检查并锁定测试用例位置；
- [ ] 评估对现有 Provider 路由顺序是否产生潜在影响。

### 7.2 任务上下文描述模板
在生成代码前，推荐在上下文中先对齐：
```text
Task: [任务简述]
Requirement ID: [例如 FR-005 或 Bug 描述]
Affected Files: [受影响的文件清单]
Security & Budget Impacts: [是否涉及文件读取、是否存在超限风险]
Implementation Plan: [实施步骤]
Validation Tests: [新增或需要执行的测试]
```

### 7.3 测试与合并卡点 (Merge Gate)
一个变更被认为“完成 (Done)”，必须满足：
1. `swift test` 全部测试通过（无 Regression）；
2. 如新增文件类型或 Provider，必须在 `Tests/Fixtures` 或 `Tests/PreviewXTests` 添加覆盖用例（包括正向合法文件、截断文件、恶意/畸形文件）；
3. 如涉及系统级文件类型关联，需同步校验 [QuickLookExtension/Info.plist](file:///Users/idcpj/workspace/PreviewX-docs/QuickLookExtension/Info.plist) 与 [App/Info.plist](file:///Users/idcpj/workspace/PreviewX-docs/App/Info.plist)；
4. 格式与 Lint 校验通过 (`make lint`)。

---

## 8. 核心扩展指引 (How-To Guides)

### 8.1 如何新增一种编程语言的代码高亮支持？
1. **添加元数据**：在 [ProviderSupport.swift](file:///Users/idcpj/workspace/PreviewX-docs/Sources/PreviewXProviders/ProviderSupport.swift) 的 `LanguageCatalog.definitions` 中增加语言定义（声明 `id`, `displayName`, `extensions`, `filenames`）；
2. **补充语法规则**：在 [SyntaxHighlighting.swift](file:///Users/idcpj/workspace/PreviewX-docs/Sources/PreviewXCore/SyntaxHighlighting.swift) 的 `LanguageRules.rules(for:)` 中补充该语言的关键字集合 (`keywords`)、类型名 (`types`)、单行注释前缀 (`lineComment`)、字符串分隔符等；
3. **补充 Mock 样本与测试**：在 `mock/code/` 放置样例文件，并在 [MockFixturePreviewTests.swift](file:///Users/idcpj/workspace/PreviewX-docs/Tests/PreviewXTests/MockFixturePreviewTests.swift) 中确保能成功分词。

### 8.2 如何新增一个专属的内置 `PreviewProvider`？
1. **实现协议**：在 `Sources/PreviewXProviders/` 下创建实现 `PreviewProvider` 协议的 Struct，定义专属 `ProviderDescriptor`（指定唯一反向域名 ID、优先级、支持的扩展名与 UTType）；
2. **编写探测逻辑**：在 `canPreview(_ request: PreviewRequest)` 中结合 `request.classification` 精确给出打分（避免过度贪婪匹配）；
3. **编写解析逻辑**：在 `makePreview(_ request: PreviewRequest)` 中通过 `FileAccess.read` 获取内容，构建 `PreviewBlock` 并包裹在 `PreviewDocument` 中返回；
4. **全局注册**：在 [ArchiveAndBinaryProviders.swift](file:///Users/idcpj/workspace/PreviewX-docs/Sources/PreviewXProviders/ArchiveAndBinaryProviders.swift) 的 `BuiltInProviders.registerAll` 中注册新 Provider；
5. **系统类型声明**：若需 Finder 触发，检查 [QuickLookExtension/Info.plist](file:///Users/idcpj/workspace/PreviewX-docs/QuickLookExtension/Info.plist) 的 `QLSupportedContentTypes` 是否覆盖。

---

## 9. 核心架构设计文档对照表 (Documentation Map)

在需要深入特定子系统的设计初衷时，查阅 [docs/](file:///Users/idcpj/workspace/PreviewX-docs/docs) 目录：

| 文档 | 对应主题 | 核心关注点 |
|---|---|---|
| [00-Project-Vision.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/00-Project-Vision.md) | 项目愿景与原则 | 产品承诺、P0/P1/P2 目标、Non-Goals |
| [01-Product-Requirements.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/01-Product-Requirements.md) | 功能与非功能需求 | FR-001 ~ FR-010 详细规格要求 |
| [02-System-Architecture.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/02-System-Architecture.md) | 总体系统架构 | 进程边界、时序图、数据流动与缓存设计 |
| [03-Technical-Architecture.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/03-Technical-Architecture.md) | 技术架构 | Swift 并发模型、Target 依赖拆分 |
| [06-QuickLook-Extension.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/06-QuickLook-Extension.md) | Quick Look 扩展 | macOS 扩展生命周期、宿主通信与资源约束 |
| [07-Preview-Engine.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/07-Preview-Engine.md) | 预览引擎机制 | 分类器管线、路由仲裁、平局打分准则 |
| [08-BuiltIn-Providers.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/08-BuiltIn-Providers.md) | 内置 Provider 清单 | 各格式的具体降级与解析行为 |
| [10-AI-Architecture.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/10-AI-Architecture.md) | AI 架构设计 | 权限边界、本地/远程模型接入前置约束 |
| [12-Security-Model.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/12-Security-Model.md) | 安全威胁模型 | 资源耗尽攻击防范、路径遍历防范、只读防护 |
| [13-Performance-Architecture.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/13-Performance-Architecture.md) | 性能架构与基准 | 预算管理、冷启动优化、流式读取 |
| [21-ADR-Architecture-Decisions.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/21-ADR-Architecture-Decisions.md) | 架构决策记录 | ADR-001 到 ADR-008 核心技术裁决 |
| [22-Plugin-Specification.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/22-Plugin-Specification.md) | 插件规范契约 | `manifest.json` 架构、权限系统声明 |
| [25-AI-Agent-Development-Guide.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/25-AI-Agent-Development-Guide.md) | AI Agent 行为规范 | 变更纪律、并发安全、排错协议 |
| [MVP-Traceability.md](file:///Users/idcpj/workspace/PreviewX-docs/docs/MVP-Traceability.md) | 需求追踪矩阵 | 需求项与源码实现及测试用例对应关系 |

---

*PreviewX — Local-First, Safe, and Blazing Fast Quick Look Platform for macOS Developers.*
