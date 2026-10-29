import SwiftUI

struct FacesView: View {
    @Environment(DeviceStore.self) private var store
    @State private var editing: Int?

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        if let s = store.state {
            VStack(spacing: 0) {
                SectionHeader(title: "Expressions")
                TimelineView(.animation(minimumInterval: 1 / 12)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(s.expr) { e in
                            ExpressionCard(e: e, active: s.mode == "face" && s.active == e.i, t: t) {
                                store.activate(e.i)
                            } onEdit: {
                                editing = e.i
                            }
                        }
                    }
                }
                Text("Tap to switch. The pencil edits eyes, mouth, nose, colors and behavior. The visor's button cycles expressions marked “In button cycle”.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                    .padding(.top, 12).padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(item: $editing) { i in
                ExpressionEditor(index: i)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.bg2)
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct ExpressionCard: View {
    @Environment(DeviceStore.self) private var store
    let e: Expression
    let active: Bool
    let t: Double
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelImage(buffer: FaceRenderer.render(e, parts: store.faces.parts(for: e), t: t))
                .aspectRatio(2, contentMode: .fit)
                .background(Color(hex: 0x05050A))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if !e.anim.isEmpty || e.custom {
                        Text(!e.anim.isEmpty ? "GIF" : "CUSTOM")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(Theme.pink)
                            .padding(5)
                    }
                }
            HStack {
                Text(e.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 30, height: 30)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(active ? AnyShapeStyle(Theme.accent2) : AnyShapeStyle(Theme.line), lineWidth: active ? 2 : 1)
        }
        .shadow(color: active ? Theme.cyan.opacity(0.3) : .clear, radius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onTap)
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

struct ExpressionEditor: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let index: Int
    @State private var part: FacePartKind = .eye
    @State private var removing = false

    private var e: Expression? { store.state?.expr[safe: index] }

    var body: some View {
        if let e {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        TextField("Name", text: Binding(get: { e.name }, set: { store.updateExpression(index, ["name": String($0.prefix(15))]) }))
                            .font(.system(size: 22, weight: .bold))
                        Button("Done") { dismiss() }.buttonStyle(SmallButtonStyle())
                    }
                    .padding(.top, 22)

                    TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                        LEDVisor(buffer: FaceRenderer.render(e, parts: store.faces.parts(for: e), t: ctx.date.timeIntervalSinceReferenceDate)
                            .visor(mirror: store.state?.cfg.mirror ?? true))
                    }
                    .padding(10)
                    .background(Color(hex: 0x05050A), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 12)

                    Segmented(options: [(false, "Presets"), (true, "Custom drawing")],
                              selection: Binding(get: { e.custom }, set: { setCustom($0) }))
                        .padding(.top, 14)

                    if e.custom { customEditor(e) } else { presetPickers(e) }
                    colors(e)
                    behavior(e)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .onAppear {
                store.activate(index)
                store.send(["cmd": "files"])
            }
        }
    }

    private func setCustom(_ on: Bool) {
        guard let e else { return }
        if on, store.faces.custom[safe: index]?.eye.isEmpty ?? true, store.faces.custom[safe: index]?.mouth.isEmpty ?? true {
            var p = e
            p.custom = false
            store.setCustom(index, store.faces.parts(for: p))  // start from the current presets
        }
        store.updateExpression(index, ["custom": on])
    }

    @ViewBuilder private func presetPickers(_ e: Expression) -> some View {
        ForEach(FacePartKind.allCases) { kind in
            SectionHeader(title: kind.label)
            PartStrip(kind: kind, selected: kind == .eye ? e.eye : kind == .nose ? e.nose : e.mouth) { i in
                store.updateExpression(index, [kind.rawValue: i])
            }
        }
    }

    @ViewBuilder private func customEditor(_ e: Expression) -> some View {
        Segmented(options: FacePartKind.allCases.map { ($0, $0.label) }, selection: $part)
            .padding(.top, 14)
        if let parts = store.faces.custom[safe: index] {
            PixelGridEditor(grid: parts[part], color: { x in FaceRenderer.gradient(e, pos: Double(x) / Double(parts[part].w), t: 0) }) { g in
                var p = parts
                p[part] = g
                store.setCustom(index, p)
            }
            .padding(.top, 12)
            HStack(spacing: 8) {
                Button("From preset") {
                    var p = parts
                    p[part] = store.faces.preset(part, part == .eye ? e.eye : part == .nose ? e.nose : e.mouth)
                    store.setCustom(index, p)
                }
                Button("Invert") {
                    var p = parts
                    p[part].bits = p[part].bits.map { !$0 }
                    store.setCustom(index, p)
                }
                Button("Mirror") {
                    var p = parts
                    var g = p[part]
                    for y in 0..<8 { for x in 0..<g.w { g[x, y] = parts[part][g.w - 1 - x, y] } }
                    p[part] = g
                    store.setCustom(index, p)
                }
                Spacer()
                Button("Clear") {
                    var p = parts
                    p[part] = PartGrid(w: part.width)
                    store.setCustom(index, p)
                }
                .buttonStyle(SmallButtonStyle(danger: true))
            }
            .buttonStyle(SmallButtonStyle())
            .padding(.top, 10)
            Text("Tap or drag to paint. Start on a lit pixel to erase.").font(.footnote).foregroundStyle(Theme.dim).padding(.top, 8)
        }
    }

    @ViewBuilder private func colors(_ e: Expression) -> some View {
        SectionHeader(title: "Colors")
        Card {
            HStack(spacing: 8) {
                ForEach(Array(e.colors.enumerated()), id: \.offset) { i, c in
                    ColorPicker("", selection: Binding(get: { RGB(hex: c).color }, set: { v in
                        var cs = e.colors
                        cs[i] = RGB(v).hex
                        store.updateExpression(index, ["colors": cs])
                    }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 42, height: 42)
                    .background(RGB(hex: c).color, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if removing && e.colors.count > 1 {
                            Button {
                                var cs = e.colors
                                cs.remove(at: i)
                                store.updateExpression(index, ["colors": cs])
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black)
                            }
                            .offset(x: 6, y: -6)
                        }
                    }
                }
                if e.colors.count < 6 {
                    Button {
                        store.updateExpression(index, ["colors": e.colors + [RGB.hsv(.random(in: 0...1), 0.8, 1).hex]])
                    } label: {
                        Image(systemName: "plus").frame(width: 42, height: 42)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [4])))
                    }
                    .foregroundStyle(Theme.dim)
                }
                Spacer()
                if e.colors.count > 1 {
                    Button(removing ? "Done" : "Remove") { removing.toggle() }.buttonStyle(SmallButtonStyle())
                }
            }
            Segmented(options: GradMode.allCases.map { ($0.rawValue, $0.label) },
                      selection: Binding(get: { e.gradMode }, set: { store.updateExpression(index, ["gradMode": $0]) }))
                .padding(.top, 12)
            HStack {
                Text("Speed")
                Slider(value: Binding(get: { e.speed }, set: { store.updateExpression(index, ["speed": ($0 * 10).rounded() / 10]) }), in: 0...10)
            }
            .padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, p in
                        Button {
                            store.updateExpression(index, ["colors": p])
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(colors: p.map { RGB(hex: $0).color }, startPoint: .leading, endPoint: .trailing))
                                .frame(width: 42, height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 2))
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    static let presets: [[String]] = [
        ["#00E5FF", "#7A5CFF", "#FF3FA4"], ["#FF1E1E", "#FF6A00", "#FFD23F"], ["#3FF2A0", "#00E5FF"], ["#FF4FD8", "#FF2A6D"],
        ["#FFFFFF"], ["#E60000", "#FFFC03", "#04E900", "#0000DC", "#5800A9", "#F50000"], ["#B04FFF", "#00E5FF", "#3FF2A0"],
    ]

    @ViewBuilder private func behavior(_ e: Expression) -> some View {
        SectionHeader(title: "Behavior")
        RowGroup {
            Row { Toggle("Blink", isOn: Binding(get: { e.blink }, set: { store.updateExpression(index, ["blink": $0]) })) }
            Row { Toggle("Talk with mic", isOn: Binding(get: { e.talk }, set: { store.updateExpression(index, ["talk": $0]) })) }
            Row { Toggle("In button cycle", isOn: Binding(get: { e.cycle }, set: { store.updateExpression(index, ["cycle": $0]) })) }
            Row {
                RowLabel(title: "Play animation instead", subtitle: "A file from Media")
                Picker("", selection: Binding(get: { e.anim }, set: { store.updateExpression(index, ["anim": $0]) })) {
                    Text("None").tag("")
                    ForEach(store.files) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
            }
        }
    }
}

