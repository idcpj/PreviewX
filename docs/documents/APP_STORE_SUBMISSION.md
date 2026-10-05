# PreviewX — App Store 上架与提审实战手册

本文档为 **PreviewX** 上架 Mac App Store 的全流程物料准备、元数据文案、审核答辩与操作指南。

---

## 一、App Store Connect 基本信息与元数据

在 [App Store Connect](https://appstoreconnect.apple.com/) 创建新 App（macOS）时使用：

### 1. 基本信息
- **平台 (Platform)**: macOS
- **应用名称 (Name)**: `PreviewX - 开发者空格预览增强` (或 `PreviewX - Code & Data Quick Look`)
- **主要语言 (Primary Language)**: 简体中文 (Simplified Chinese) 或 英文 (English - U.S.)
- **套装 ID (Bundle ID)**: `com.idcpj.previewx`
- **SKU**: `PREVIEWX_MAC_01`（或自定义唯一字符串）
- **版本号 (Version)**: `1.0.0`
- **版权声明 (Copyright)**: `2026 idcpj`
- **App Store 图标 (1024x1024，无Alpha通道)**: 已生成于 `App/AppStoreIcon_1024.png`，可直接拖拽上传

### 2. 类别与分级
- **主要类别 (Primary Category)**: `开发者工具 (Developer Tools)`
- **次要类别 (Secondary Category)**: `实用工具 (Utilities)`
- **内容分级 (Age Rating)**: `4+`（无年龄限制内容）

### 3. 网址与联系方式
- **技术支持网址 (Support URL)**: `https://github.com/idcpj/PreviewX/issues`
- **营销网址 (Marketing URL)**: `https://github.com/idcpj/PreviewX`（可选）
- **隐私政策网址 (Privacy Policy URL)**: `https://github.com/idcpj/PreviewX/blob/main/PRIVACY_POLICY.md`（或 GitHub Pages 页面）

---

## 二、商店展示文案（可直接复制）

### 中文版 (Simplified Chinese)

- **副标题 (Subtitle, 30字符限制)**:
  ```text
  开发者专属 Quick Look 空格键增强
  ```

- **促销文本 (Promotional Text, 170字符限制)**:
  ```text
  无需等待大型 IDE 启动！选中文件轻按空格键，即刻呈现代码高亮、JSON/YAML 大纲树与压缩包免解压预览。纯本地运行，极速且安全。
  ```

- **关键词 (Keywords, 100字符限制，英文逗号分隔)**:
  ```text
  Quick Look,空格预览,代码高亮,Markdown,JSON,YAML,压缩包预览,SQLite,开发者工具,语法高亮,快速查看
  ```

- **描述 (Description)**:
  ```text
  PreviewX 是一款专为 Mac 开发者打造的现代化 Quick Look（空格键预览）增强工具与轻量文件工作台。

  【先预览，后打开 (Preview First, Open Later)】
  还在为查看几行代码或排查配置而苦等臃肿的 IDE 启动吗？使用 PreviewX，在访达（Finder）中只需轻按空格键，即可毫秒级呈现清晰专业的渲染视图。

  【核心功能特色】
  1. 丰富的代码语法高亮：
     原生内置 30+ 种主流编程语言与开发配置文件的词法高亮，包括 Swift, TypeScript, Python, Rust, Go, C/C++, Java, Kotlin, PHP, Shell, SQL, HTML/CSS, Dockerfile, Vue, Svelte 等。

  2. 现代结构化数据与表格：
     自动解析并美化排版 JSON, JSON5, YAML, TOML, XML 格式，提供清晰的大纲折叠能力；支持 CSV / TSV 纯正表格渲染与列对齐。

  3. 压缩包免解压预览：
     支持 ZIP, TAR, GZ, 7-Zip, JAR 等归档文件。无需解压即可流式查看内部文件目录树，自动防御恶意路径穿越。

  4. 日志与数据库元数据：
     超大系统/应用日志流畅分页浏览；SQLite 数据库文件头与元数据即时卡片呈现。

  5. 独立工作台与格式管理：
     除访达空格预览外，还提供独立的桌面 App 工作台，可集中配置支持的格式并进行本地调试。

  【隐私与安全设计】
  • 100% 本地优先 (Local-First)：所有解析在本地内存中完成，无任何网络数据上传，零用户追踪。
  • 绝对纯只读：不修改源文件，绝不产生写盘副作用。
  • 绝不隐式执行代码：被预览文件纯粹作为静态数据解析，杜绝恶意脚本注入执行。
  • 敏感信息告警：本地轻量检测 API Key、Token 与私钥风险并在界面显著预警，绝不外发。
  ```

---

## 三、App Store 隐私问卷填写指引 (Privacy Nutrition Labels)

在 App Store Connect 的 **App 隐私 (App Privacy)** 板块：

1. 当系统询问：“您或您的第三方合作伙伴是否从此 App 中收集数据？”
2. 明确选择：**【否，我们不会从此 App 中收集数据】 (No, we do not collect data from this app)**。
3. 保存并发布即可。
> **依据**：PreviewX 采用纯本地处理，零网络依赖、零分析 SDK，完全符合苹果关于“不收集数据”的最高隐私标准。

---

## 四、给苹果审核人员的备注 (Review Notes)

在提交版本时的 **审核信息 (App Review Information)** -> **备注 (Notes)** 中附上以下文字，能大幅降低因 Quick Look 扩展特性造成的沟通成本：

```text
Dear Apple Review Team,

PreviewX is a local-only developer file preview utility that provides a macOS Quick Look extension (com.idcpj.previewx.quicklook) and a companion configuration app.

Key testing instructions:
1. Launch PreviewX.app to verify format preferences and supported extension matrix.
2. In Finder, navigate to any code or structured data file (e.g., .swift, .json, .yaml, .md, .zip, .dockerfile) and press the Spacebar to trigger the Quick Look preview.
3. The app is 100% read-only, strictly sandboxed with standard User Selected Read-Only and App Group entitlements, and does NOT execute any file content or initiate network connections.

Thank you!
```

---

## 五、Xcode 打包与上传归档流程 (Step-by-Step)

1. **登录开发者账号**：
   - 打开 Xcode -> `Settings` (Command + ,) -> `Accounts`；
   - 登录您的 Apple Developer 账号。

2. **配置 Signing & Capabilities**：
   - 在 Xcode 项目导航中点击 `PreviewX.xcodeproj`；
   - 选中 Target `PreviewX` -> `Signing & Capabilities`：
     - 勾选 `Automatically manage signing`；
     - `Team` 选择您的个人或组织开发者团队；
     - 确认 Bundle Identifier 为 `com.idcpj.previewx`；
   - 选中 Target `PreviewXQuickLook` -> `Signing & Capabilities`：
     - 勾选 `Automatically manage signing`；
     - `Team` 选择相同团队；
     - 确认 Bundle Identifier 为 `com.idcpj.previewx.quicklook`。

3. **创建归档 (Archive)**：
   - 在 Xcode 顶部 Scheme 选择：`PreviewX` -> `Any Mac (Apple Silicon, Intel)`；
   - 点击顶部菜单栏：`Product` -> `Archive`；
   - 编译完成后会自动弹出 `Organizer` 窗口。

4. **预检与上传 (Validate & Distribute)**：
   - 在 Organizer 中点击右侧 **Validate App** 按钮；
   - 预检通过后，点击 **Distribute App** -> 选择 **App Store Connect** -> **Upload**；
   - 上传成功后，在 App Store Connect 后台等待约 5~15 分钟处理完成，即可在“构建版本”中选择该版本并正式提交审核。

---

## 六、屏幕截图准备指南 (Screenshots Guide)

App Store 强制要求至少提供 1 张 macOS 屏幕截图（建议提供 3~5 张以体现核心卖点）：

### 1. 尺寸规范 (选择其一)
- **推荐尺寸 (Retina 16:10)**: `2880 x 1800` 像素
- **标准尺寸**: `1440 x 900` 像素
- 格式：PNG（RGB，无透明度）

### 2. 推荐截取场景与对应文件
1. **主打图 1：代码极速预览与高亮**
   - 演示文件：`mock/code/sample.swift` 或 `sample.ts`
   - 展示重点：行号、多色词法高亮、顶部元数据卡片（代码行数、大小、编码）。
2. **主打图 2：结构化数据与大纲树**
   - 演示文件：`mock/structured/valid.json` 或 `sample.yaml`
   - 展示重点：JSON 格式化折叠树、大纲层级、格式美化。
3. **主打图 3：压缩包免解压大纲**
   - 演示文件：`Tests/Fixtures/archives/sample.tar` 或 `sample.zip`
   - 展示重点：目录树层级、文件类型图标、免解压即时查看。
4. **主打图 4：现代 CSV / 表格解析**
   - 演示文件：`Tests/Fixtures/csv/sample.csv`
   - 展示重点：表格网格布局、自动列对齐、单元格清晰排版。
5. **主打图 5：PreviewX 独立工作台**
   - 启动独立桌面应用 `PreviewX.app`，展示格式开关与首选项设置。

### 3. macOS 快速截图小技巧
- 选中目标文件按下空格键唤出预览窗口后；
- 按下快捷键 `Command + Shift + 4`，再按一次 `Space`（空格键）；
- 鼠标指针变为相机图标，轻点预览窗口，即可获得带优雅系统阴影的纯净独立窗口截图！
