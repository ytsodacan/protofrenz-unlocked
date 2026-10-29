import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MediaView: View {
    @Environment(DeviceStore.self) private var store
    @State private var pick: PhotosPickerItem?
    @State private var importing = false
    @State private var source: [SourceFrame] = []
    @State private var converted: ConvertedAnim?
    @State private var name = ""
    @State private var layout = AnimLayout.mirror
    @State private var fit = AnimFit.fill
    @State private var sharp = false
    @State private var speed = 1.0
    @State private var progress: Double?
    @State private var text = ""
    @State private var rainbow = true
    @State private var textColor = Color(hex: 0x00E5FF)
    @State private var textSpeed = 28.0
    @State private var textSize = 2

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Animations")
            Card {
                if converted == nil { picker } else { converter }
            }
            if !store.files.isEmpty {
                RowGroup {
                    ForEach(store.files) { f in
                        Row {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text("\(f.frames) frames · \(f.size / 1024) KB · \(f.w == 128 ? "span" : "one panel")").font(.caption).foregroundStyle(Theme.dim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Play") { store.play(f.name) }.buttonStyle(SmallButtonStyle())
                            Button { store.remove(f.name) } label: { Image(systemName: "trash") }.buttonStyle(SmallButtonStyle(danger: true))
                        }
                    }
                }
                .padding(.top, 12)
            }
            if let fs = store.fs {
                Text("\(fs.free / 1024) KB free of \(fs.total / 1024) KB")
                    .font(.footnote).foregroundStyle(Theme.dim).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }

            SectionHeader(title: "Scrolling text")
            RowGroup {
                Row { TextField("Say something…", text: $text).submitLabel(.send).onSubmit(showText) }
                Row {
                    Text("Color").frame(maxWidth: .infinity, alignment: .leading)
                    Segmented(options: [(true, "Rainbow"), (false, "Solid")], selection: $rainbow).frame(width: 180)
                    if !rainbow { ColorPicker("", selection: $textColor, supportsOpacity: false).labelsHidden() }
                }
                Row { Text("Speed"); Slider(value: $textSpeed, in: 6...100) }
                Row {
                    Text("Size").frame(maxWidth: .infinity, alignment: .leading)
                    Segmented(options: [(1, "Small"), (2, "Big"), (3, "Huge")], selection: $textSize).frame(width: 200)
                }
            }
            HStack(spacing: 10) {
                Button("Show text", action: showText).buttonStyle(GlowButtonStyle(style: .pink))
                Button("Back to face") { store.setMode("face") }.buttonStyle(GlowButtonStyle(style: .plain))
            }
            .padding(.top, 12)
        }
        .onAppear { store.send(["cmd": "files"]) }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { load(data, name: "anim") }
                pick = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gif, .png, .jpeg, .webP, .image]) { result in
            guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) { load(data, name: url.deletingPathExtension().lastPathComponent) }
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("Add a GIF or image").font(.headline)
            Text("It's resized on your phone, then sent to the visor.").font(.footnote).foregroundStyle(Theme.dim)
            HStack(spacing: 10) {
                PhotosPicker(selection: $pick, matching: .any(of: [.images, .not(.livePhotos)])) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(GlowButtonStyle(style: .primary))
                Button { importing = true } label: { Label("Files", systemImage: "folder") }
                    .buttonStyle(GlowButtonStyle(style: .plain))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var converter: some View {
        if let c = converted {
            TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
                LEDVisor(buffer: c.preview(frameIndex(c, at: ctx.date.timeIntervalSinceReferenceDate)))
            }
            .padding(8)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 10) {
                HStack {
                    Text("Name")
                    TextField("anim", text: $name).multilineTextAlignment(.trailing)
                        .onChange(of: name) { _, v in name = String(v.filter { $0.isLetter || $0.isNumber || " -_".contains($0) }.prefix(28)) }
                }
                Segmented(options: AnimLayout.allCases.map { ($0, $0.label) }, selection: $layout)
                Segmented(options: AnimFit.allCases.map { ($0, $0.label) }, selection: $fit)
                Toggle(isOn: $sharp) { RowLabel(title: "Pixel art", subtitle: "Sharp scaling instead of smooth") }
                HStack {
                    Text("Speed")
                    Slider(value: $speed, in: 0.25...3)
                    Text(String(format: "%.2g×", speed)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 40)
                }
                Text("\(c.frames.count) frame\(c.frames.count == 1 ? "" : "s") · \(c.width)×32 · \(c.byteCount / 1024) KB")
                    .font(.footnote).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                if let p = progress { ProgressView(value: p).tint(Theme.pink) }
                HStack(spacing: 10) {
                    Button("Cancel") { converted = nil; source = [] }.buttonStyle(GlowButtonStyle(style: .plain))
                    Button(progress == nil ? "Upload & play" : "Uploading…", action: upload)
                        .buttonStyle(GlowButtonStyle(style: .primary)).disabled(progress != nil)
                }
            }
            .padding(.top, 12)
            .onChange(of: layout) { reconvert() }
            .onChange(of: fit) { reconvert() }
            .onChange(of: sharp) { reconvert() }
            .onChange(of: speed) { reconvert() }
        }
    }

    private func frameIndex(_ c: ConvertedAnim, at t: Double) -> Int {
        let total = c.frames.reduce(0) { $0 + $1.delayMs }
        guard total > 0 else { return 0 }
        var ms = Int(t * 1000) % total
        for (i, f) in c.frames.enumerated() {
            if ms < f.delayMs { return i }
            ms -= f.delayMs
        }
        return 0
    }

    private func load(_ data: Data, name base: String) {
        let frames = AnimConverter.load(data)
        guard !frames.isEmpty else {
            store.flash("Couldn't read that image")
            return
        }
        source = frames
        name = String(base.filter { $0.isLetter || $0.isNumber || " -_".contains($0) }.prefix(28))
        if name.isEmpty { name = "anim" }
        sharp = frames[0].image.width <= 128 && frames[0].image.height <= 64
        reconvert()
    }

    private func reconvert() {
        guard !source.isEmpty else { return }
        let budget = store.fs.map { max(64_000, Int(Double($0.free) * 0.9)) } ?? 1_200_000
        converted = AnimConverter.convert(source, layout: layout, fit: fit, sharp: sharp, speed: speed, maxBytes: budget)
    }

    private func upload() {
        guard let c = converted else { return }
        let fileName = name.isEmpty ? "anim" : name
        progress = 0
        Task {
            do {
                try await store.upload(name: fileName, data: c.encoded()) { p in progress = p }
                store.play(fileName)
                store.flash("Uploaded \(fileName)")
                converted = nil
                source = []
            } catch {
                store.flash("Upload failed: \(error.localizedDescription)")
            }
            progress = nil
        }
    }

    private func showText() {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return store.flash("Type something first") }
        store.showText(s, color: rainbow ? "rainbow" : RGB(textColor).hex, speed: textSpeed, size: textSize)
    }
}