struct PartStrip: View {
    @Environment(DeviceStore.self) private var store
    let kind: FacePartKind
    let selected: Int
    let onPick: (Int) -> Void

    var body: some View {
        let items = store.faces.items(kind)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(items) { item in
                        let isSel = items.isEmpty ? false : item.id == ((selected % items.count) + items.count) % items.count
                        Button { onPick(item.id) } label: {
                            VStack(spacing: 4) {
                                PixelImage(buffer: thumb(item.grid))
                                    .frame(width: CGFloat(item.grid.w) * 4.2, height: 34)
                                Text(item.name).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                            }
                            .padding(6)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSel ? Theme.cyan : Theme.line, lineWidth: isSel ? 2 : 1))
                            .shadow(color: isSel ? Theme.cyan.opacity(0.35) : .clear, radius: 8)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .frame(height: 70)
    }

    private func thumb(_ g: PartGrid) -> PixelBuffer {
        var b = PixelBuffer(width: g.w, height: 8)
        for y in 0..<8 { for x in 0..<g.w where g[x, y] { b.set(x, y, RGB(hex: "#00E5FF")) } }
        return b
    }
}

/// Paintable bitmap editor for a face part.
struct PixelGridEditor: View {
    let grid: PartGrid
    let color: (Int) -> RGB
    let onChange: (PartGrid) -> Void
    @State private var paintValue: Bool?

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(grid.w)
            Canvas { ctx, _ in
                for y in 0..<8 {
                    for x in 0..<grid.w {
                        let r = CGRect(x: CGFloat(x) * cell + 1, y: CGFloat(y) * cell + 1, width: cell - 2, height: cell - 2)
                        ctx.fill(Path(roundedRect: r, cornerRadius: min(4, cell / 4)),
                                 with: .color(grid[x, y] ? color(x).color : Color(hex: 0x16162A)))
                    }
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let x = Int(v.location.x / cell), y = Int(v.location.y / cell)
                guard x >= 0, y >= 0, x < grid.w, y < 8 else { return }
                if paintValue == nil { paintValue = !grid[x, y] }
                guard grid[x, y] != paintValue else { return }
                var g = grid
                g[x, y] = paintValue!
                onChange(g)
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            }.onEnded { _ in paintValue = nil })
        }
        .aspectRatio(CGFloat(grid.w) / 8, contentMode: .fit)
        .padding(6)
        .background(Color(hex: 0x05050A), in: RoundedRectangle(cornerRadius: 12))
    }
}
