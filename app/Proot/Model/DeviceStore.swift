import Foundation
import Observation
import UIKit

enum ConnectionKind: Equatable {
    case none, ble(UUID), wifi(String), demo
}

@MainActor
@Observable
final class DeviceStore {
    var state: DeviceState?
    var faces = FaceLibrary()
    var files: [AnimFile] = []
    var fs: FsInfo?
    var link: LinkState = .idle
    var kind: ConnectionKind = .none
    var micLevel: Double = 0
    var lastBoop: Int?
    var toast: String?
    /// ProtoFrenz presets extracted on this phone (see FaceImporter); nil until imported.
    var importedFaces: FacesMessage? = FaceImporter.load()
    var faceImport: FaceImportStatus = .idle

    @ObservationIgnored let scanner = BLEScanner()
    @ObservationIgnored private var transport: Transport?
    @ObservationIgnored private var nextId = 1
    @ObservationIgnored private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    @ObservationIgnored private var uploadWaiter: CheckedContinuation<Int, Error>?
    @ObservationIgnored private var debounce: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var demoUpload: (name: String, size: Int, got: Int, frames: Int, w: Int)?

    var isConnected: Bool { link == .connected || kind == .demo }
    var isDemo: Bool { kind == .demo }
    var isBLE: Bool { if case .ble = kind { return true } else { return false } }

    var deviceName: String {
        state?.cfg.devName ?? scanner.visors.first(where: { if case .ble(let id) = kind { return $0.id == id } else { return false } })?.name ?? "Visor"
    }

    // MARK: connecting

    func autoConnect() {
        if let s = UserDefaults.standard.string(forKey: "lastBLE"), let id = UUID(uuidString: s) {
            reconnectTask = Task {
                for _ in 0..<20 where scanner.poweredOn == false { try? await Task.sleep(for: .milliseconds(150)) }
                if kind == .none { connectBLE(id) }
            }
        }
    }

    func connectBLE(_ id: UUID) {
        disconnect()
        guard let t = scanner.connect(id) else {
            link = .failed("Visor not found")
            return
        }
        kind = .ble(id)
        UserDefaults.standard.set(id.uuidString, forKey: "lastBLE")
        attach(t)
    }

    func connectWiFi(host: String) {
        disconnect()
        let t = WebSocketTransport(host: host)
        kind = .wifi(host)
        attach(t)
        t.open()
    }

    func startDemo() {
        disconnect()
        kind = .demo
        link = .connected
        faces = importedFaces.map(FaceLibrary.init) ?? FaceLibrary.demo
        state = DemoData.state
        files = []
        fs = FsInfo(total: 1_500_000, used: 0)
    }

    func disconnect(forget: Bool = false) {
        reconnectTask?.cancel()
        transport?.onState = nil
        transport?.onMessage = nil
        transport?.close()
        transport = nil
        kind = .none
        link = .idle
        state = nil
        if forget { UserDefaults.standard.removeObject(forKey: "lastBLE") }
        for (_, c) in pending { c.resume(throwing: CancellationError()) }
        pending.removeAll()
        uploadWaiter?.resume(throwing: CancellationError())
        uploadWaiter = nil
    }

    private func attach(_ t: Transport) {
        transport = t
        link = .connecting
        t.onState = { [weak self] s in
            Task { @MainActor in
                guard let self, self.transport === t else { return }
                self.link = s
                if s == .connected {
                    self.send(["cmd": "get"])
                    self.send(["cmd": "faces"])
                    self.send(["cmd": "files"])
                } else if case .failed = s, case .ble(let id) = self.kind {
                    // Out of range or visor rebooting: keep trying in the background.
                    try? await Task.sleep(for: .seconds(2))
                    if self.transport === t { self.connectBLE(id) }
                }
            }
        }
        t.onMessage = { [weak self] data, binary in
            Task { @MainActor in self?.receive(data, binary: binary) }
        }
    }

    // MARK: sending

    func send(_ obj: [String: Any]) {
        if isDemo { demo(obj); return }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        transport?.send(data, binary: false)
    }

    func sendBinary(_ data: Data) {
        if isDemo { demoBinary(data); return }
        transport?.send(data, binary: true)
    }

