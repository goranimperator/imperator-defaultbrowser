import AppKit

enum SVGRenderer {
    struct Element {
        enum Kind {
            case path(String)
            case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
            case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rx: CGFloat, ry: CGFloat)
            case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
            case polyline(points: [CGPoint])
            case polygon(points: [CGPoint])
        }
        let kind: Kind
        let shouldFill: Bool
    }

    static func render(elements: [Element], size: CGFloat, strokeWidth: CGFloat, color: NSColor = .black) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = size / 24.0
            let transform = NSAffineTransform()
            transform.scaleX(by: scale, yBy: scale)
            transform.concat()

            color.setStroke()
            color.setFill()

            for element in elements {
                let bezier = makePath(for: element.kind)
                bezier.lineWidth = strokeWidth
                bezier.lineCapStyle = .round
                bezier.lineJoinStyle = .round
                if element.shouldFill { bezier.fill() }
                bezier.stroke()
            }
            return true
        }
    }

    static func makePath(for kind: Element.Kind) -> NSBezierPath {
        switch kind {
        case .path(let d):
            return SVGPathParser.parse(d)
        case .circle(let cx, let cy, let r):
            return NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        case .rect(let x, let y, let w, let h, let rx, let ry):
            return NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: rx, yRadius: ry)
        case .line(let x1, let y1, let x2, let y2):
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x1, y: y1))
            p.line(to: NSPoint(x: x2, y: y2))
            return p
        case .polyline(let points):
            let p = NSBezierPath()
            guard let first = points.first else { return p }
            p.move(to: first)
            for pt in points.dropFirst() { p.line(to: pt) }
            return p
        case .polygon(let points):
            let p = NSBezierPath()
            guard let first = points.first else { return p }
            p.move(to: first)
            for pt in points.dropFirst() { p.line(to: pt) }
            p.close()
            return p
        }
    }

    static func parseElement(_ svg: String) -> Element? {
        let s = svg.trimmingCharacters(in: .whitespaces)

        if s.hasPrefix("<path") {
            guard let d = attr(s, "d") else { return nil }
            return Element(kind: .path(d), shouldFill: hasFill(s))
        }
        if s.hasPrefix("<circle") {
            guard let cx = numAttr(s, "cx"), let cy = numAttr(s, "cy"), let r = numAttr(s, "r") else { return nil }
            return Element(kind: .circle(cx: cx, cy: cy, r: r), shouldFill: hasFill(s))
        }
        if s.hasPrefix("<rect") {
            let x = numAttr(s, "x") ?? 0
            let y = numAttr(s, "y") ?? 0
            guard let w = numAttr(s, "width"), let h = numAttr(s, "height") else { return nil }
            let rx = numAttr(s, "rx") ?? 0
            let ry = numAttr(s, "ry") ?? rx
            return Element(kind: .rect(x: x, y: y, width: w, height: h, rx: rx, ry: ry), shouldFill: hasFill(s))
        }
        if s.hasPrefix("<line") {
            guard let x1 = numAttr(s, "x1"), let y1 = numAttr(s, "y1"),
                  let x2 = numAttr(s, "x2"), let y2 = numAttr(s, "y2") else { return nil }
            return Element(kind: .line(x1: x1, y1: y1, x2: x2, y2: y2), shouldFill: false)
        }
        if s.hasPrefix("<polyline") {
            guard let pts = pointsAttr(s) else { return nil }
            return Element(kind: .polyline(points: pts), shouldFill: false)
        }
        if s.hasPrefix("<polygon") {
            guard let pts = pointsAttr(s) else { return nil }
            return Element(kind: .polygon(points: pts), shouldFill: hasFill(s))
        }
        if s.hasPrefix("<ellipse") {
            guard let cx = numAttr(s, "cx"), let cy = numAttr(s, "cy"),
                  let rx = numAttr(s, "rx"), let ry = numAttr(s, "ry") else { return nil }
            return Element(kind: .rect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2, rx: rx, ry: ry), shouldFill: hasFill(s))
        }
        return nil
    }

    private static func hasFill(_ s: String) -> Bool {
        s.contains("fill=\"currentColor\"")
    }

    private static func attr(_ s: String, _ name: String) -> String? {
        let pattern = "\(name)=\""
        guard let start = s.range(of: pattern) else { return nil }
        let rest = s[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func numAttr(_ s: String, _ name: String) -> CGFloat? {
        guard let val = attr(s, name) else { return nil }
        return CGFloat(Double(val) ?? 0)
    }

    private static func pointsAttr(_ s: String) -> [CGPoint]? {
        guard let raw = attr(s, "points") else { return nil }
        let nums = raw.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard nums.count >= 2, nums.count % 2 == 0 else { return nil }
        var pts: [CGPoint] = []
        for i in stride(from: 0, to: nums.count, by: 2) {
            pts.append(CGPoint(x: nums[i], y: nums[i+1]))
        }
        return pts
    }
}

// MARK: - SVG Path Data Parser

enum SVGPathParser {
    static func parse(_ d: String) -> NSBezierPath {
        let path = NSBezierPath()
        var sc = Scanner(d)
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl = CGPoint.zero
        var prevCmd: Character = " "

        while let rawCmd = sc.nextCommand() {
            let isRel = rawCmd.isLowercase
            let cmd = Character(rawCmd.uppercased())

            switch cmd {
            case "M":
                guard var p = sc.nextPoint() else { break }
                if isRel { p = p + cur }
                path.move(to: p)
                cur = p; start = p
                while sc.hasNextNumber {
                    guard var p = sc.nextPoint() else { break }
                    if isRel { p = p + cur }
                    path.line(to: p); cur = p
                }

            case "L":
                while sc.hasNextNumber {
                    guard var p = sc.nextPoint() else { break }
                    if isRel { p = p + cur }
                    path.line(to: p); cur = p
                }

            case "H":
                while sc.hasNextNumber {
                    guard let v = sc.nextNumber() else { break }
                    let x = isRel ? cur.x + v : v
                    let p = CGPoint(x: x, y: cur.y)
                    path.line(to: p); cur = p
                }

            case "V":
                while sc.hasNextNumber {
                    guard let v = sc.nextNumber() else { break }
                    let y = isRel ? cur.y + v : v
                    let p = CGPoint(x: cur.x, y: y)
                    path.line(to: p); cur = p
                }

            case "C":
                while sc.hasNextNumber {
                    guard var c1 = sc.nextPoint(), var c2 = sc.nextPoint(), var p = sc.nextPoint() else { break }
                    if isRel { c1 = c1 + cur; c2 = c2 + cur; p = p + cur }
                    path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                    lastCtrl = c2; cur = p
                }

            case "S":
                while sc.hasNextNumber {
                    guard var c2 = sc.nextPoint(), var p = sc.nextPoint() else { break }
                    if isRel { c2 = c2 + cur; p = p + cur }
                    let c1 = (prevCmd == "C" || prevCmd == "S")
                        ? CGPoint(x: 2 * cur.x - lastCtrl.x, y: 2 * cur.y - lastCtrl.y)
                        : cur
                    path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                    lastCtrl = c2; cur = p
                }

            case "Q":
                while sc.hasNextNumber {
                    guard var qc = sc.nextPoint(), var p = sc.nextPoint() else { break }
                    if isRel { qc = qc + cur; p = p + cur }
                    let c1 = CGPoint(x: cur.x + 2.0/3.0 * (qc.x - cur.x), y: cur.y + 2.0/3.0 * (qc.y - cur.y))
                    let c2 = CGPoint(x: p.x + 2.0/3.0 * (qc.x - p.x), y: p.y + 2.0/3.0 * (qc.y - p.y))
                    path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                    lastCtrl = qc; cur = p
                }

            case "T":
                while sc.hasNextNumber {
                    guard var p = sc.nextPoint() else { break }
                    if isRel { p = p + cur }
                    let qc = (prevCmd == "Q" || prevCmd == "T")
                        ? CGPoint(x: 2 * cur.x - lastCtrl.x, y: 2 * cur.y - lastCtrl.y)
                        : cur
                    let c1 = CGPoint(x: cur.x + 2.0/3.0 * (qc.x - cur.x), y: cur.y + 2.0/3.0 * (qc.y - cur.y))
                    let c2 = CGPoint(x: p.x + 2.0/3.0 * (qc.x - p.x), y: p.y + 2.0/3.0 * (qc.y - p.y))
                    path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                    lastCtrl = qc; cur = p
                }

            case "A":
                while sc.hasNextNumber {
                    guard let rx = sc.nextNumber(), let ry = sc.nextNumber(),
                          let rot = sc.nextNumber(), let la = sc.nextNumber(), let sw = sc.nextNumber(),
                          var p = sc.nextPoint() else { break }
                    if isRel { p = p + cur }
                    addArc(to: path, from: cur, to: p, rx: abs(rx), ry: abs(ry),
                           rotation: rot, largeArc: la != 0, sweep: sw != 0)
                    cur = p
                }

            case "Z":
                path.close()
                cur = start

            default: break
            }
            prevCmd = cmd
        }
        return path
    }

    private static func addArc(to path: NSBezierPath, from p1: CGPoint, to p2: CGPoint,
                                rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat,
                                largeArc: Bool, sweep: Bool) {
        guard p1 != p2 else { return }
        var rx = rxIn, ry = ryIn
        guard rx > 0, ry > 0 else { path.line(to: p2); return }

        let cosA = cos(rotation * .pi / 180)
        let sinA = sin(rotation * .pi / 180)

        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosA * dx + sinA * dy
        let y1p = -sinA * dx + cosA * dy

        var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let sq = sqrt(lambda)
            rx *= sq; ry *= sq
            lambda = 1
        }

        let num = max(0, rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p)
        let den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
        let sq = den > 0 ? sqrt(num / den) : 0
        let sign: CGFloat = (largeArc == sweep) ? -1 : 1
        let cxp = sign * sq * rx * y1p / ry
        let cyp = sign * sq * (-ry) * x1p / rx

        let cx = cosA * cxp - sinA * cyp + (p1.x + p2.x) / 2
        let cy = sinA * cxp + cosA * cyp + (p1.y + p2.y) / 2

        let theta1 = angle(ux: 1, uy: 0, vx: (x1p - cxp) / rx, vy: (y1p - cyp) / ry)
        var dtheta = angle(ux: (x1p - cxp) / rx, uy: (y1p - cyp) / ry,
                           vx: (-x1p - cxp) / rx, vy: (-y1p - cyp) / ry)

        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / CGFloat(segments)
        let t = tan(delta / 2)
        let alpha = sin(delta) * (sqrt(4 + 3 * t * t) - 1) / 3

        var theta = theta1

        for _ in 0..<segments {
            let nextTheta = theta + delta
            let cosT = cos(theta), sinT = sin(theta)
            let cosNT = cos(nextTheta), sinNT = sin(nextTheta)

            let ep1x = cosA * rx * cosT - sinA * ry * sinT + cx
            let ep1y = sinA * rx * cosT + cosA * ry * sinT + cy
            let ep2x = cosA * rx * cosNT - sinA * ry * sinNT + cx
            let ep2y = sinA * rx * cosNT + cosA * ry * sinNT + cy

            let d1x = -cosA * rx * sinT - sinA * ry * cosT
            let d1y = -sinA * rx * sinT + cosA * ry * cosT
            let d2x = -cosA * rx * sinNT - sinA * ry * cosNT
            let d2y = -sinA * rx * sinNT + cosA * ry * cosNT

            let cp1 = CGPoint(x: ep1x + alpha * d1x, y: ep1y + alpha * d1y)
            let cp2 = CGPoint(x: ep2x - alpha * d2x, y: ep2y - alpha * d2y)
            let end = CGPoint(x: ep2x, y: ep2y)

            path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
            theta = nextTheta
        }
    }

    private static func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        var a = len > 0 ? acos(max(-1, min(1, dot / len))) : 0
        if ux * vy - uy * vx < 0 { a = -a }
        return a
    }
}

