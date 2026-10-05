import Foundation
import PreviewXCore
import SwiftUI

public enum L10n {
    public enum Key {
        // App / Navigation
        case appName
        case currentFile
        case general
        case files
        case providers
        case fileTypes
        case diagnostics
        case settings
        case openFile
        case openFilePrompt
        case openFileHelp

        // Empty states / Status
        case noFileSelected
        case noFileSelectedDesc
        case loadingPreview
        case noDiagnostics

        // Settings - General & Language
        case language
        case languageFooter
        case languageSystem
        case languageZhHans
        case languageEn

        // Settings - Appearance
        case appearance
        case theme
        case themeSystem
        case themeLight
        case themeDark
        case themeFooter

        // Settings - Performance
        case performance
        case maxBytes
        case maxArchiveEntries
        case maxTextLines
        case performanceFooter

        // Settings - Security
        case security
        case inspectArchives
        case redactSecrets
        case securityFooter

        // Settings - Reset & About
        case resetSettings
        case about
        case aboutSubtitle
        case designedAndDevelopedBy

        // Providers
        case typeOnlyFallback
        case supportsPrefix
        case enableProvider

        // File Types
        case fileTypesNotice
        case fileTypesFooter
        case builtInFilenames
        case builtInExtensions

        // Formats & Categories (PM Redesign)
        case formatsAndRules
        case formatsSubtitle
        case catCode
        case catCodeDesc
        case catStructured
        case catStructuredDesc
        case catArchives
        case catArchivesDesc
        case catDocs
        case catDocsDesc
        case catDatabase
        case catDatabaseDesc
        case dropzoneTitle
        case dropzoneSubtitle
        case dropzoneOpenFile
        case featureLocalOnly
        case featureZeroDep
        case featureSafe
        case searchFormats

        // Diagnostics
        case durationMs
        case bytesRead
        case noProvider
    }