    @discardableResult
    func request(_ obj: [String: Any], timeout: Double = 8) async throws -> [String: Any] {
        let id = nextId
        nextId += 1
        var o = obj
        o["id"] = id
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            send(o)
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if let c = pending.removeValue(forKey: id) { c.resume(throwing: ProotError.timeout) }
            }
        }
    }

    /// Coalesces rapid changes (sliders, color wells) into one message per key.
    func debounced(_ key: String, delay: Double = 0.08, _ obj: [String: Any]) {
        debounce[key]?.cancel()
        debounce[key] = Task {
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { send(obj) }
        }
    }

    // MARK: receiving

    private func receive(_ data: Data, binary: Bool) {
        guard !binary, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["t"] as? String else { return }
        let dec = JSONDecoder()
        switch t {
        case "state":
            if let s = try? dec.decode(DeviceState.self, from: data) { mergeState(s) }
        case "faces":
            if let f = try? dec.decode(FacesMessage.self, from: data) { faces = FaceLibrary(f) }
        case "files":
            if let f = try? dec.decode(FilesMessage.self, from: data) {
                files = f.files
                fs = f.fs
            }
        case "ack":
            if let id = obj["id"] as? Int, let c = pending.removeValue(forKey: id) { c.resume(returning: obj) }
        case "up":
            if let err = obj["err"] as? String { uploadWaiter?.resume(throwing: ProotError.device(err)) } else { uploadWaiter?.resume(returning: obj["got"] as? Int ?? 0) }
            uploadWaiter = nil
        case "meter":
            micLevel = obj["mic"] as? Double ?? 0
        case "boop":
            lastBoop = obj["n"] as? Int
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        default:
            break
        }
    }

    /// Keeps local edits that haven't been sent yet from snapping back.
    private func mergeState(_ s: DeviceState) {
        if debounce.values.contains(where: { !$0.isCancelled }), var cur = state {
            cur.mode = s.mode
            cur.active = s.active
            cur.boop = s.boop
            cur.game = s.game
            cur.stats = s.stats
            cur.net = s.net
            cur.anim = s.anim
            state = cur
        } else {
            state = s
        }
    }

    // MARK: high-level actions

    func activate(_ i: Int) {
        state?.active = i
        state?.mode = "face"
        send(["cmd": "expr", "i": i])
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func updateExpression(_ i: Int, _ patch: [String: Any]) {
        guard var s = state, i < s.expr.count else { return }
        var e = s.expr[i]
        for (k, v) in patch {
            switch k {
            case "name": e.name = v as? String ?? e.name
            case "eye": e.eye = v as? Int ?? e.eye
            case "nose": e.nose = v as? Int ?? e.nose
            case "mouth": e.mouth = v as? Int ?? e.mouth
            case "colors": e.colors = v as? [String] ?? e.colors
            case "speed": e.speed = v as? Double ?? e.speed
            case "gradMode": e.gradMode = v as? String ?? e.gradMode
            case "blink": e.blink = v as? Bool ?? e.blink
            case "talk": e.talk = v as? Bool ?? e.talk
            case "cycle": e.cycle = v as? Bool ?? e.cycle
            case "custom": e.custom = v as? Bool ?? e.custom
            case "anim": e.anim = v as? String ?? e.anim
            default: break
            }
        }
        s.expr[i] = e
        state = s
        pendingPatch[i, default: [:]].merge(patch) { $1 }
        debounce["expr\(i)"]?.cancel()
        debounce["expr\(i)"] = Task {
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled, let p = pendingPatch.removeValue(forKey: i) else { return }
            var msg: [String: Any] = ["cmd": "setExpr", "i": i]
            msg.merge(p) { $1 }
            send(msg)
        }
    }

    @ObservationIgnored private var pendingPatch: [Int: [String: Any]] = [:]
    @ObservationIgnored private var uploadToken = 0

    func setCustom(_ i: Int, _ parts: CustomParts) {
        guard i < faces.custom.count else { return }
        faces.custom[i] = parts
        debounced("custom\(i)", delay: 0.15, ["cmd": "custom", "i": i, "eye": parts.eye.hex, "nose": parts.nose.hex,
                                              "mouth": parts.mouth.hex, "clearPaint": true])
    }

    func setConfig(_ key: String, _ value: Any) {
        guard var s = state else { return }
        var dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(s.cfg))) as? [String: Any] ?? [:]
        dict[key] = value
        if let d = try? JSONSerialization.data(withJSONObject: dict), let cfg = try? JSONDecoder().decode(DeviceConfig.self, from: d) {
            s.cfg = cfg
            state = s
        }
        debounced("cfg." + key, ["cmd": "set", "k": key, "v": value])
    }

    func setMode(_ m: String) {
        state?.mode = m
        send(["cmd": "mode", "m": m])
    }

    func startGame(_ id: String) {
        state?.mode = "game"
        state?.game.id = id
        send(["cmd": "game", "g": id])
    }

    func stopGame() {
        state?.mode = "face"
        state?.game.id = ""
        send(["cmd": "game", "g": ""])
    }

    func key(_ k: GameKey, down: Bool) { send(["cmd": "key", "k": k.rawValue, "d": down]) }

    func showText(_ s: String, color: String, speed: Double, size: Int) {
        state?.mode = "text"
        state?.text = TextState(s: s, color: color, speed: speed, size: size)
        send(["cmd": "text", "s": s, "color": color, "speed": speed, "size": size])
    }

    func play(_ name: String) {
        state?.mode = "anim"
        state?.anim = name
        send(["cmd": "anim", "name": name])
    }

    func remove(_ name: String) {
        files.removeAll { $0.name == name }
        send(["cmd": "rm", "name": name])
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            send(["cmd": "files"])
        }
    }

    func meter(_ on: Bool) { send(["cmd": "meter", "on": on]) }

    /// Live drawing frame. BLE uses RGB332 to halve the payload.
    func sendFrame(_ pixels: [RGB], width: Int, mirror: Bool) {
        let compact = isBLE
        var d = Data([1, (compact ? 1 : 0) | (mirror ? 0x80 : 0), UInt8(width), 32])
        d.reserveCapacity(4 + pixels.count * 2)
        for p in pixels {
            if compact {
                d.append(p.rgb332)
            } else {
                let v = p.rgb565
                d.append(UInt8(v & 0xFF))
                d.append(UInt8(v >> 8))
            }
        }
        state?.mode = "draw"
        sendBinary(d)
    }

    func upload(name: String, data: Data, kind: String = "anim", progress: @escaping (Double) -> Void) async throws {
        let start = try await request(["cmd": "upStart", "name": name, "kind": kind, "size": data.count])
        guard start["ok"] as? Bool == true else { throw ProotError.device("Not enough space on the visor") }
        let chunk = transport?.maxBinaryChunk ?? 4096
        var off = 0
        while off < data.count {
            let n = min(chunk, data.count - off)
            var pkt = Data([2])
            withUnsafeBytes(of: UInt32(off).littleEndian) { pkt.append(contentsOf: $0) }
            pkt.append(data.subdata(in: off..<(off + n)))
            uploadToken += 1
            let token = uploadToken
            _ = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int, Error>) in
                uploadWaiter = c
                sendBinary(pkt)
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    if token == uploadToken, let w = uploadWaiter {
                        uploadWaiter = nil
                        w.resume(throwing: ProotError.timeout)
                    }
                }
            }
            off += n
            progress(Double(off) / Double(data.count))
        }
        let end = try await request(["cmd": "upEnd"])
        guard end["ok"] as? Bool == true else { throw ProotError.device("The visor rejected the file") }
        send(["cmd": "files"])
    }

    // MARK: face library

    /// Downloads the official ProtoFrenz firmware, extracts its presets on the phone,
    /// keeps them, and installs them on the connected visor.
    func importProtoFrenzFaces() async {
        faceImport = .downloading
        do {
            importedFaces = try await FaceImporter.download()
            if isConnected { try await installFacePack() } else { faceImport = .idle }
            flash("ProtoFrenz faces imported")
        } catch {
            faceImport = .failed(error.localizedDescription)
        }
    }

    func installFacePack() async throws {
        guard let f = importedFaces else { return }
        if isDemo {
            faces = FaceLibrary(f)
            state?.facePack = true
            faceImport = .idle
            return
        }
        faceImport = .sending(0)
        defer { if case .sending = faceImport { faceImport = .idle } }
        try await upload(name: "faces", data: FaceImporter.pack(f), kind: "faces") { p in self.faceImport = .sending(p) }
        send(["cmd": "get"])
    }

    func removeFacePack() {
        if isDemo {
            faces = FaceLibrary.demo
            state?.facePack = false
            return
        }
        send(["cmd": "removeFacePack"])
    }

    func forgetImportedFaces() {
        FaceImporter.forget()
        importedFaces = nil
    }

    func otaUpdate(fileURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard case .wifi(let host) = kind else { throw ProotError.device("Connect over Wi-Fi to update firmware") }
        let firmware = try Data(contentsOf: fileURL)
        let boundary = "proot-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"firmware\"; filename=\"firmware.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(firmware)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var req = URLRequest(url: URL(string: "http://\(host)/api/ota")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        let delegate = UploadProgress(progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        let (_, resp) = try await session.upload(for: req, from: body)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ProotError.device("Update failed") }
    }

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == message { toast = nil }
        }
    }

    // MARK: demo

    private func demo(_ o: [String: Any]) {
        guard var s = state, let cmd = o["cmd"] as? String else { return }
        var ack = true
        switch cmd {
        case "custom", "set", "setExpr", "expr", "mode", "game", "text", "anim":
            break  // already applied optimistically
        case "files":
            fs = FsInfo(total: 1_500_000, used: files.reduce(0) { $0 + $1.size })
        case "upStart":
            demoUpload = (o["name"] as? String ?? "anim", o["size"] as? Int ?? 0, 0, 1, 64)
        case "upEnd":
            if let u = demoUpload { files.append(AnimFile(name: u.name, size: u.size, frames: u.frames, w: u.w)) }
        case "resetStats":
            s.stats = DeviceStats(boops: 0, boots: 0, minutes: 0, peakRapid: 0)
            state = s
        default:
            ack = o["id"] != nil
        }
        if ack, let id = o["id"] as? Int, let c = pending.removeValue(forKey: id) { c.resume(returning: ["ok": true]) }
    }

    private func demoBinary(_ d: Data) {
        guard d.first == 2, var u = demoUpload else { return }
        u.got += d.count - 5
        if d.count > 17, u.got == d.count - 5 {
            u.w = Int(d[9]) | Int(d[10]) << 8
            u.frames = Int(d[13]) | Int(d[14]) << 8
        }
        demoUpload = u
        uploadWaiter?.resume(returning: u.got)
        uploadWaiter = nil
    }
}

