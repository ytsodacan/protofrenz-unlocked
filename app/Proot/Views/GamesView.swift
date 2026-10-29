import SwiftUI

struct GamesView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        if let s = store.state {
            let active = s.mode == "game" && !s.game.id.isEmpty
            VStack(spacing: 0) {
                SectionHeader(title: "Games")
                if active, let i = GameInfo.all.firstIndex(where: { $0.id == s.game.id }) {
                    controller(GameInfo.all[i], score: s.game.score, best: s.game.best[safe: i] ?? 0)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(GameInfo.all.enumerated()), id: \.element.id) { i, g in
                            Button { store.startGame(g.id) } label: { card(g, best: s.game.best[safe: i] ?? 0) }
                                .buttonStyle(PressStyle())
                        }
                    }
                    Text("Games play across the whole visor. Steer them from here, or press the visor's button for A.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                        .padding(.top, 12).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func card(_ g: GameInfo, best: Int) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: g.symbol).font(.system(size: 28, weight: .semibold))
            Spacer(minLength: 18)
            Text(g.name).font(.system(size: 17, weight: .bold))
            Text(g.blurb).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            if best > 0 { Text("Best \(best)").font(.caption.bold()).padding(.top, 2) }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(LinearGradient(colors: g.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func controller(_ g: GameInfo, score: Int, best: Int) -> some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name).font(.headline)
                    Text("Score \(score) · best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                }
                Spacer()
                Button("Exit") { store.stopGame() }.buttonStyle(SmallButtonStyle(danger: true))
            }
            .padding(14)
            .cardBackground()

            HStack(alignment: .center) {
                DPad { k, d in store.key(k, down: d) }
                Spacer(minLength: 12)
                ZStack(alignment: .topTrailing) {
                    Color.clear.frame(width: 150, height: 150)
                    PadButton(key: .a, label: "A", size: 76, fill: AnyShapeStyle(LinearGradient(colors: [Theme.pink, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing))) { k, d in store.key(k, down: d) }
                    PadButton(key: .b, label: "B", size: 68, fill: AnyShapeStyle(Theme.card2)) { k, d in store.key(k, down: d) }
                        .offset(x: -82, y: 78)
                }
            }
            Text("Hold the visor's button to quit a game.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct DPad: View {
    let onKey: (GameKey, Bool) -> Void
    var body: some View {
        let u: CGFloat = 60
        ZStack {
            Color.clear.frame(width: u * 3, height: u * 3)
            PadButton(key: .up, systemImage: "chevron.up", size: u, onKey: onKey).offset(y: -u)
            PadButton(key: .down, systemImage: "chevron.down", size: u, onKey: onKey).offset(y: u)
            PadButton(key: .left, systemImage: "chevron.left", size: u, onKey: onKey).offset(x: -u)
            PadButton(key: .right, systemImage: "chevron.right", size: u, onKey: onKey).offset(x: u)
        }
    }
}

/// Press-and-hold button that reports key down/up, for game control.
struct PadButton: View {
    let key: GameKey
    var label: String? = nil
    var systemImage: String? = nil
    var size: CGFloat
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.card2)
    let onKey: (GameKey, Bool) -> Void
    @State private var down = false

    init(key: GameKey, label: String? = nil, systemImage: String? = nil, size: CGFloat, fill: AnyShapeStyle = AnyShapeStyle(Theme.card2),
         onKey: @escaping (GameKey, Bool) -> Void) {
        self.key = key
        self.label = label
        self.systemImage = systemImage
        self.size = size
        self.fill = fill
        self.onKey = onKey
    }

    var body: some View {
        let round = label != nil
        ZStack {
            if round { Circle().fill(fill) } else { RoundedRectangle(cornerRadius: 16).fill(fill) }
            if let label { Text(label).font(.system(size: 22, weight: .heavy)) }
            if let systemImage { Image(systemName: systemImage).font(.system(size: 24, weight: .bold)) }
        }
        .foregroundStyle(down ? .white : Theme.dim)
        .overlay { if !round { RoundedRectangle(cornerRadius: 16).stroke(Theme.line) } }
        .frame(width: size, height: size)
        .scaleEffect(down ? 0.92 : 1)
        .brightness(down ? 0.15 : 0)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !down else { return }
                down = true
                onKey(key, true)
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            .onEnded { _ in
                down = false
                onKey(key, false)
            })
        .animation(.spring(duration: 0.15), value: down)
    }
}
