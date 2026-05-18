import AppKit

@MainActor
enum StatusIconFactory {
    static func icon(for status: String) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
        }

        NSGraphicsContext.current?.shouldAntialias = true
        drawWutongLeaf(in: NSRect(x: 1, y: 1, width: 14, height: 16), status: status)
        drawStatusDot(in: NSRect(x: 14, y: 1.5, width: 6.5, height: 6.5), status: status)

        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription(for: status)
        return image
    }

    /// 绘制一片简化的梧桐叶：五裂掌状叶 + 叶柄
    private static func drawWutongLeaf(in rect: NSRect, status: String) {
        let color = glyphColor(for: status)
        color.setStroke()
        color.setFill()

        let cx = rect.midX
        let bottom = rect.minY
        let top = rect.maxY

        // 叶柄
        let stem = NSBezierPath()
        stem.lineWidth = 1.4
        stem.lineCapStyle = .round
        stem.move(to: NSPoint(x: cx, y: bottom))
        stem.line(to: NSPoint(x: cx, y: bottom + rect.height * 0.3))
        stem.stroke()

        // 五裂掌状叶轮廓
        let leaf = NSBezierPath()
        let baseY = bottom + rect.height * 0.25
        let leafH = top - baseY
        let leafW = rect.width

        // 从底部中心开始，逆时针画五个裂片
        leaf.move(to: NSPoint(x: cx, y: baseY))

        // 右下裂片
        leaf.curve(
            to: NSPoint(x: cx + leafW * 0.42, y: baseY + leafH * 0.25),
            controlPoint1: NSPoint(x: cx + leafW * 0.15, y: baseY + leafH * 0.05),
            controlPoint2: NSPoint(x: cx + leafW * 0.38, y: baseY + leafH * 0.1)
        )
        // 右下凹口
        leaf.curve(
            to: NSPoint(x: cx + leafW * 0.28, y: baseY + leafH * 0.4),
            controlPoint1: NSPoint(x: cx + leafW * 0.4, y: baseY + leafH * 0.32),
            controlPoint2: NSPoint(x: cx + leafW * 0.32, y: baseY + leafH * 0.35)
        )
        // 右上裂片
        leaf.curve(
            to: NSPoint(x: cx + leafW * 0.48, y: baseY + leafH * 0.7),
            controlPoint1: NSPoint(x: cx + leafW * 0.38, y: baseY + leafH * 0.48),
            controlPoint2: NSPoint(x: cx + leafW * 0.5, y: baseY + leafH * 0.58)
        )
        // 右上凹口
        leaf.curve(
            to: NSPoint(x: cx + leafW * 0.2, y: baseY + leafH * 0.72),
            controlPoint1: NSPoint(x: cx + leafW * 0.42, y: baseY + leafH * 0.74),
            controlPoint2: NSPoint(x: cx + leafW * 0.3, y: baseY + leafH * 0.72)
        )
        // 顶部裂片
        leaf.curve(
            to: NSPoint(x: cx, y: baseY + leafH),
            controlPoint1: NSPoint(x: cx + leafW * 0.15, y: baseY + leafH * 0.82),
            controlPoint2: NSPoint(x: cx + leafW * 0.08, y: baseY + leafH * 0.95)
        )
        // 左上凹口（对称）
        leaf.curve(
            to: NSPoint(x: cx - leafW * 0.2, y: baseY + leafH * 0.72),
            controlPoint1: NSPoint(x: cx - leafW * 0.08, y: baseY + leafH * 0.95),
            controlPoint2: NSPoint(x: cx - leafW * 0.15, y: baseY + leafH * 0.82)
        )
        // 左上裂片
        leaf.curve(
            to: NSPoint(x: cx - leafW * 0.48, y: baseY + leafH * 0.7),
            controlPoint1: NSPoint(x: cx - leafW * 0.3, y: baseY + leafH * 0.72),
            controlPoint2: NSPoint(x: cx - leafW * 0.42, y: baseY + leafH * 0.74)
        )
        // 左下凹口
        leaf.curve(
            to: NSPoint(x: cx - leafW * 0.28, y: baseY + leafH * 0.4),
            controlPoint1: NSPoint(x: cx - leafW * 0.5, y: baseY + leafH * 0.58),
            controlPoint2: NSPoint(x: cx - leafW * 0.38, y: baseY + leafH * 0.48)
        )
        // 左下裂片
        leaf.curve(
            to: NSPoint(x: cx - leafW * 0.42, y: baseY + leafH * 0.25),
            controlPoint1: NSPoint(x: cx - leafW * 0.32, y: baseY + leafH * 0.35),
            controlPoint2: NSPoint(x: cx - leafW * 0.4, y: baseY + leafH * 0.32)
        )
        // 回到底部
        leaf.curve(
            to: NSPoint(x: cx, y: baseY),
            controlPoint1: NSPoint(x: cx - leafW * 0.38, y: baseY + leafH * 0.1),
            controlPoint2: NSPoint(x: cx - leafW * 0.15, y: baseY + leafH * 0.05)
        )

        leaf.fill()

        // 叶脉：中脉 + 两对侧脉
        let vein = NSBezierPath()
        vein.lineWidth = 0.7
        vein.lineCapStyle = .round
        NSColor.windowBackgroundColor.withAlphaComponent(0.5).setStroke()

        // 中脉
        vein.move(to: NSPoint(x: cx, y: baseY))
        vein.line(to: NSPoint(x: cx, y: baseY + leafH * 0.88))

        // 右侧脉
        vein.move(to: NSPoint(x: cx, y: baseY + leafH * 0.35))
        vein.line(to: NSPoint(x: cx + leafW * 0.32, y: baseY + leafH * 0.6))

        // 左侧脉
        vein.move(to: NSPoint(x: cx, y: baseY + leafH * 0.35))
        vein.line(to: NSPoint(x: cx - leafW * 0.32, y: baseY + leafH * 0.6))

        vein.stroke()
    }

    private static func drawStatusDot(in rect: NSRect, status: String) {
        let shadow = NSBezierPath(ovalIn: rect.insetBy(dx: -1.0, dy: -1.0))
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        shadow.fill()

        let dot = NSBezierPath(ovalIn: rect)
        dotColor(for: status).setFill()
        dot.fill()
    }

    private static func glyphColor(for status: String) -> NSColor {
        switch status {
        case "失败", "离线":
            return NSColor.secondaryLabelColor
        default:
            return NSColor.labelColor
        }
    }

    private static func dotColor(for status: String) -> NSColor {
        switch status {
        case "在线":
            return NSColor.systemGreen
        case "需认证", "登录中", "检测中":
            return NSColor.systemOrange
        case "失败", "离线":
            return NSColor.systemRed
        default:
            return NSColor.systemGray
        }
    }

    private static func accessibilityDescription(for status: String) -> String {
        switch status {
        case "在线":
            return "HUST 校园网在线"
        case "需认证":
            return "HUST 校园网需要认证"
        case "登录中":
            return "HUST 校园网正在登录"
        case "检测中":
            return "HUST 校园网正在检测"
        case "失败":
            return "HUST 校园网登录失败"
        case "离线":
            return "HUST 校园网离线"
        default:
            return "HUST 校园网"
        }
    }
}
