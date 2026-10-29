import CoreGraphics
import Foundation
import ImageIO

enum AnimLayout: String, CaseIterable, Identifiable {
    case mirror, copy, span
    var id: String { rawValue }
    var label: String { self == .mirror ? "Mirror" : self == .copy ? "Copy" : "Span" }
    var width: Int { self == .span ? 128 : 64 }
}

enum AnimFit: String, CaseIterable, Identifiable {
    case fill, fit, stretch
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct SourceFrame {
    let image: CGImage
    let delay: Double  // seconds
}

struct ConvertedAnim {
    var width: Int
    var frames: [(pixels: PixelBuffer, delayMs: Int)]
    var layout: AnimLayout

    var byteCount: Int { 12 + frames.count * (2 + width * 32 * 2) }

    /// .pfa: "PFA1", u16 w, u16 h, u16 frames, u8 flags, u8 0, then per frame u16 delay + RGB565 LE.
    func encoded() -> Data {
        var d = Data(capacity: byteCount)
        d.append(contentsOf: Array("PFA1".utf8))
        func u16(_ v: Int) { d.append(UInt8(v & 255)); d.append(UInt8((v >> 8) & 255)) }
        u16(width)
        u16(32)
        u16(frames.count)
        d.append(layout == .mirror ? 1 : 0)
        d.append(0)
        for f in frames {
            u16(f.delayMs)
            for y in 0..<32 {
                for x in 0..<width { u16(Int(f.pixels.get(x, y).rgb565)) }
            }
        }
        return d
    }

    /// Full 128x32 preview of a frame as it will appear on the visor.
    func preview(_ i: Int) -> PixelBuffer {
        let f = frames[i % frames.count].pixels
        return width == 128 ? f : f.visor(mirror: layout == .mirror)
    }
}

enum AnimConverter {
    static func load(_ data: Data) -> [SourceFrame] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        return (0..<n).compactMap { i in
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { return nil }
            var delay = n > 1 ? 0.1 : 1.0
            if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] {
                for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary] {
                    if let dict = props[key] as? [CFString: Any] {
                        let unclamped = dict[kCGImagePropertyGIFUnclampedDelayTime] ?? dict[kCGImagePropertyAPNGUnclampedDelayTime]
                            ?? dict[kCGImagePropertyWebPUnclampedDelayTime]
                        let clamped = dict[kCGImagePropertyGIFDelayTime] ?? dict[kCGImagePropertyAPNGDelayTime] ?? dict[kCGImagePropertyWebPDelayTime]
                        if let v = (unclamped ?? clamped) as? Double, v > 0 { delay = v }
                    }
                }
            }
            return SourceFrame(image: img, delay: max(0.02, delay))
        }
    }

    static func convert(_ src: [SourceFrame], layout: AnimLayout, fit: AnimFit, sharp: Bool, speed: Double, maxBytes: Int) -> ConvertedAnim {
        let w = layout.width
        let frameBytes = 2 + w * 32 * 2
        let budget = max(1, min(240, (maxBytes - 12) / frameBytes))
        let step = max(1, Int(ceil(Double(src.count) / Double(budget))))
        var out = ConvertedAnim(width: w, frames: [], layout: layout)
        guard let ctx = CGContext(data: nil, width: w, height: 32, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return out }
        ctx.interpolationQuality = sharp ? .none : .high
        var i = 0
        while i < src.count {
            let img = src[i].image
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: 32))
            let iw = Double(img.width), ih = Double(img.height)
            var rect = CGRect(x: 0, y: 0, width: w, height: 32)
            if fit != .stretch {
                let s = fit == .fill ? max(Double(w) / iw, 32 / ih) : min(Double(w) / iw, 32 / ih)
                rect = CGRect(x: (Double(w) - iw * s) / 2, y: (32 - ih * s) / 2, width: iw * s, height: ih * s)
            }
            ctx.draw(img, in: rect)
            var buf = PixelBuffer(width: w, height: 32)
            if let p = ctx.data?.assumingMemoryBound(to: UInt8.self) {
                buf.data = Array(UnsafeBufferPointer(start: p, count: w * 32 * 4))
            }
            let delay = src[i..<min(src.count, i + step)].reduce(0) { $0 + $1.delay }
            out.frames.append((buf, Int(max(16, min(60000, delay * 1000 / speed)))))
            i += step
        }
        return out
    }
}