// MARK: - Path Scanner

private struct Scanner {
    private let chars: [Character]
    private var idx: Int

    init(_ string: String) {
        chars = Array(string)
        idx = 0
    }

    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard idx < chars.count, chars[idx].isLetter else { return nil }
        let c = chars[idx]; idx += 1; return c
    }

    var hasNextNumber: Bool {
        var i = idx
        while i < chars.count && isSeparator(chars[i]) { i += 1 }
        guard i < chars.count else { return false }
        let c = chars[i]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func nextNumber() -> CGFloat? {
        skipSeparators()
        guard idx < chars.count else { return nil }
        let start = idx

        if idx < chars.count && (chars[idx] == "-" || chars[idx] == "+") { idx += 1 }
        var hasDot = false
        while idx < chars.count && (chars[idx].isNumber || (chars[idx] == "." && !hasDot)) {
            if chars[idx] == "." { hasDot = true }
            idx += 1
        }
        if idx < chars.count && (chars[idx] == "e" || chars[idx] == "E") {
            idx += 1
            if idx < chars.count && (chars[idx] == "-" || chars[idx] == "+") { idx += 1 }
            while idx < chars.count && chars[idx].isNumber { idx += 1 }
        }
        guard idx > start else { return nil }
        return CGFloat(Double(String(chars[start..<idx])) ?? 0)
    }

    mutating func nextPoint() -> CGPoint? {
        guard let x = nextNumber(), let y = nextNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    private mutating func skipSeparators() {
        while idx < chars.count && isSeparator(chars[idx]) { idx += 1 }
    }

    private func isSeparator(_ c: Character) -> Bool {
        c == " " || c == "," || c == "\n" || c == "\r" || c == "\t"
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
