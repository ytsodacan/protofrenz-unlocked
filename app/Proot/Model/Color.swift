import SwiftUI

struct RGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(r: UInt8((v >> 16) & 255), g: UInt8((v >> 8) & 255), b: UInt8(v & 255))
    }

    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: UInt8(max(0, min(1, r)) * 255), g: UInt8(max(0, min(1, g)) * 255), b: UInt8(max(0, min(1, b)) * 255))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var isDark: Bool { Int(r) + Int(g) + Int(b) < 12 }
    var rgb565: UInt16 { (UInt16(r & 0xF8) << 8) | (UInt16(g & 0xFC) << 3) | UInt16(b >> 3) }
    var rgb332: UInt8 { (r & 0xE0) | ((g >> 3) & 0x1C) | (b >> 6) }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(Double(a) + (Double(b) - Double(a)) * t) }
        return RGB(r: m(r, o.r), g: m(g, o.g), b: m(b, o.b))
    }

    static func hsv(_ h0: Double, _ s: Double, _ v: Double) -> RGB {
        let h = h0 - floor(h0)
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch Int(i) % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

extension Data {
    init(hexString: String) {
        var bytes = [UInt8]()
        var idx = hexString.startIndex
        while idx < hexString.endIndex, let next = hexString.index(idx, offsetBy: 2, limitedBy: hexString.endIndex) {
            if let b = UInt8(hexString[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        self.init(bytes)
    }
}
