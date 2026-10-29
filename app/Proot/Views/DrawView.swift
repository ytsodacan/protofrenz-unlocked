import SwiftUI

/// Drawing canvas state, kept across tab switches. `lastFrame` feeds the header preview.
@Observable
final class DrawModel {
    static let shared = DrawModel()
    var pixels = [RGB](repeating: .black, count: 128 * 32)  // always 128 wide; 64-wide mode uses the left half
    var span = false
    var version = 0
    @ObservationIgnored var lastFrame: PixelBuffer?

    var width: Int { span ? 128 : 64 }

    func get(_ x: Int, _ y: Int) -> RGB { pixels[y * 128 + x] }

    func set(_ x: Int, _ y: Int, _ c: RGB) {
        guard x >= 0, y >= 0, x < width, y < 32 else { return }
        pixels[y * 128 + x] = c
    }

    func fill(_ x: Int, _ y: Int, _ c: RGB) {
        let target = get(x, y)
        guard target != c else { return }
        var stack = [(x, y)]
        while let (a, b) = stack.popLast() {
            guard a >= 0, b >= 0, a < width, b < 32, get(a, b) == target else { continue }
            set(a, b, c)
            stack += [(a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)]
        }
    }

    func frame() -> [RGB] {
        (0..<32).flatMap { y in (0..<width).map { x in get(x, y) } }
    }

    func visorPreview(mirror: Bool) -> PixelBuffer {
        var b = PixelBuffer(width: 128, height: 32)
        for y in 0..<32 {
            for x in 0..<128 {
                let sx = span ? x : (x < 64 ? x : (mirror ? 127 - x : x - 64))
                b.set(x, y, get(sx, y))
            }
        }
        return b
    }
}

struct DrawView: View {
    @Environment(DeviceStore.self) private var store
    @State private var model = DrawModel.shared
    @State private var tool = Tool.pen
    @State private var color = RGB(hex: "#00E5FF")
    @State private var last: (Int, Int)?
    @State private var sendTask: Task<Void, Never>?
    @State private var lastSend = Date.distantPast

    enum Tool: String, CaseIterable { case pen, erase, fill }

    private let palette = ["#00E5FF", "#7A5CFF", "#FF3FA4", "#FF1E1E", "#FF8A00", "#FFD23F", "#3FF2A0", "#FFFFFF", "#3A3A55"]

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Live drawing")
            Card {
                canvas
                HStack(spacing: 8) {
                    toolButton(.pen, "pencil.tip")
                    toolButton(.erase, "eraser")
                    toolButton(.fill, "drop.fill")
                    Spacer()
                    Button("Clear") {
                        model.pixels = .init(repeating: .black, count: 128 * 32)
                        model.version += 1
                        push()
                    }
                    .buttonStyle(SmallButtonStyle())
                }
                .padding(.top, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(palette, id: \.self) { h in
                            let c = RGB(hex: h)
                            Circle().fill(c.color).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: color == c ? 2 : 0))
                                .shadow(color: color == c ? .white.opacity(0.5) : .clear, radius: 5)
                                .onTapGesture { color = c; if tool == .erase { tool = .pen } }
                        }
                        ColorPicker("", selection: Binding(get: { color.color }, set: { color = RGB($0) }), supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 10)
                Toggle(isOn: Binding(get: { model.span }, set: { model.span = $0; model.version += 1; push() })) {
                    RowLabel(title: "Span both panels", subtitle: "Off: draw one side, mirrored to the other")
                }
                .padding(.top, 8)
            }
            HStack(spacing: 10) {
                Button("Show on visor") { push(force: true) }.buttonStyle(GlowButtonStyle(style: .primary))
                Button("Back to face") { store.setMode("face") }.buttonStyle(GlowButtonStyle(style: .plain))
            }
            .padding(.top, 12)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(model.width)
            Canvas { ctx, _ in
                _ = model.version
                for y in 0..<32 {
                    for x in 0..<model.width {
                        let c = model.get(x, y)
                        ctx.fill(Path(CGRect(x: CGFloat(x) * cell + 0.5, y: CGFloat(y) * cell + 0.5, width: cell - 1, height: cell - 1)),
                                 with: .color(c.isDark ? Color(hex: 0x121222) : c.color))
                    }
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in paint(Int(v.location.x / cell), Int(v.location.y / cell)) }
                .onEnded { _ in last = nil; push(force: true) })
        }
        .aspectRatio(CGFloat(model.width) / 32, contentMode: .fit)
        .background(Color(hex: 0x05050A), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func toolButton(_ t: Tool, _ icon: String) -> some View {
        Button { tool = t } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(tool == t ? Theme.cyan : Theme.dim)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tool == t ? Theme.cyan : Theme.line))
        }
        .buttonStyle(.plain)
    }

    private func paint(_ x: Int, _ y: Int) {
        switch tool {
        case .fill:
            if last == nil, x >= 0, y >= 0, x < model.width, y < 32 { model.fill(x, y, color) }
            last = (x, y)
        case .pen, .erase:
            let c = tool == .erase ? RGB.black : color
            let (x0, y0) = last ?? (x, y)
            let n = max(abs(x - x0), abs(y - y0), 1)
            for i in 0...n {
                model.set(x0 + (x - x0) * i / n, y0 + (y - y0) * i / n, c)
            }
            last = (x, y)
        }
        model.version += 1
        push()
    }

    /// Streams the canvas, throttled to ~10 fps over BLE and ~20 fps over Wi-Fi.
    private func push(force: Bool = false) {
        let interval = store.isBLE ? 0.1 : 0.05
        let send = {
            lastSend = Date()
            model.lastFrame = model.visorPreview(mirror: true)
            store.sendFrame(model.frame(), width: model.width, mirror: true)
        }
        if force || Date().timeIntervalSince(lastSend) >= interval {
            sendTask?.cancel()
            send()
        } else if sendTask == nil {
            sendTask = Task {
                try? await Task.sleep(for: .seconds(interval))
                sendTask = nil
                if !Task.isCancelled { send() }
            }
        }
    }
}
