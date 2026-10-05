import Foundation
import AppKit
import CoreGraphics

struct ShowcaseItem {
    let filename: String
    let badgeText: String
    let badgeColor: NSColor
    let headline: String
    let subheadline: String
    let glowColor: NSColor
}

let items: [ShowcaseItem] = [
    ShowcaseItem(
        filename: "quicklook-diff-patch-highlight.png",
        badgeText: "⚡️ 毫秒级预览 · 免启大型 IDE",
        badgeColor: NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1.0),
        headline: "代码语法高亮与 Git 差异检视",
        subheadline: "内置 40+ 语言精准语法分词，智能行号导航与文件元数据，选中文件空格即看",
        glowColor: NSColor(red: 0.12, green: 0.35, blue: 0.75, alpha: 0.28)
    ),
    ShowcaseItem(
        filename: "quicklook-sqlite-database-table.png",
        badgeText: "📊 原生数据表格 · 多表结构展示",
        badgeColor: NSColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1.0),
        headline: "SQLite 数据库与结构化表格",
        subheadline: "直观检视数据库表结构与多行数据，自动列宽对齐与格式化排版，无需专用客户端",
        glowColor: NSColor(red: 0.45, green: 0.20, blue: 0.75, alpha: 0.28)
    ),
    ShowcaseItem(
        filename: "quicklook-archive-tree-jar.png",
        badgeText: "📦 免解压流式浏览 · 路径安全校验",
        badgeColor: NSColor(red: 0.25, green: 0.75, blue: 0.85, alpha: 1.0),
        headline: "压缩归档免解压目录树",
        subheadline: "ZIP, TAR, GZ, 7Z, JAR 等无损深层展开浏览，智能防御路径穿越风险",
        glowColor: NSColor(red: 0.10, green: 0.55, blue: 0.65, alpha: 0.28)
    ),
    ShowcaseItem(
        filename: "app-settings-supported-formats.png",
        badgeText: "🧩 全面格式覆盖 · 灵活开关映射",
        badgeColor: NSColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1.0),
        headline: "支持 110+ 种格式与开发扩展名",
        subheadline: "主流编程语言、开发配置、数据交换格式与通用二进制头部，支持分类即时检索",
        glowColor: NSColor(red: 0.75, green: 0.35, blue: 0.10, alpha: 0.26)
    ),
    ShowcaseItem(
        filename: "app-settings-preferences.png",
        badgeText: "🔒 100% 本地运行 · 隐私安全无妥协",
        badgeColor: NSColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1.0),
        headline: "纯本地优先 · 绝无网络数据外发",
        subheadline: "严格沙箱隔离与只读保护，敏感凭据本地预警，零数据收集、零追踪遥测",
        glowColor: NSColor(red: 0.15, green: 0.60, blue: 0.35, alpha: 0.25)
    )
]

let canvasWidth: CGFloat = 2880
let canvasHeight: CGFloat = 1800

let inputDir = URL(fileURLWithPath: "docs/imags/raw")
let outputDir = URL(fileURLWithPath: "docs/imags")

