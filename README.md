# PreviewX ⚡️

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zero Dependency](https://img.shields.io/badge/Dependencies-0%20External-success)](#核心设计哲学)
[![Local First](https://img.shields.io/badge/Privacy-Local--First-brightgreen)](PRIVACY_POLICY.md)

**PreviewX** 是一款专为 macOS 开发者打造的现代化 Quick Look（空格键预览）增强工具与独立文件工作台。

无需启动体积庞大的 IDE 或专业软件，只需轻轻按下**空格键**，即可即时渲染语法高亮、结构化数据树、压缩包虚拟目录与各类开发配置文件。

---

## ✨ 核心特性

- ⚡️ **先预览，后打开 (Preview first, open later)**：毫秒级冷启动，支持大文件有界流式读取与虚拟滚动，Finder 预览永不卡死。
- 🎨 **丰富语法高亮**：原生行级分词器，原生支持 30+ 种主流语言与配置文件（Swift, TypeScript, Python, Rust, Go, SQL, Dockerfile, Vue, Svelte 等）。
- 🌳 **结构化数据渲染**：针对 JSON, YAML, TOML, XML 自动格式化排版并支持大纲折叠；支持 CSV / TSV 现代表格视图。
- 📦 **压缩包免解压预览**：ZIP, TAR, GZ, 7-Zip, JAR 即时展开文件树大纲，流式读取目录头，严格防护路径穿越攻击。
- 🛡️ **默认安全与隐私**：
  - **本地优先 (Local-First)**：100% 逻辑在本地设备执行，无第三方统计与数据回传。
  - **绝对只读 (Read-Only)**：不产生写盘副作用，绝不隐式执行被预览文件。
  - **敏感信息本地告警**：内置轻量规则检测私钥、API Key 与 Token，仅在界面安全提示，绝不泄露明文。
- 🪶 **零第三方依赖**：完全基于 Apple 原生框架（SwiftUI + AppKit + Foundation + Darwin + zlib）构建，轻盈稳定。

---

## 🖥️ 支持格式一览

| 分类 | 支持格式 / 扩展名 |
|---|---|
| **编程语言** | `swift`, `ts`, `js`, `py`, `rs`, `go`, `c`, `cpp`, `java`, `kt`, `rb`, `php`, `sh`, `zsh`, `fish`, `sql`, `html`, `css`, `vue`, `svelte` 等 |
| **配置文件** | `Dockerfile`, `Makefile`, `CMakeLists.txt`, `yaml`, `yml`, `toml`, `ini`, `conf`, `env`, `.gitignore`, `.editorconfig` 等 |
| **结构化数据** | `json`, `json5`, `jsonc`, `geojson`, `har`, `xml`, `plist`, `svg`, `csv`, `tsv` |
| **归档文件** | `zip`, `tar`, `tar.gz`, `tgz`, `7z`, `gz`, `jar`, `war`, `apk` |
| **数据库与二进制** | `sqlite`, `sqlite3`, `db` 元数据卡片；`wasm`, `bin`, `dylib` 通用头信息展示 |

---

## 🚀 快速上手与构建

### 系统要求
- macOS 14.0 (Sonoma) 或更高版本
- Xcode 16.0+ / Swift 6.0+

### 1. 命令行极速构建与测试
```bash
# 克隆代码
git clone https://github.com/idcpj/PreviewX.git
cd PreviewX

# 运行全套自动化测试 (88+ 测试用例)
make test

# 使用 CLI 预览本地文件
swift run previewx preview mock/structured/valid.json
```

### 2. 编译并安装到 macOS 系统
```bash
# 编译并在本地安装 PreviewX.app 与 QuickLookExtension
make install
```

---

## 🔒 隐私与安全承诺

PreviewX 遵循严格的隐私保护承诺：
- 不收集、不存储、不上传任何个人信息与文件内容。
- 详细说明请参阅 **[隐私政策 (Privacy Policy)](PRIVACY_POLICY.md)**。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源协议发布，商业友好，自由使用。
