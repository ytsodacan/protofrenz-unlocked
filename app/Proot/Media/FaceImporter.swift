import Foundation

/// Pulls the built-in face presets out of the official ProtoFrenz firmware image,
/// on the phone. Same decoding as tools/import_protofrenz_faces.py. The result is
/// kept in the app's own storage and sent to the visor as a face pack.
enum FaceImporter {
    static let releaseURL = URL(string: "https://github.com/protofrenz/protofrenz-firmware/releases/download/v3.0.13/ProtoFrenz.bin")!

    // Table locations in the v3.0.13 image (found by disassembling /api/presetpack).
    private static let eyes = (addr: UInt32(0x3F43_1080), count: 52)
    private static let noses = (addr: UInt32(0x3F43_0FC0), count: 24)
    private static let mouths = (addr: UInt32(0x3F43_13C0), count: 33)

    private static var savedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ProtoFrenzFaces.json")
    }

    static func download() async throws -> FacesMessage {
        let (data, resp) = try await URLSession.shared.data(from: releaseURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ProotError.device("Couldn't download the ProtoFrenz firmware") }
        let faces = try extract(from: data)
        try save(faces)
        return faces
    }

    static func extract(from image: Data) throws -> FacesMessage {
        let b = [UInt8](image)
        guard b.count > 24, b[0] == 0xE9, image.range(of: Data("3.0.13".utf8)) != nil else {
            throw ProotError.device("That isn't the ProtoFrenz v3.0.13 firmware")
        }
        func u32(_ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 }

        // Find the DROM (read-only data) segment.
        var off = 24
        var drom: (base: UInt32, start: Int, size: Int)?
        for _ in 0..<Int(b[1]) {
            guard off + 8 <= b.count else { break }
            let addr = u32(off), size = Int(u32(off + 4))
            if addr >= 0x3F40_0000, addr < 0x3F80_0000 { drom = (addr, off + 8, size) }
            off += 8 + size
        }
        guard let d = drom else { throw ProotError.device("No data segment in that firmware") }

        func u64(_ addr: UInt32) -> UInt64 {
            let o = d.start + Int(addr - d.base)
            return (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[o + $1]) << (8 * UInt64($1)) }
        }
        func byte(_ v: UInt64, _ i: Int) -> UInt8 { UInt8((v >> (8 * UInt64(i))) & 0xFF) }
        func rev(_ x: UInt8) -> UInt8 { (0..<8).reduce(UInt8(0)) { $0 | ((x >> $1) & 1) << (7 - $1) } }
        func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

        // Orientation matches the stock editor's pfDecodePresetBytes().
        let eyeList = (0..<eyes.count).map { i -> FacePart in
            let t0 = u64(eyes.addr + UInt32(16 * i)), t1 = u64(eyes.addr + UInt32(16 * i + 8))
            return FacePart(n: "Eye \(i + 1)", b: hex((0..<8).flatMap { r in [rev(byte(t1, r)), rev(byte(t0, r))] }))
        }
        let noseList = (0..<noses.count).map { i -> FacePart in
            let v = u64(noses.addr + UInt32(8 * i))
            return FacePart(n: "Nose \(i + 1)", b: hex((0..<8).map { byte(v, $0) }))
        }
        let mouthList = (0..<mouths.count).map { i -> FacePart in
            let tiles = (0..<5).map { u64(mouths.addr + UInt32(40 * i + 8 * $0)) }
            return FacePart(n: "Mouth \(i + 1)", b: hex((0..<8).flatMap { r in tiles.map { byte($0, 7 - r) } }))
        }
        return FacesMessage(eyes: eyeList, noses: noseList, mouths: mouthList, custom: nil)
    }

    static func save(_ f: FacesMessage) throws {
        try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(f).write(to: savedURL, options: .atomic)
    }

    static func load() -> FacesMessage? {
        guard let d = try? Data(contentsOf: savedURL) else { return nil }
        return try? JSONDecoder().decode(FacesMessage.self, from: d)
    }

    static func forget() { try? FileManager.default.removeItem(at: savedURL) }

    /// Face pack for the visor: "PFP1", u8 eyes, u8 noses, u8 mouths, u8 0, then each
    /// part as a 16-byte name followed by its bitmap.
    static func pack(_ f: FacesMessage) -> Data {
        var d = Data("PFP1".utf8)
        d.append(contentsOf: [UInt8(f.eyes.count), UInt8(f.noses.count), UInt8(f.mouths.count), 0])
        for list in [f.eyes, f.noses, f.mouths] {
            for p in list {
                var name = Array(p.n.utf8.prefix(16))
                name += [UInt8](repeating: 0, count: 16 - name.count)
                d.append(contentsOf: name)
                d.append(Data(hexString: p.b))
            }
        }
        return d
    }
}
