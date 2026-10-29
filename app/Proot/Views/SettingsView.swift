import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DeviceStore.self) private var store
    @State private var apPass = ""
    @State private var staPass = ""
    @State private var otaPicking = false
    @State private var otaProgress: Double?
    @State private var confirm: Confirm?

    enum Confirm: String, Identifiable {
        case reboot, factory, stats, wifi
        var id: String { rawValue }
    }

    var body: some View {
        if let s = store.state {
            let c = s.cfg
            VStack(spacing: 0) {
                SectionHeader(title: "Display")
                RowGroup {
                    sliderRow("Brightness", value: c.brightness, range: 4...255, key: "brightness")
                    toggleRow("Mirror second panel", "Off: both panels show the same image", c.mirror, "mirror")
                    toggleRow("Swap panels", nil, c.swapPanels, "swapPanels")
                    toggleRow("Upside down", nil, c.rotate, "rotate")
                    Row {
                        RowLabel(title: "Panel driver", subtitle: "Restart to apply")
                        Picker("", selection: binding(c.driver, "driver")) {
                            Text("Standard").tag(0)
                            Text("FM6126A").tag(1)
                            Text("ICN2038S").tag(2)
                            Text("MBI5124").tag(3)
                        }
                        .labelsHidden()
                    }
                    Row {
                        RowLabel(title: "Test pattern", subtitle: "Checks panel order and colors")
                        Button(s.mode == "test" ? "Hide" : "Show") { store.setMode(s.mode == "test" ? "face" : "test") }
                            .buttonStyle(SmallButtonStyle())
                    }
                }

                SectionHeader(title: "Boop")
                RowGroup {
                    toggleRow("React to boops", nil, c.boopOn, "boopOn")
                    Row {
                        Text("Reaction").frame(maxWidth: .infinity, alignment: .leading)
                        Picker("", selection: binding(c.boopExpr, "boopExpr")) {
                            ForEach(s.expr) { Text($0.name).tag($0.i) }
                        }
                        .labelsHidden()
                    }
                    Row {
                        Text("Duration")
                        Slider(value: Binding(get: { Double(c.boopMs) }, set: { store.setConfig("boopMs", Int($0 / 100) * 100) }), in: 300...10000)
                        Text(String(format: "%.1fs", Double(c.boopMs) / 1000)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 40)
                    }
                }

                SectionHeader(title: "Microphone")
                RowGroup {
                    sliderRow("Sensitivity", value: c.micSens, range: 1...10, key: "micSens")
                    Row {
                        Text("Level")
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.bg2)
                                Capsule().fill(LinearGradient(colors: [Theme.good, Theme.cyan, Theme.pink], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * store.micLevel)
                                    .animation(.linear(duration: 0.1), value: store.micLevel)
                            }
                        }
                        .frame(height: 10)
                    }
                }

                SectionHeader(title: "Fan & cheeks")
                RowGroup {
                    Row {
                        Text("Fan")
                        Slider(value: Binding(get: { Double(c.fan) }, set: { store.setConfig("fan", Int($0)) }), in: 0...255)
                        Text("\(Int(Double(c.fan) / 2.55))%").font(.footnote.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 40)
                    }
                    Row {
                        RowLabel(title: "Cheek LEDs", subtitle: "NeoPixels on the cheek connector")
                        Stepper("\(c.cheekCount)", value: binding(c.cheekCount, "cheekCount"), in: 0...64).fixedSize()
                    }
                    Row {
                        Text("Cheek style").frame(maxWidth: .infinity, alignment: .leading)
                        Picker("", selection: binding(c.cheekMode, "cheekMode")) {
                            ForEach(CheekMode.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                    }
                    Row {
                        ColorPicker("Cheek color", selection: Binding(get: { RGB(hex: c.cheekColor).color }, set: { store.setConfig("cheekColor", RGB($0).hex) }),
                                    supportsOpacity: false)
                    }
                    sliderRow("Cheek brightness", value: c.cheekBright, range: 0...255, key: "cheekBright")
                }

                SectionHeader(title: "Connections")
                RowGroup {
                    textRow("Name", c.devName, "devName", hint: "Shown in Bluetooth")
                    toggleRow("Bluetooth", "Restart to apply", c.bleOn, "bleOn")
                    textRow("Hotspot name", c.apName, "apName")
                    Row {
                        RowLabel(title: "Hotspot password", subtitle: "8+ characters, empty = open")
                        SecureField(c.apPassSet ? "unchanged" : "none", text: $apPass)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { store.setConfig("apPass", apPass) }
                    }
                    textRow("Home Wi-Fi", c.staSsid, "staSsid", hint: "Network name")
                    Row {
                        Text("Home Wi-Fi password").frame(maxWidth: .infinity, alignment: .leading)
                        SecureField("unchanged", text: $staPass).multilineTextAlignment(.trailing)
                            .onSubmit { store.setConfig("staPass", staPass) }
                    }
                    Row {
                        RowLabel(title: "Hotspot \(s.net.ap)", subtitle: s.net.sta.isEmpty ? "Not on home Wi-Fi" : "Home Wi-Fi \(s.net.sta) · proot.local")
                        Button("Apply Wi-Fi") { confirm = .wifi }.buttonStyle(SmallButtonStyle())
                    }
                }

                SectionHeader(title: "Stats")
                HStack(spacing: 10) {
                    stat("Boops", "\(s.stats.boops)")
                    stat("Best burst", "\(s.stats.peakRapid)")
                    stat("Hours", String(format: "%.1f", Double(s.stats.minutes) / 60))
                }

                SectionHeader(title: "Firmware")
                RowGroup {
                    Row { Text("Version").frame(maxWidth: .infinity, alignment: .leading); Text(s.version).foregroundStyle(Theme.dim) }
                    Row { Text("Face set").frame(maxWidth: .infinity, alignment: .leading); Text(s.vendorFaces ? "ProtoFrenz (imported)" : "Proot default").foregroundStyle(Theme.dim) }
                    Row {
                        RowLabel(title: "Update firmware", subtitle: store.isBLE ? "Connect over Wi-Fi to update" : "Pick a Proot firmware .bin")
                        Button("Choose") { otaPicking = true }.buttonStyle(SmallButtonStyle()).disabled(store.isBLE || store.isDemo)
                    }
                }
                if let p = otaProgress { ProgressView(value: p).tint(Theme.pink).padding(.top, 10) }

                HStack(spacing: 10) {
                    Button("Restart") { confirm = .reboot }.buttonStyle(GlowButtonStyle(style: .plain))
                    Button("Reset stats") { confirm = .stats }.buttonStyle(GlowButtonStyle(style: .danger))
                    Button("Factory reset") { confirm = .factory }.buttonStyle(GlowButtonStyle(style: .danger))
                }
                .padding(.top, 14)
                Button("Disconnect") { store.disconnect(forget: true) }
                    .buttonStyle(GlowButtonStyle(style: .plain))
                    .padding(.top, 10)
                Text("Proot · open firmware for ProtoFrenz controllers").font(.footnote).foregroundStyle(Theme.faint).padding(.top, 20)
            }
            .onAppear { store.meter(true) }
            .onDisappear { store.meter(false) }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    store.meter(true)
                }
            }
            .fileImporter(isPresented: $otaPicking, allowedContentTypes: [UTType(filenameExtension: "bin") ?? .data, .data]) { result in
                guard case .success(let url) = result else { return }
                flash(url)
            }
            .alert(item: $confirm) { which in
                switch which {
                case .reboot:
                    return Alert(title: Text("Restart the visor?"), primaryButton: .default(Text("Restart")) { store.send(["cmd": "reboot"]) }, secondaryButton: .cancel())
                case .stats:
                    return Alert(title: Text("Reset boop and game stats?"), primaryButton: .destructive(Text("Reset")) { store.send(["cmd": "resetStats"]) }, secondaryButton: .cancel())
                case .factory:
                    return Alert(title: Text("Erase all settings?"), message: Text("Expressions, colors and settings go back to defaults. Animations stay."),
                                 primaryButton: .destructive(Text("Erase")) { store.send(["cmd": "factoryReset"]) }, secondaryButton: .cancel())
                case .wifi:
                    return Alert(title: Text("Restart Wi-Fi now?"), message: Text("You may need to rejoin the hotspot."),
                                 primaryButton: .default(Text("Apply")) { store.send(["cmd": "applyWifi"]) }, secondaryButton: .cancel())
                }
            }
        }
    }

    private func flash(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        otaProgress = 0
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                try await store.otaUpdate(fileURL: url) { otaProgress = $0 }
                store.flash("Updated — the visor is restarting")
            } catch {
                store.flash(error.localizedDescription)
            }
            otaProgress = nil
        }
    }

    private func binding<T>(_ value: T, _ key: String) -> Binding<T> {
        Binding(get: { value }, set: { store.setConfig(key, $0) })
    }

    private func sliderRow(_ title: String, value: Int, range: ClosedRange<Int>, key: String) -> some View {
        Row {
            Text(title)
            Slider(value: Binding(get: { Double(value) }, set: { store.setConfig(key, Int($0)) }), in: Double(range.lowerBound)...Double(range.upperBound))
            Text("\(value)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 34, alignment: .trailing)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String?, _ value: Bool, _ key: String) -> some View {
        Row { Toggle(isOn: binding(value, key)) { RowLabel(title: title, subtitle: subtitle) } }
    }

    private func textRow(_ title: String, _ value: String, _ key: String, hint: String? = nil) -> some View {
        Row {
            RowLabel(title: title, subtitle: hint)
            TextField(title, text: Binding(get: { value }, set: { store.setConfig(key, String($0.prefix(31))) }))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold).monospacedDigit())
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .cardBackground()
    }
}
