# PreviewX Test Fixtures 统一测试数据集

本文档为 `Tests/Fixtures` 目录下测试数据集的说明索引。包含从 `mock/` 合并的完整样本、新扩展的语法与边界案例（包括畸形格式、Git Diff/Patch、敏感信息、二进制、路径穿越和超大预算拦截）。

---

## 目录结构与分类说明

| 子目录 | 文件数 | 说明与典型测试场景 |
|---|---|---|
| [`archives/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/archives) | 9 | 支持 `.zip`, `.tar`, `.tar.gz`, `.tgz`, `.7z`, `.gz`, `.gzip`，包含安全边界样本 `unsafe_traversal.zip` 和 `unsafe_traversal.tar`（测试 `../` 路径穿越检测）。 |
| [`binary/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/binary) | 4 | 纯二进制与兜底测试：`sample.bin` (随机字节流)、`sample_macho.bin` (Mach-O 64-bit 魔数)、`sample_elf.bin` (ELF 头)、`sample_zeroes.bin` (空字节)。 |
| [`code/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/code) | 49 | 涵盖 27+ 种主流及现代语言源代码：Swift, C, C++, Objective-C/C++, Rust, Go, Python, JS, TS, Java, Kotlin, Shell, SQL, HTML, CSS/SCSS/LESS, Dockerfile, Makefile, INI, CMakeLists, Vue, Svelte, GraphQL, Proto, Ruby, Lua, 以及 Git `.diff` 与 `.patch`。 |
| [`database/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/database) | 4 | SQLite 数据库文件：`sample.sqlite`, `sample.sqlite3`, `sample.db` 以及损坏文件 `corrupted.sqlite`（测试魔数签名校验）。 |
| [`diff/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/diff) | 3 | Git 统一差异与补丁格式：`sample.diff`, `sample.patch`, `multi_file.diff`（支持增删行高亮、hunk 语法分词）。 |
| [`huge/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/huge) | 3 | 预算截断与边界防护测试：`large_text.txt` (>20,000 行限制测试), `large_table.csv` (>1,000 行限制测试), `exceed_budget.bin` (9MB 大文件安全截断至 512 字节)。 |
| [`json/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/json) | 6 | 标准 JSON 系列：`valid.json`, `package.json`, `sample.json`, `sample.jsonc`, `sample.geojson`, `sample.har`。 |
| [`logs/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/logs) | 2 | 日志流解析：`service.log` (ISO-8601 带等级日志), `nginx_access.log` (Web 服务器访问日志)。 |
| [`malformed/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/malformed) | 14 | 畸形与格式损坏文件集合（测试容错优雅降级与告警）：错误的 JSON (未闭合括号、末尾逗号、未加引号键名)、错误的 YAML (Tab 缩进、错乱缩进、未闭合引号)、错误的 TOML、错误的 XML (标签不匹配/未闭合)、错误的 CSV (未闭合引号、列数不一致)、错误日志。 |
| [`security/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/security) | 3 | 本地敏感信息与密钥检测（`SecretDetector`）：`secret_keys.env` (AWS Key, OpenAI Key, GitHub Token), `private_key.pem` (RSA 私钥), `authorization_token.json` (Bearer JWT)。 |
| [`structured/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/structured) | 13 | 镜像完整结构化数据套件（来自 mock）：JSON, JSONC, GeoJSON, HAR, YAML, TOML, XML, XSD, SVG, Plist, CSV, TSV。 |
| [`text/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/text) | 10 | 纯文本与 Markdown 扩展名家族：`.txt`, `.text`, `.md`, `.markdown`, `.mdown`, `.log`, `.out`, `.trace`, `advanced.md`。 |
| [`toml/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/toml) | 3 | TOML 配置文件：`config.toml`, `sample.toml`, `Cargo.toml`。 |
| [`unicode/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/unicode) | 3 | 编码与多语言测试：`mixed.txt`, `utf8_bom.txt` (带 UTF-8 BOM 头), `cjk_multilingual.txt` (中日韩阿拉伯文与 Emoji)。 |
| [`xml/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/xml) | 6 | XML 及衍生格式：`data.xml`, `sample.xml`, `sample.xsd`, `sample.svg`, `sample.plist`, `pom.xml`。 |
| [`yaml/`](file:///Users/idcpj/workspace/PreviewX-docs/Tests/Fixtures/yaml) | 5 | YAML 及编排配置：`config.yaml`, `sample.yaml`, `sample.yml`, `docker-compose.yml`, `k8s-pod.yaml`。 |

---

## 自动化测试与覆盖

全套测试用例统一由 Swift Package Manager 驱动：
```bash
# 运行全部 42 个单元测试与样本断言
swift test

# 专跑 Fixtures 综合套件
swift test --filter ComprehensiveFixturesTests
```
