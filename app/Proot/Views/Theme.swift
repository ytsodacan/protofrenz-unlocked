import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x07070D)
    static let bg2 = Color(hex: 0x0E0E18)
    static let card = Color(hex: 0x141422)
    static let card2 = Color(hex: 0x1B1B2C)
    static let line = Color(hex: 0x262640)
    static let dim = Color(hex: 0x8F8DB0)
    static let faint = Color(hex: 0x5A587A)
    static let cyan = Color(hex: 0x00E5FF)
    static let violet = Color(hex: 0x7A5CFF)
    static let pink = Color(hex: 0xFF3FA4)
    static let good = Color(hex: 0x3FF2A0)
    static let bad = Color(hex: 0xFF5468)
    static let accent = LinearGradient(colors: [cyan, violet, pink], startPoint: .leading, endPoint: .trailing)
    static let accent2 = LinearGradient(colors: [cyan, violet], startPoint: .leading, endPoint: .trailing)
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}

/// Rounded group of `Row`s separated by hairlines.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}

struct Row<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct RowLabel: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var style: Kind = .primary
    enum Kind { case primary, pink, plain, danger }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(style == .primary ? Color.black : style == .danger ? Theme.bad : .white)
            .background {
                switch style {
                case .primary: RoundedRectangle(cornerRadius: 14).fill(Theme.accent2)
                case .pink: RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Theme.violet, Theme.pink], startPoint: .leading, endPoint: .trailing))
                case .plain: RoundedRectangle(cornerRadius: 14).fill(Theme.card2)
                case .danger: RoundedRectangle(cornerRadius: 14).fill(Theme.bad.opacity(0.14))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SmallButtonStyle: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(danger ? Theme.bad : .white)
            .background(RoundedRectangle(cornerRadius: 11).fill(danger ? Theme.bad.opacity(0.14) : Theme.card2))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Segmented control matching the rest of the UI.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection == value ? .white : Theme.dim)
                        .background {
                            if selection == value { RoundedRectangle(cornerRadius: 9).fill(Theme.card2).shadow(color: .black.opacity(0.4), radius: 4) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.card2, in: Capsule())
            .overlay(Capsule().stroke(Theme.line))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}

/// Pixel-perfect image of a buffer.
struct PixelImage: View {
    let buffer: PixelBuffer
    var body: some View {
        if let cg = buffer.cgImage {
            Image(decorative: cg, scale: 1).resizable().interpolation(.none)
        } else {
            Color.black
        }
    }
}

/// The big LED visor: pixels, a dark dot grid on top, and a soft glow beneath.
struct LEDVisor: View {
    let buffer: PixelBuffer  // 128x32
    var body: some View {
        GeometryReader { geo in
            let p = geo.size.width / 128
            ZStack {
                PixelImage(buffer: buffer).blur(radius: p * 1.4).opacity(0.75)
                PixelImage(buffer: buffer)
                Canvas { ctx, size in
                    // Gaps between LEDs: darken the cell borders so each pixel reads as a dot.
                    var path = Path()
                    let cols = 128, rows = 32
                    let cw = size.width / CGFloat(cols), ch = size.height / CGFloat(rows)
                    for x in 0...cols { path.addRect(CGRect(x: CGFloat(x) * cw - cw * 0.14, y: 0, width: cw * 0.28, height: size.height)) }
                    for y in 0...rows { path.addRect(CGRect(x: 0, y: CGFloat(y) * ch - ch * 0.14, width: size.width, height: ch * 0.28)) }
                    ctx.fill(path, with: .color(Color(hex: 0x05050A)))
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(4, contentMode: .fit)
        .drawingGroup()
    }
}

extension View {
    func cardBackground() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}
