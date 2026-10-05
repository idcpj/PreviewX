#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
fixtures="$root/Tests/Fixtures"
mock="$root/mock"

echo "==> Creating Fixtures directory structure..."
mkdir -p "$fixtures"/{archives,binary,code,csv,database,diff,huge,json,logs,malformed,security,structured,text,toml,unicode,xml,yaml}

# --- 1. Copy mock files into Tests/Fixtures ---
echo "==> Merging mock data into Tests/Fixtures..."
cp -R "$mock/archives/"* "$fixtures/archives/"
cp -R "$mock/database/"* "$fixtures/database/"
cp -R "$mock/code/"* "$fixtures/code/"
cp -R "$mock/structured/"* "$fixtures/structured/"
cp -R "$mock/text/"* "$fixtures/text/"

# Also copy structured into category dirs if applicable
cp "$mock/structured/sample.json" "$fixtures/json/"
cp "$mock/structured/sample.jsonc" "$fixtures/json/"
cp "$mock/structured/sample.geojson" "$fixtures/json/"
cp "$mock/structured/sample.har" "$fixtures/json/"

cp "$mock/structured/sample.yaml" "$fixtures/yaml/"
cp "$mock/structured/sample.yml" "$fixtures/yaml/"

cp "$mock/structured/sample.toml" "$fixtures/toml/"

cp "$mock/structured/sample.xml" "$fixtures/xml/"
cp "$mock/structured/sample.xsd" "$fixtures/xml/"
cp "$mock/structured/sample.svg" "$fixtures/xml/"
cp "$mock/structured/sample.plist" "$fixtures/xml/"

cp "$mock/structured/sample.csv" "$fixtures/csv/"
cp "$mock/structured/sample.tsv" "$fixtures/csv/"