    public static func tr(_ key: Key, for language: PreviewXSettings.Language) -> String {
        let isZh = language.isChinese
        switch key {
        // App / Navigation
        case .appName:
            return "PreviewX"
        case .currentFile:
            return isZh ? "当前文件" : "Current File"
        case .general:
            return isZh ? "通用" : "General"
        case .files:
            return isZh ? "文件" : "Files"
        case .providers:
            return isZh ? "提供者" : "Providers"
        case .fileTypes:
            return isZh ? "文件类型" : "File Types"
        case .diagnostics:
            return isZh ? "诊断日志" : "Diagnostics"
        case .settings:
            return isZh ? "设置" : "Settings"
        case .openFile:
            return isZh ? "打开文件..." : "Open File..."
        case .openFilePrompt:
            return isZh ? "预览" : "Preview"
        case .openFileHelp:
            return isZh ? "选择要预览的文件" : "Select a file to preview"

        // Empty states / Status
        case .noFileSelected:
            return isZh ? "未选择文件" : "No File Selected"
        case .noFileSelectedDesc:
            return isZh ? "通过“打开文件”选择或拖拽文件到窗口进行预览。" : "Choose a file using Open File or drag one into the window."
        case .loadingPreview:
            return isZh ? "正在载入预览..." : "Loading preview..."
        case .noDiagnostics:
            return isZh ? "暂无诊断日志" : "No Diagnostics"

        // Settings - General & Language
        case .language:
            return isZh ? "语言 (Language)" : "Language"
        case .languageFooter:
            return isZh ? "选择应用界面语言，支持在简体中文与英文之间即时切换。" : "Select interface language, supporting instant switching between Simplified Chinese and English."
        case .languageSystem:
            return isZh ? "跟随系统" : "System"
        case .languageZhHans:
            return "简体中文"
        case .languageEn:
            return "English"

        // Settings - Appearance
        case .appearance:
            return isZh ? "外观" : "Appearance"
        case .theme:
            return isZh ? "主题" : "Theme"
        case .themeSystem:
            return isZh ? "跟随系统" : "System"
        case .themeLight:
            return isZh ? "浅色" : "Light"
        case .themeDark:
            return isZh ? "深色" : "Dark"
        case .themeFooter:
            return isZh ? "立即应用于 PreviewX。Finder 空格预览跟随系统外观。" : "Applies immediately to PreviewX. Finder Spacebar preview follows the system appearance."

        // Settings - Performance
        case .performance:
            return isZh ? "性能与预算" : "Performance"
        case .maxBytes:
            return isZh ? "最大读取字节" : "Maximum bytes"
        case .maxArchiveEntries:
            return isZh ? "归档条目上限" : "Maximum archive entries"
        case .maxTextLines:
            return isZh ? "文本行数上限" : "Maximum text lines"
        case .performanceFooter:
            return isZh ? "这些限制适用于 Finder 空格预览，防止超大文件阻塞 Quick Look。" : "These limits apply to Finder Spacebar preview and prevent huge files from blocking Quick Look."

        // Settings - Security
        case .security:
            return isZh ? "安全与隐私" : "Security"
        case .inspectArchives:
            return isZh ? "允许解析归档" : "Inspect archives"
        case .redactSecrets:
            return isZh ? "遮蔽疑似敏感凭据" : "Redact likely secrets"
        case .securityFooter:
            return isZh ? "普通预览完全在本地完成，绝不会将文件内容上传到网络。" : "Ordinary previews stay on this Mac and never send file contents to a network."

        // Settings - Reset & About
        case .resetSettings:
            return isZh ? "恢复默认设置" : "Reset Settings"
        case .about:
            return isZh ? "关于 PreviewX" : "About PreviewX"
        case .aboutSubtitle:
            return isZh ? "专为 macOS 开发者打造的轻量即时预览平台" : "Local-First Quick Look Platform for macOS Developers"
        case .designedAndDevelopedBy:
            return isZh ? "设计与开发" : "Designed & Developed by"

        // Providers
        case .typeOnlyFallback:
            return isZh ? "支持：仅按类型回退" : "Supports: type-only fallback"
        case .supportsPrefix:
            return isZh ? "支持：." : "Supports: ."
        case .enableProvider:
            return isZh ? "启用" : "Enable"

        // File Types
        case .fileTypesNotice:
            return isZh ? "macOS 不允许 PreviewX 在运行期间动态注册新的 Finder 预览类型。空格键预览仅使用编译到 Quick Look 扩展中的静态类型声明。" : "macOS does not allow PreviewX to register new Finder preview types while the app is running. Spacebar preview only uses types compiled into the Quick Look extension."
        case .fileTypesFooter:
            return isZh ? "在此添加扩展名无法让 Finder 直接调用扩展。新类型必须在 Info.plist 声明并重新编译安装。" : "Adding extensions here cannot make Finder call PreviewX. Those names must be declared in Info.plist and shipped with a new build."
        case .builtInFilenames:
            return isZh ? "内置支持的文件名" : "Built-in filenames"
        case .builtInExtensions:
            return isZh ? "内置支持的扩展名" : "Built-in extensions"

        // Formats & Categories (PM Redesign)
        case .formatsAndRules:
            return isZh ? "支持格式与扩展" : "Supported Formats"
        case .formatsSubtitle:
            return isZh ? "管理 PreviewX 在 macOS Finder 空格预览及应用内支持的文件格式与自定义映射" : "Manage supported file formats and custom mappings in Finder Quick Look and PreviewX"
        case .catCode:
            return isZh ? "源码与脚本" : "Source Code & Scripts"
        case .catCodeDesc:
            return isZh ? "Swift, Python, TypeScript, Go, Rust, C/C++ 等 30+ 种主流语言语法高亮与行号导航" : "30+ programming languages with syntax highlighting and line numbers"
        case .catStructured:
            return isZh ? "结构化数据" : "Structured Data"
        case .catStructuredDesc:
            return isZh ? "JSON, XML, YAML, TOML 格式化排版 (Pretty-Print)，CSV/TSV 数据表格预览" : "Pretty-printed JSON, XML, YAML, TOML, and tabular view for CSV/TSV"
        case .catArchives:
            return isZh ? "压缩归档" : "Archives & Packages"
        case .catArchivesDesc:
            return isZh ? "ZIP, TAR, GZ, 7Z 等目录树形浏览与安全路径穿越校验" : "Hierarchical directory tree inspection and path traversal security checks"
        case .catDocs:
            return isZh ? "文档与日志" : "Docs & Logs"
        case .catDocsDesc:
            return isZh ? "Markdown 结构化标题渲染，系统与运行日志等级高亮" : "Rich Markdown rendering, system & application logs with severity colors"
        case .catDatabase:
            return isZh ? "数据库与二进制" : "Database & Binary"
        case .catDatabaseDesc:
            return isZh ? "SQLite 数据库表结构与元数据解析，通用二进制头部安全检视" : "SQLite database schemas inspection, safe binary header inspection"
        case .dropzoneTitle:
            return isZh ? "极速预览工作台" : "Instant Quick Look"
        case .dropzoneSubtitle:
            return isZh ? "在 Finder 中选中任意文件按下空格键 (Spacebar) 即可即时预览；\n也可以拖拽文件到此窗口直接查看。" : "Select any file in Finder and press Spacebar to preview instantly,\nor drag files into this window."
        case .dropzoneOpenFile:
            return isZh ? "选择文件预览..." : "Choose File to Preview..."
        case .featureLocalOnly:
            return isZh ? "100% 本地运行" : "100% Local-First"
        case .featureZeroDep:
            return isZh ? "零依赖 · 毫秒启动" : "Zero External Deps"
        case .featureSafe:
            return isZh ? "纯只读 · 杜绝代码执行" : "Read-Only · Never Executes Code"
        case .searchFormats:
            return isZh ? "搜索格式或扩展名..." : "Search formats or extensions..."

        // Diagnostics
        case .durationMs:
            return "ms"
        case .bytesRead:
            return isZh ? "字节" : "bytes"
        case .noProvider:
            return isZh ? "无对应提供者" : "No provider"
        }
    }
}

public extension PreviewXSettings.Language {
    func tr(_ key: L10n.Key) -> String {
        L10n.tr(key, for: self)
    }
}
