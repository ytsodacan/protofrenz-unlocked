import CoreGraphics
import Foundation

/// A 1-bit face part grid, row-major. `w` is 16 (eye), 8 (nose) or 40 (mouth).
struct PartGrid: Equatable {
    var w: Int
    var bits: [Bool]  // w * 8

    init(w: Int, bits: [Bool]? = nil) {
        self.w = w
        self.bits = bits ?? Array(repeating: false, count: w * 8)
    }

    init(hex: String, w: Int) {
        self.init(w: w)
        let bytes = Data(hexString: hex)
        let rowBytes = w / 8
        for y in 0..<8 {
            for x in 0..<w {
                let i = y * rowBytes + x / 8
                if i < bytes.count { bits[y * w + x] = (bytes[i] >> (7 - x % 8)) & 1 == 1 }
            }
        }
    }

    subscript(x: Int, y: Int) -> Bool {
        get { bits[y * w + x] }
        set { bits[y * w + x] = newValue }
    }

    var hex: String {
        var out = [UInt8](repeating: 0, count: w)
        for y in 0..<8 {
            for x in 0..<w where self[x, y] {
                out[y * (w / 8) + x / 8] |= 1 << (7 - x % 8)
            }
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    var isEmpty: Bool { !bits.contains(true) }
}

enum FacePartKind: String, CaseIterable, Identifiable {
    case eye, mouth, nose
    var id: String { rawValue }
    var width: Int { self == .eye ? 16 : self == .nose ? 8 : 40 }
    var label: String { rawValue.capitalized }
    var origin: (x: Double, y: Double) {
        switch self {
        case .eye: return (4, 2)
        case .nose: return (52, 2)
        case .mouth: return (2, 18)
        }
    }
}

struct CustomParts: Equatable {
    var eye = PartGrid(w: 16)
    var nose = PartGrid(w: 8)
    var mouth = PartGrid(w: 40)

    subscript(kind: FacePartKind) -> PartGrid {
        get { kind == .eye ? eye : kind == .nose ? nose : mouth }
        set {
            switch kind {
            case .eye: eye = newValue
            case .nose: nose = newValue
            case .mouth: mouth = newValue
            }
        }
    }
}

struct FaceLibrary {
    struct Item: Identifiable {
        let id: Int
        let name: String
        let grid: PartGrid
    }

    var eyes: [Item] = []
    var noses: [Item] = []
    var mouths: [Item] = []
    var custom: [CustomParts] = Array(repeating: CustomParts(), count: 8)

    init() {}

    init(_ m: FacesMessage) {
        func map(_ parts: [FacePart], _ w: Int) -> [Item] {
            parts.enumerated().map { Item(id: $0.offset, name: $0.element.n, grid: PartGrid(hex: $0.element.b, w: w)) }
        }
        eyes = map(m.eyes, 16)
        noses = map(m.noses, 8)
        mouths = map(m.mouths, 40)
        if let c = m.custom {
            custom = c.map { CustomParts(eye: PartGrid(hex: $0.eye, w: 16), nose: PartGrid(hex: $0.nose, w: 8), mouth: PartGrid(hex: $0.mouth, w: 40)) }
        }
        while custom.count < 8 { custom.append(CustomParts()) }
    }

    func items(_ kind: FacePartKind) -> [Item] {
        kind == .eye ? eyes : kind == .nose ? noses : mouths
    }

    func preset(_ kind: FacePartKind, _ index: Int) -> PartGrid {
        let list = items(kind)
        guard !list.isEmpty else { return PartGrid(w: kind.width) }
        return list[((index % list.count) + list.count) % list.count].grid
    }

    func parts(for e: Expression) -> CustomParts {
        if e.custom, e.i < custom.count { return custom[e.i] }
        return CustomParts(eye: preset(.eye, e.eye), nose: preset(.nose, e.nose), mouth: preset(.mouth, e.mouth))
    }

    static let demo: FaceLibrary = {
        guard let url = Bundle.main.url(forResource: "DemoFaces", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(FacesMessage.self, from: data) else { return FaceLibrary() }
        return FaceLibrary(m)
    }()
}

/// RGBA8 pixel buffer.
struct PixelBuffer {
    let width: Int
    let height: Int
    var data: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        data = Array(repeating: 0, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGB) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let o = (y * width + x) * 4
        data[o] = c.r
        data[o + 1] = c.g
        data[o + 2] = c.b
        data[o + 3] = 255
    }

    func get(_ x: Int, _ y: Int) -> RGB {
        let o = (y * width + x) * 4
        return RGB(r: data[o], g: data[o + 1], b: data[o + 2])
    }

    mutating func clear() { data = Array(repeating: 0, count: width * height * 4) }

    var cgImage: CGImage? {
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Expands a 64-wide face to the full 128x32 visor.
    func visor(mirror: Bool) -> PixelBuffer {
        if width == 128 { return self }
        var out = PixelBuffer(width: 128, height: height)
        for y in 0..<height {
            for x in 0..<128 {
                let sx = x < 64 ? x : (mirror ? 127 - x : x - 64)
                out.set(x, y, get(sx, y))
            }
        }
        return out
    }
}

enum FaceRenderer {
    static func gradient(_ e: Expression, pos: Double, t: Double) -> RGB {
        let scroll = t * e.speed * 0.1
        let cols = e.colors.map { RGB(hex: $0) }
        if e.gradMode == "rainbow" { return RGB.hsv(pos * 0.6 - scroll, 1, 1) }
        if e.gradMode == "solid" || cols.count < 2 { return cols.first ?? RGB(r: 255, g: 255, b: 255) }
        var p = pos - scroll
        p = (p - floor(p)) * Double(cols.count)
        let i = Int(p) % cols.count
        return cols[i].mix(cols[(i + 1) % cols.count], p - floor(p))
    }

    /// Port of firmware faces::render(): parts at 1.5x on a 64x32 panel.
    static func render(_ e: Expression, parts: CustomParts, t: Double, blink: Double = 0, talk: Double = 0) -> PixelBuffer {
        var buf = PixelBuffer(width: 64, height: 32)
        func put(_ k: FacePartKind, _ sx: Double, _ sy: Double, _ c: RGB) {
            for dy in 0..<2 {
                for dx in 0..<2 {
                    let px = Int(floor(k.origin.x + sx * 1.5 + Double(dx) + 0.5))
                    let py = Int(floor(k.origin.y + sy * 1.5 + Double(dy) + 0.5))
                    buf.set(px, py, c)
                }
            }
        }
        func color(_ k: FacePartKind, _ sx: Double, _ sy: Double) -> RGB {
            let px = k.origin.x + sx * 1.5, py = k.origin.y + sy * 1.5
            return gradient(e, pos: e.gradMode == "vertical" ? py / 32 : px / 64, t: t)
        }
        let open = e.blink ? 1 - blink : 1
        for k in FacePartKind.allCases {
            let g = parts[k]
            for y in 0..<8 {
                for x in 0..<g.w where g[x, y] {
                    var sy = Double(y)
                    if k == .eye { sy = open < 0.12 ? 3.5 : 3.5 + (Double(y) - 3.5) * open }
                    let c = color(k, Double(x), sy)
                    put(k, Double(x), sy, c)
                    if k == .mouth, e.talk, talk > 0.02 {
                        let drop = talk * 3.2 * sin(.pi * (Double(x) + 0.5) / 40)
                        var d = 1.0
                        while d <= drop + 0.01 {
                            put(k, Double(x), Double(y) + d, d < drop ? c.mix(.black, 0.55) : c)
                            d += 1
                        }
                    }
                }
            }
        }
        return buf
    }

    /// Thumbnail of a single part, drawn 1:1.
    static func partImage(_ g: PartGrid, color: RGB = RGB(hex: "#00E5FF")) -> CGImage? {
        var buf = PixelBuffer(width: g.w, height: 8)
        for y in 0..<8 { for x in 0..<g.w where g[x, y] { buf.set(x, y, color) } }
        return buf.cgImage
    }
}

/// Natural blink timing, matching the firmware's cadence.
struct BlinkClock {
    private var start: Double = -1
    private var next: Double = 1.5

    mutating func value(at t: Double) -> Double {
        if start < 0, t >= next { start = t }
        guard start >= 0 else { return 0 }
        let b = t - start
        if b < 0.07 { return b / 0.07 }
        if b < 0.11 { return 1 }
        if b < 0.22 { return 1 - (b - 0.11) / 0.11 }
        start = -1
        next = t + Double.random(in: 2.2...6.5)
        return 0
    }
}