for item in items {
    let sourceURL = inputDir.appendingPathComponent(item.filename)
    guard let sourceImage = NSImage(contentsOf: sourceURL) else {
        print("⚠️ 未找到源图: \(sourceURL.path)")
        continue
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    // 先在带 Alpha 的高质量 Context 中绘制完整画面，确保所有半透明微光、高斯阴影与边框完美抗锯齿混合
    guard let context = CGContext(
        data: nil,
        width: Int(canvasWidth),
        height: Int(canvasHeight),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("⚠️ 无法创建 CGContext")
        continue
    }

    let ctx = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // 1. 绘制深邃细腻的深空蓝灰底色渐变
    let bgColors = [
        NSColor(red: 0.055, green: 0.082, blue: 0.135, alpha: 1.0).cgColor,
        NSColor(red: 0.020, green: 0.031, blue: 0.055, alpha: 1.0).cgColor
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    context.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: canvasWidth / 2, y: canvasHeight),
        end: CGPoint(x: canvasWidth / 2, y: 0),
        options: []
    )

    // 2. 绘制顶部广域柔和环境微光 (Ambient Light)
    context.saveGState()
    let glowColors = [
        item.glowColor.withAlphaComponent(0.35).cgColor,
        item.glowColor.withAlphaComponent(0.12).cgColor,
        item.glowColor.withAlphaComponent(0.0).cgColor
    ] as CFArray
    let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0])!
    context.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: canvasWidth / 2, y: canvasHeight - 160),
        startRadius: 0,
        endCenter: CGPoint(x: canvasWidth / 2, y: canvasHeight - 160),
        endRadius: 1100,
        options: []
    )
    context.restoreGState()

    // 3. 绘制顶部徽章 Badge (Pill)
    let badgeFont = NSFont.systemFont(ofSize: 28, weight: .bold)
    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: badgeFont,
        .foregroundColor: item.badgeColor
    ]
    let badgeString = NSAttributedString(string: item.badgeText, attributes: badgeAttrs)
    let badgeSize = badgeString.size()
    let badgePaddingH: CGFloat = 30
    let badgePaddingV: CGFloat = 12
    let badgeRectWidth = badgeSize.width + badgePaddingH * 2
    let badgeRectHeight = badgeSize.height + badgePaddingV * 2
    let badgeY = canvasHeight - 175
    let badgeX = (canvasWidth - badgeRectWidth) / 2
    let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeRectWidth, height: badgeRectHeight)

    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRectHeight / 2, yRadius: badgeRectHeight / 2)
    item.badgeColor.withAlphaComponent(0.15).setFill()
    badgePath.fill()
    item.badgeColor.withAlphaComponent(0.40).setStroke()
    badgePath.lineWidth = 1.5
    badgePath.stroke()

    badgeString.draw(at: NSPoint(x: badgeX + badgePaddingH, y: badgeY + badgePaddingV - 2))

    // 4. 绘制大标题 (Headline)
    let headlineFont = NSFont.systemFont(ofSize: 68, weight: .bold)
    let headlineStyle = NSMutableParagraphStyle()
    headlineStyle.alignment = .center
    let headlineAttrs: [NSAttributedString.Key: Any] = [
        .font: headlineFont,
        .foregroundColor: NSColor.white,
        .paragraphStyle: headlineStyle
    ]
    let headlineString = NSAttributedString(string: item.headline, attributes: headlineAttrs)
    let headlineHeight = headlineString.size().height
    let headlineY = badgeY - headlineHeight - 20
    let headlineRect = NSRect(x: 100, y: headlineY, width: canvasWidth - 200, height: headlineHeight)
    headlineString.draw(in: headlineRect)

    // 5. 绘制副标题 (Subheadline)
    let subheadlineFont = NSFont.systemFont(ofSize: 32, weight: .regular)
    let subheadlineStyle = NSMutableParagraphStyle()
    subheadlineStyle.alignment = .center
    let subheadlineAttrs: [NSAttributedString.Key: Any] = [
        .font: subheadlineFont,
        .foregroundColor: NSColor(white: 0.82, alpha: 1.0),
        .paragraphStyle: subheadlineStyle
    ]
    let subheadlineString = NSAttributedString(string: item.subheadline, attributes: subheadlineAttrs)
    let subheadlineHeight = subheadlineString.size().height
    let subheadlineY = headlineY - subheadlineHeight - 16
    let subheadlineRect = NSRect(x: 200, y: subheadlineY, width: canvasWidth - 400, height: subheadlineHeight)
    subheadlineString.draw(in: subheadlineRect)

    // 6. 居中排布悬浮窗口 Mockup
    let availableBottom = subheadlineY - 45
    let targetBottomMargin: CGFloat = 65
    let maxMockupHeight = availableBottom - targetBottomMargin
    let maxMockupWidth: CGFloat = 2200

    let srcSize = sourceImage.size
    let scale = min(maxMockupWidth / srcSize.width, maxMockupHeight / srcSize.height)
    let windowWidth = srcSize.width * scale
    let windowHeight = srcSize.height * scale
    let windowX = (canvasWidth - windowWidth) / 2
    let windowY = targetBottomMargin + (availableBottom - targetBottomMargin - windowHeight) / 2
    let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)

    // 6.1 绘制窗口多重柔和投影 (macOS Window Shadow)
    context.saveGState()
    let shadowColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.70).cgColor
    context.setShadow(offset: CGSize(width: 0, height: -30), blur: 80, color: shadowColor)
    let shadowClipPath = NSBezierPath(roundedRect: windowRect, xRadius: 18, yRadius: 18)
    NSColor(white: 0.12, alpha: 1.0).setFill()
    shadowClipPath.fill()
    context.restoreGState()

    // 6.2 绘制窗口原图并应用优雅圆角裁剪
    context.saveGState()
    let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: 18, yRadius: 18)
    windowPath.addClip()
    sourceImage.draw(in: windowRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    context.restoreGState()

    // 6.3 绘制窗口外层精致高光边框 (Subtle Glass Border)
    let borderPath = NSBezierPath(roundedRect: windowRect, xRadius: 18, yRadius: 18)
    NSColor(white: 1.0, alpha: 0.20).setStroke()
    borderPath.lineWidth = 2.0
    borderPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    // 7. 转为严格纯 RGB (无 Alpha 通道) 输出，完全符合 App Store 要求
    guard let alphaCGImage = context.makeImage() else {
        print("⚠️ 无法生成 CGImage: \(item.filename)")
        continue
    }

    guard let rgbContext = CGContext(
        data: nil,
        width: Int(canvasWidth),
        height: Int(canvasHeight),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        print("⚠️ 无法创建 RGB CGContext")
        continue
    }

    rgbContext.draw(alphaCGImage, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

    guard let finalCGImage = rgbContext.makeImage() else {
        print("⚠️ 无法导出 RGB CGImage")
        continue
    }

    let bitmapRep = NSBitmapImageRep(cgImage: finalCGImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("⚠️ 无法生成 PNG 数据: \(item.filename)")
        continue
    }

    let destURL = outputDir.appendingPathComponent(item.filename)
    try! pngData.write(to: destURL)
    print("✅ 成功生成 2880x1800 商店美化宣传图: \(destURL.path)")
}
