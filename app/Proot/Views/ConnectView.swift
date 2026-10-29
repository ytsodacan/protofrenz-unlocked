import SwiftUI

struct ConnectView: View {
    @Environment(DeviceStore.self) private var store
    @ObservedObject var scanner: BLEScanner
    @State private var host = UserDefaults.standard.string(forKey: "wifiHost") ?? "192.168.4.1"
    @State private var showWifi = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                statusLine
                VStack(spacing: 10) {
                    if scanner.visors.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Looking for visors…").font(.headline)
                                Text("Power on your controller and keep it close.").font(.footnote).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .cardBackground()
                    }
                    ForEach(scanner.visors) { v in
                        Button { store.connectBLE(v.id) } label: { visorRow(v) }
                            .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation { showWifi.toggle() }
                    } label: {
                        Label("Connect over Wi-Fi instead", systemImage: "wifi")
                    }
                    .buttonStyle(GlowButtonStyle(style: .plain))
                    if showWifi {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Join the visor's hotspot in Settings → Wi-Fi first, then connect here. Wi-Fi is faster for big animations and is needed for firmware updates.")
                                .font(.footnote).foregroundStyle(Theme.dim)
                            HStack {
                                TextField("192.168.4.1", text: $host)
                                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(10).background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
                                Button("Connect") {
                                    UserDefaults.standard.set(host, forKey: "wifiHost")
                                    store.connectWiFi(host: host)
                                }
                                .buttonStyle(SmallButtonStyle())
                            }
                        }
                        .padding(14)
                        .cardBackground()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Button("Try the demo") { store.startDemo() }
                        .buttonStyle(GlowButtonStyle(style: .plain))
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear { scanner.startScan() }
        .onDisappear { scanner.stopScan() }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                LEDVisor(buffer: heroFrame(ctx.date.timeIntervalSinceReferenceDate))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x05050A)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.line))
            .shadow(color: Theme.violet.opacity(0.25), radius: 30, y: 10)
            Text("proot").font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.accent)
            Text("Faces, animations and games for your ProtoFrenz visor.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    @ViewBuilder private var statusLine: some View {
        if scanner.unauthorized {
            Text("Bluetooth access is off for Proot. Turn it on in Settings → Privacy → Bluetooth.")
                .font(.footnote).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
        } else if !scanner.poweredOn {
            Text("Bluetooth is off.").font(.footnote).foregroundStyle(Theme.bad)
        } else if case .failed(let why) = store.link {
            Text(why).font(.footnote).foregroundStyle(Theme.bad)
        } else if store.link == .connecting {
            HStack { ProgressView().tint(Theme.cyan); Text("Connecting…").foregroundStyle(Theme.dim) }
        }
    }

    private func visorRow(_ v: DiscoveredVisor) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.inset.filled")
                .font(.title2)
                .foregroundStyle(Theme.accent2)
                .frame(width: 44, height: 44)
                .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.headline)
                Text(signal(v.rssi)).font(.footnote).foregroundStyle(Theme.dim)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
        }
        .padding(14)
        .cardBackground()
    }

    private func signal(_ rssi: Int) -> String {
        rssi > -60 ? "Right here" : rssi > -75 ? "Nearby" : "Far away"
    }

    private func heroFrame(_ t: Double) -> PixelBuffer {
        let lib = store.faces.eyes.isEmpty ? FaceLibrary.demo : store.faces
        var e = DemoData.state.expr[0]
        e.speed = 3
        return FaceRenderer.render(e, parts: lib.parts(for: e), t: t, blink: heroBlink.value(at: t)).visor(mirror: true)
    }

    private let heroBlink = HeroBlink()
}

private final class HeroBlink {
    private var clock = BlinkClock()
    func value(at t: Double) -> Double { clock.value(at: t) }
}
