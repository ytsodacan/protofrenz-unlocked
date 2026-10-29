import SwiftUI

@main
struct ProotApp: App {
    @State private var store = DeviceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
                .onAppear { store.autoConnect() }
        }
    }
}

struct RootView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            if store.state != nil {
                MainTabs()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ConnectView(scanner: store.scanner)
                    .transition(.opacity)
            }
            if let t = store.toast {
                Toast(text: t)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: store.state == nil)
        .animation(.spring(duration: 0.3), value: store.toast)
    }
}

enum Tab: String, CaseIterable {
    case faces, draw, media, games, settings
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .faces: return "face.smiling"
        case .draw: return "pencil.tip"
        case .media: return "play.rectangle"
        case .games: return "gamecontroller"
        case .settings: return "gearshape"
        }
    }
}

struct MainTabs: View {
    @Environment(DeviceStore.self) private var store
    @State private var tab: Tab = .faces

    var body: some View {
        VStack(spacing: 0) {
            VisorHeader()
            ScrollView {
                Group {
                    switch tab {
                    case .faces: FacesView()
                    case .draw: DrawView()
                    case .media: MediaView()
                    case .games: GamesView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) { TabBar(tab: $tab) }
        .ignoresSafeArea(.keyboard)
    }
}

struct TabBar: View {
    @Binding var tab: Tab
    var body: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    tab = t
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(tab == t ? AnyShapeStyle(Theme.accent2) : AnyShapeStyle(Theme.faint))
                            .shadow(color: tab == t ? Theme.cyan.opacity(0.5) : .clear, radius: 6)
                        Text(t.title).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tab == t ? .white : Theme.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .background(Theme.bg.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Sticky header: name, link status and a live preview of what the visor shows.
struct VisorHeader: View {
    @Environment(DeviceStore.self) private var store
    @State private var clock = PreviewClock()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("proot")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                Text(store.deviceName).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer()
                StatusPill()
            }
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                LEDVisor(buffer: frame(at: ctx.date.timeIntervalSinceReferenceDate))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x15152A), Color(hex: 0x06060B)], center: .top, startRadius: 0, endRadius: 400))
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
            .overlay(alignment: .bottomLeading) {
                Text(modeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.dim)
                    .padding(.leading, 18).padding(.bottom, 6)
            }
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            if store.isDemo {
                Text("Demo mode — not connected to a visor.")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(LinearGradient(colors: [Theme.violet.opacity(0.2), Theme.pink.opacity(0.2)], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: 720)
    }

    private var modeLabel: String {
        guard let s = store.state else { return "" }
        switch s.mode {
        case "face": return s.expr[safe: s.boop ? s.cfg.boopExpr : s.active]?.name ?? ""
        case "anim": return "▶ " + s.anim
        case "game": return GameInfo.all.first { $0.id == s.game.id }?.name ?? "game"
        case "draw": return "live drawing"
        case "test": return "test pattern"
        default: return s.mode
        }
    }

    private func frame(at t: Double) -> PixelBuffer {
        guard let s = store.state else { return PixelBuffer(width: 128, height: 32) }
        switch s.mode {
        case "face":
            let i = s.boop ? s.cfg.boopExpr : s.active
            guard let e = s.expr[safe: i] else { break }
            let b = clock.blink.value(at: t)
            let face = FaceRenderer.render(e, parts: store.faces.parts(for: e), t: t, blink: b)
            return face.visor(mirror: s.cfg.mirror)
        case "draw":
            if let f = DrawModel.shared.lastFrame { return f }
        case "text":
            return TextPreview.render(s.text, t: t, clock: clock)
        default:
            break
        }
        return Placeholder.render(label: modeLabel, t: t)
    }
}

struct StatusPill: View {
    @Environment(DeviceStore.self) private var store
    var body: some View {
        let (color, text): (Color, String) = {
            if store.isDemo { return (Theme.violet, "Demo") }
            switch store.link {
            case .connected: return (Theme.good, store.isBLE ? "Bluetooth" : "Wi-Fi")
            case .connecting: return (.orange, "Connecting")
            default: return (Theme.bad, "Offline")
            }
        }()
        Menu {
            Button("Disconnect", systemImage: "xmark.circle") { store.disconnect(forget: true) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 4)
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.card, in: Capsule())
        }
    }
}

enum Placeholder {
    static func render(label: String, t: Double) -> PixelBuffer {
        var b = PixelBuffer(width: 128, height: 32)
        for x in 0..<128 {
            let y = Int(16 + 6 * sin(Double(x) / 9 + t * 3))
            b.set(x, y, RGB.hsv(Double(x) / 128 + t * 0.2, 0.9, 0.9))
        }
        return b
    }
}

/// Mutable animation state for previews; a class so ticking it doesn't re-render views.
final class PreviewClock {
    var blink = BlinkClock()
    var textX = 128.0
    var textKey = ""
    var textMask: (w: Int, h: Int, alpha: [UInt8])?
}

enum TextPreview {
    @MainActor
    static func render(_ tx: TextState, t: Double, clock: PreviewClock) -> PixelBuffer {
        var buf = PixelBuffer(width: 128, height: 32)
        let key = "\(tx.s)|\(tx.size)"
        if clock.textKey != key {
            clock.textKey = key
            clock.textMask = mask(tx.s, size: max(1, tx.size))
        }
        guard let m = clock.textMask else { return buf }
        let oy = (32 - m.h) / 2
        for yy in 0..<m.h {
            for xx in 0..<m.w where m.alpha[yy * m.w + xx] > 100 {
                let X = Int(clock.textX) + xx
                guard X >= 0, X < 128 else { continue }
                let c = tx.color == "rainbow" ? RGB.hsv(Double(xx) / 60 - t * 0.25, 1, 1) : RGB(hex: tx.color)
                buf.set(X, oy + yy, c)
            }
        }
        clock.textX -= tx.speed / 30
        if clock.textX < Double(-m.w) { clock.textX = 128 }
        return buf
    }

    @MainActor
    private static func mask(_ s: String, size: Int) -> (w: Int, h: Int, alpha: [UInt8])? {
        let renderer = ImageRenderer(content:
            Text(s).font(.system(size: CGFloat(8 * size), weight: .bold, design: .monospaced)).foregroundStyle(.white).fixedSize())
        renderer.scale = 1
        guard let img = renderer.cgImage else { return nil }
        let w = img.width, h = min(img.height, 32)
        guard let ctx = CGContext(data: nil, width: w, height: img.height, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: img.height))),
              let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let alpha = (0..<(w * h)).map { p[$0 * 4 + 3] }
        return (w, h, alpha)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