enum FaceImportStatus: Equatable {
    case idle
    case downloading
    case sending(Double)
    case failed(String)
}

enum ProotError: LocalizedError {
    case timeout
    case device(String)
    var errorDescription: String? {
        switch self {
        case .timeout: return "The visor didn't answer"
        case .device(let s): return s
        }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    let cb: (Double) -> Void
    init(_ cb: @escaping (Double) -> Void) { self.cb = cb }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData _: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        cb(Double(totalBytesSent) / Double(max(1, totalBytesExpectedToSend)))
    }
}

enum DemoData {
    static var state: DeviceState {
        func ex(_ i: Int, _ n: String, _ e: Int, _ no: Int, _ m: Int, _ c: [String], mode: String = "scroll", blink: Bool = true) -> Expression {
            Expression(i: i, name: n, eye: e, nose: no, mouth: m, colors: c, speed: 2, gradMode: mode, blink: blink, talk: true, cycle: true, custom: false, anim: "")
        }
        return DeviceState(
            version: "demo", vendorFaces: false, mode: "face", active: 0, boop: false,
            expr: [
                ex(0, "Idle", 0, 0, 0, ["#00E5FF", "#7A5CFF", "#FF3FA4"]),
                ex(1, "Happy", 2, 0, 2, ["#FFD23F", "#FF7A3F", "#FF3FA4"]),
                ex(2, "Angry", 3, 0, 1, ["#FF1E1E", "#FF6A00"]),
                ex(3, "Sad", 4, 0, 5, ["#3F7BFF", "#00C2FF"]),
                ex(4, "Surprised", 5, 3, 7, ["#00FFC8", "#00A2FF"]),
                ex(5, "Love", 6, 2, 2, ["#FF4FD8", "#FF2A6D"]),
                ex(6, "Dizzy", 11, 0, 10, ["#B04FFF", "#00E5FF"], mode: "rainbow"),
                ex(7, "Dead", 7, 5, 4, ["#8A8A9A", "#50506A"], blink: false),
            ],
            cfg: DeviceConfig(brightness: 110, fan: 191, micSens: 5, boopOn: true, boopExpr: 1, boopMs: 2500, cheekCount: 0,
                              cheekMode: "face", cheekBright: 60, cheekColor: "#FF3FA4", mirror: true, swapPanels: false,
                              rotate: false, driver: 0, devName: "Demo visor", apName: "Proot-DEMO", apPassSet: false,
                              staSsid: "", bleOn: true),
            game: GameState(id: "", score: 0, best: [0, 0, 0, 0]), anim: "",
            text: TextState(s: "Hello!", color: "rainbow", speed: 28, size: 2),
            stats: DeviceStats(boops: 42, boots: 3, minutes: 190, peakRapid: 9),
            net: NetInfo(ap: "192.168.4.1", sta: "", wsClients: 0, ble: true, heap: 0))
    }
}