# --- 2. Git Diff and Patch fixtures ---
echo "==> Generating Git diff & patch fixtures..."
cat << 'EOF' > "$fixtures/diff/sample.diff"
diff --git a/Sources/PreviewXCore/PreviewModels.swift b/Sources/PreviewXCore/PreviewModels.swift
index 1234567..89abcde 100644
--- a/Sources/PreviewXCore/PreviewModels.swift
+++ b/Sources/PreviewXCore/PreviewModels.swift
@@ -10,6 +10,7 @@ public struct PreviewDocument: Codable, Equatable, Sendable {
     public let title: String
     public let subtitle: String?
+    public let version: String?
     public let blocks: [PreviewBlock]
     public let metadata: [MetadataItem]
@@ -25,4 +26,3 @@ public struct PreviewDocument: Codable, Equatable, Sendable {
-    // Legacy deprecated field
     public let warnings: [PreviewWarning]
 }
EOF

cat << 'EOF' > "$fixtures/diff/sample.patch"
From 4b825dc642cb6eb9a060e54bf8d69288fbee4904 Mon Sep 17 00:00:00 2001
From: PreviewX Team <dev@previewx.app>
Date: Sun, 4 Oct 2026 14:00:00 +0800
Subject: [PATCH] Add syntax highlighting for unified diff files

---
 Sources/PreviewXCore/SyntaxHighlighting.swift | 6 ++++++
 1 file changed, 6 insertions(+)

diff --git a/Sources/PreviewXCore/SyntaxHighlighting.swift b/Sources/PreviewXCore/SyntaxHighlighting.swift
index a1b2c3d..e4f5a6b 100644
--- a/Sources/PreviewXCore/SyntaxHighlighting.swift
+++ b/Sources/PreviewXCore/SyntaxHighlighting.swift
@@ -40,6 +40,12 @@ public enum SyntaxHighlighter {
     public static func tokens(in line: String, language: String?) -> [SyntaxToken] {
+        let lang = (language ?? "").lowercased()
+        if lang == "diff" || lang == "patch" {
+            return tokenizeDiff(line)
+        }
         let rules = LanguageRules.rules(for: language)
         return tokenize(line, rules: rules)
     }
-- 
2.39.3
EOF

cat << 'EOF' > "$fixtures/diff/multi_file.diff"
diff --git a/Package.swift b/Package.swift
index e2a1b3c..f4d5e6a 100644
--- a/Package.swift
+++ b/Package.swift
@@ -12,3 +12,4 @@ let package = Package(
         .library(name: "PreviewXCore", targets: ["PreviewXCore"]),
+        .library(name: "PreviewXDiff", targets: ["PreviewXDiff"]),
     ]
diff --git a/README.md b/README.md
index 789abcd..ef01234 100644
--- a/README.md
+++ b/README.md
@@ -1,3 +1,5 @@
 # PreviewX
+
+Fast, local-first Quick Look enhancements for macOS developers.
EOF

# Copy diff fixtures to code/ and mock/code/
cp "$fixtures/diff/sample.diff" "$fixtures/code/sample.diff"
cp "$fixtures/diff/sample.patch" "$fixtures/code/sample.patch"
cp "$fixtures/diff/sample.diff" "$mock/code/sample.diff"
cp "$fixtures/diff/sample.patch" "$mock/code/sample.patch"

# --- 3. Malformed and Invalid fixtures ---
echo "==> Generating Malformed fixtures..."
# JSON
cat << 'EOF' > "$fixtures/malformed/trailing_comma.json"
{
  "name": "PreviewX",
  "items": [
    "alpha",
    "beta",
  ],
  "count": 2,
}
EOF

cat << 'EOF' > "$fixtures/malformed/unclosed_bracket.json"
{
  "service": "previewx",
  "nodes": [
    {"id": 1, "name": "node-1"},
    {"id": 2, "name": "node-2"}
EOF

cat << 'EOF' > "$fixtures/malformed/unquoted_key.json"
{
  service: "previewx",
  enabled: true
}
EOF

# YAML
cat << 'EOF' > "$fixtures/malformed/invalid_tab.yaml"
server:
	port: 8080
	host: localhost
EOF

cat << 'EOF' > "$fixtures/malformed/unclosed_quote.yaml"
service:
  name: "PreviewX - Unclosed quote
  port: 8080
EOF

cat << 'EOF' > "$fixtures/malformed/bad_indent.yaml"
service:
  name: previewx
 port: 8080
    workers: 4
EOF

# TOML
cat << 'EOF' > "$fixtures/malformed/invalid_syntax.toml"
[service
name "previewx"
enabled true
EOF

cat << 'EOF' > "$fixtures/malformed/bad_type.toml"
[server]
port = = 8080
timeout = [1, 2, "unclosed
EOF

# XML
cat << 'EOF' > "$fixtures/malformed/unclosed_tag.xml"
<?xml version="1.0" encoding="UTF-8"?>
<service>
  <name>PreviewX</name>
  <port>8080
</service>
EOF

cat << 'EOF' > "$fixtures/malformed/mismatched_tags.xml"
<configuration>
  <database>
    <host>127.0.0.1</port>
  </database>
</configuration>
EOF

# CSV
cat << 'EOF' > "$fixtures/malformed/unclosed_quote.csv"
id,name,description
1,Ada,"Principal Engineer
2,Lin,Lead Architect,Specialist
EOF

cat << 'EOF' > "$fixtures/malformed/inconsistent_columns.csv"
name,role,department
Ada,Developer,Core
Lin,Architect
Kai,Designer,UX,ExtraColumn,Another
EOF

# Logs
cat << 'EOF' > "$fixtures/malformed/invalid_date.log"
NOT_A_DATE [INFO] Server initialization started
???-99-99T99:99:99Z [WARN] Invalid timestamp parsed
Broken log stream line without level
EOF

# --- 4. Binary fixtures ---
echo "==> Generating Binary fixtures..."
# 128 bytes pseudo-random non-text bytes
dd if=/dev/urandom of="$fixtures/binary/sample.bin" bs=128 count=1 2>/dev/null
# Mach-O 64-bit header (0xFEEDFACF)
printf '\xCF\xFA\xED\xFE\x07\x00\x00\x01\x03\x00\x00\x80\x02\x00\x00\x00\x10\x00\x00\x00\x80\x07\x00\x00\x85\x00\x20\x00\x00\x00\x00\x00' > "$fixtures/binary/sample_macho.bin"
# ELF 64-bit header (0x7F 'E' 'L' 'F')
printf '\x7F\x45\x4C\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3E\x00\x01\x00\x00\x00\x78\x00\x40\x00\x00\x00\x00\x00' > "$fixtures/binary/sample_elf.bin"
# Null bytes
printf '\x00%.0s' {1..64} > "$fixtures/binary/sample_zeroes.bin"

# --- 5. Security fixtures ---
echo "==> Generating Security fixtures..."
cat << 'EOF' > "$fixtures/security/secret_keys.env"
# Test environment secrets for SecretDetector validation
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
OPENAI_API_KEY=sk-proj-abc123def456ghi789jkl012mno345pqr678stu901vwx234
GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwxyzAB
EOF

cat << 'EOF' > "$fixtures/security/private_key.pem"
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAz/Vv3XyE4B2O1xN9fK3Z1aB2c3d4e5f6g7h8i9j0k1l2m3n4
o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3h4i5j6k7l8m9n0o1p2q3r4s5t6
u7v8w9x0y1z2a3b4c5d6e7f8g9h0i1j2k3l4m5n6o7p8q9r0s1t2u3v4w5x6y7z8
-----END RSA PRIVATE KEY-----
EOF

cat << 'EOF' > "$fixtures/security/authorization_token.json"
{
  "auth": {
    "type": "Bearer",
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSJ9.signature123456789"
  }
}
EOF

# --- 6. Database fixtures ---
echo "==> Generating Database fixtures..."
printf 'Not an SQLite database file at all' > "$fixtures/database/corrupted.sqlite"

# --- 7. Archives with security traversal ---
echo "==> Generating Security Archive fixtures..."
mkdir -p "$fixtures/.unsafe-archive"
print 'Normal entry' > "$fixtures/.unsafe-archive/safe.txt"
print 'Malicious entry escaping extraction sandbox' > "$fixtures/.unsafe-archive/escape.txt"
(cd "$fixtures/.unsafe-archive" && zip -q "$fixtures/archives/unsafe_traversal.zip" safe.txt)
python3 -c "
import zipfile
with zipfile.ZipFile('$fixtures/archives/unsafe_traversal.zip', 'a') as zf:
    zf.writestr('../evil_traversal.txt', 'malicious content')
" 2>/dev/null || true

tar -cf "$fixtures/archives/unsafe_traversal.tar" -C "$fixtures/.unsafe-archive" safe.txt
python3 -c "
import tarfile, io
with tarfile.open('$fixtures/archives/unsafe_traversal.tar', 'a') as tf:
    data = b'malicious content'
    ti = tarfile.TarInfo('../evil_traversal.txt')
    ti.size = len(data)
    tf.addfile(ti, io.BytesIO(data))
" 2>/dev/null || true
rm -rf "$fixtures/.unsafe-archive"

# --- 8. Huge fixtures ---
echo "==> Generating Huge / Budget fixtures..."
# 22,000 lines text file (triggers line budget warning > 20,000)
python3 -c "
with open('$fixtures/huge/large_text.txt', 'w') as f:
    for i in range(1, 22001):
        f.write(f'Log line {i}: PreviewX high-throughput stream testing\n')
"

# 1,200 rows CSV (triggers maxRows 1,000 warning in DelimitedTextParser)
python3 -c "
with open('$fixtures/huge/large_table.csv', 'w') as f:
    f.write('id,index,uuid,status\n')
    for i in range(1, 1201):
        f.write(f'{i},row_{i},previewx-uuid-{i},active\n')
"

# 9MB binary file (triggers maxBytesRead 8MB budget error)
dd if=/dev/zero of="$fixtures/huge/exceed_budget.bin" bs=1048576 count=9 2>/dev/null

# --- 9. Additional real-world structured & code fixtures ---
echo "==> Generating Additional Real-world fixtures..."
cat << 'EOF' > "$fixtures/json/package.json"
{
  "name": "previewx-app",
  "version": "1.0.0",
  "description": "Quick Look preview enhancement platform",
  "main": "index.js",
  "scripts": {
    "test": "swift test",
    "build": "make build"
  },
  "keywords": ["macos", "quicklook", "swift"],
  "author": "PreviewX Contributors",
  "license": "MIT"
}
EOF

cat << 'EOF' > "$fixtures/yaml/docker-compose.yml"
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    restart: always
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
EOF

cat << 'EOF' > "$fixtures/yaml/k8s-pod.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: previewx-worker
  labels:
    app: previewx
spec:
  containers:
    - name: worker
      image: alpine:latest
      command: ["sh", "-c", "echo PreviewX worker running"]
EOF

cat << 'EOF' > "$fixtures/toml/Cargo.toml"
[package]
name = "previewx-core"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.28", features = ["full"] }
EOF

cat << 'EOF' > "$fixtures/xml/pom.xml"
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.previewx</groupId>
  <artifactId>previewx-core</artifactId>
  <version>1.0.0</version>
</project>
EOF

cat << 'EOF' > "$fixtures/csv/complex_quoted.csv"
"id","full_name","address","notes"
"101","Ada Lovelace","12 St James's Square, London","Co-founder, \"Analytical Engine\" Pioneer"
"102","Grace Hopper","Arlington, Virginia","Developed early compiler; \"Bug\" term originator"
EOF

cat << 'EOF' > "$fixtures/code/sample.rb"
# Ruby sample fixture
class Greeting
  attr_reader :name

  def initialize(name = "PreviewX")
    @name = name
  end

  def salute
    puts "Hello, #{@name}!"
  end
end

Greeting.new.salute
EOF

cat << 'EOF' > "$fixtures/code/sample.lua"
-- Lua sample fixture
local preview = {
    name = "PreviewX",
    version = "1.0.0"
}

function preview.greet()
    print("Welcome to " .. preview.name)
end

preview.greet()
EOF

cat << 'EOF' > "$fixtures/code/CMakeLists.txt"
cmake_minimum_required(VERSION 3.20)
project(PreviewX C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

add_executable(previewx main.cpp)
EOF

cat << 'EOF' > "$fixtures/code/sample.graphql"
type Query {
  user(id: ID!): User
  previews(limit: Int = 10): [PreviewDocument!]!
}

type User {
  id: ID!
  username: String!
  email: String
}
EOF

cat << 'EOF' > "$fixtures/code/sample.proto"
syntax = "proto3";

package previewx;

message DocumentRequest {
  string file_path = 1;
  int64 max_bytes = 2;
}

message DocumentResponse {
  string title = 1;
  string subtitle = 2;
  repeated string blocks = 3;
}
EOF

cat << 'EOF' > "$fixtures/code/sample.vue"
<template>
  <div class="preview-card">
    <h1>{{ title }}</h1>
  </div>
</template>

<script>
export default {
  data() {
    return {
      title: "PreviewX"
    };
  }
};
</script>

<style scoped>
.preview-card {
  color: steelblue;
}
</style>
EOF

cat << 'EOF' > "$fixtures/code/sample.svelte"
<script>
  let name = 'PreviewX';
</script>

<main>
  <h1>Hello {name}!</h1>
</main>

<style>
  main {
    text-align: center;
    padding: 1em;
  }
</style>
EOF

# Copy additional code fixtures to mock/code as well
for f in sample.rb sample.lua CMakeLists.txt sample.graphql sample.proto sample.vue sample.svelte; do
  cp "$fixtures/code/$f" "$mock/code/$f"
done

# --- 10. Additional Text, Logs and Unicode ---
echo "==> Generating Text, Logs and Unicode fixtures..."
cat << 'EOF' > "$fixtures/text/advanced.md"
# PreviewX Extended Markdown

A local-first, safe preview tool for macOS.

## Feature Checklist
- [x] Fast Quick Look
- [x] Syntax Highlighting
- [x] Unified Diff Viewer
- [x] Secret Redaction

> Preview first, open later.

```swift
func greet() {
    print("Hello from PreviewX")
}
```
EOF

cat << 'EOF' > "$fixtures/logs/nginx_access.log"
127.0.0.1 - - [04/Oct/2026:14:00:01 +0800] "GET /index.html HTTP/1.1" 200 612 "-" "Mozilla/5.0"
192.168.1.100 - - [04/Oct/2026:14:00:02 +0800] "POST /api/v1/preview HTTP/1.1" 201 1420 "-" "PreviewX-CLI"
10.0.0.5 - - [04/Oct/2026:14:00:03 +0800] "GET /unauthorized HTTP/1.1" 403 162 "-" "curl/7.79.1"
EOF

# UTF-8 BOM
printf '\xEF\xBB\xBFPreviewX UTF-8 with Byte Order Mark\n' > "$fixtures/unicode/utf8_bom.txt"

cat << 'EOF' > "$fixtures/unicode/cjk_multilingual.txt"
PreviewX 多语言测试样本
简体中文：快速预览，安全第一，原生体验。
繁體中文：快速預覽，安全第一，原生體驗。
日本語：スペースキーで素早くプレビュー。
한국어：가장 빠르고 안전한 퀵룩 미리보기.
Arabic: معاينة سريعة وآمنة
Emoji: 🚀 ⚡ 🔒 💻 🛠️ 📄 🎨
EOF

# Remove any .DS_Store
find "$fixtures" "$mock" -name ".DS_Store" -delete 2>/dev/null || true

echo "==> Complete! Total fixtures count:"
find "$fixtures" -type f | wc -l

