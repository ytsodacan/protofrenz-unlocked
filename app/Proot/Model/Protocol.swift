import Foundation

// Mirrors the JSON the firmware sends (see firmware/src/main.cpp stateJson()).

struct Expression: Codable, Identifiable, Equatable {
    var i: Int
    var name: String
    var eye: Int
    var nose: Int
    var mouth: Int
    var colors: [String]
    var speed: Double
    var gradMode: String
    var blink: Bool
    var talk: Bool
    var cycle: Bool
    var custom: Bool
    var anim: String
    var id: Int { i }
}

struct DeviceConfig: Codable, Equatable {
    var brightness: Int
    var fan: Int
    var micSens: Int
    var boopOn: Bool
    var boopExpr: Int
    var boopMs: Int
    var cheekCount: Int
    var cheekMode: String
    var cheekBright: Int
    var cheekColor: String
    var mirror: Bool
    var swapPanels: Bool
    var rotate: Bool
    var driver: Int
    var devName: String
    var apName: String
    var apPassSet: Bool
    var staSsid: String
    var bleOn: Bool
}

struct GameState: Codable, Equatable {
    var id: String
    var score: Int
    var best: [Int]
}

struct TextState: Codable, Equatable {
    var s: String
    var color: String
    var speed: Double
    var size: Int
}

struct DeviceStats: Codable, Equatable {
    var boops: Int
    var boots: Int
    var minutes: Int
    var peakRapid: Int
}

struct NetInfo: Codable, Equatable {
    var ap: String
    var sta: String
    var wsClients: Int
    var ble: Bool
    var heap: Int
}

struct DeviceState: Codable, Equatable {
    var version: String
    var vendorFaces: Bool
    var facePack: Bool?
    var mode: String
    var active: Int
    var boop: Bool
    var expr: [Expression]
    var cfg: DeviceConfig
    var game: GameState
    var anim: String
    var text: TextState
    var stats: DeviceStats
    var net: NetInfo
}

struct AnimFile: Codable, Identifiable, Equatable {
    var name: String
    var size: Int
    var frames: Int
    var w: Int
    var id: String { name }
}

struct FsInfo: Codable, Equatable {
    var total: Int
    var used: Int
    var free: Int { max(0, total - used) }
}

struct FilesMessage: Codable {
    var files: [AnimFile]
    var fs: FsInfo
}

struct FacePart: Codable {
    var n: String
    var b: String
}

struct CustomPartsHex: Codable {
    var eye: String
    var nose: String
    var mouth: String
}

struct FacesMessage: Codable {
    var eyes: [FacePart]
    var noses: [FacePart]
    var mouths: [FacePart]
    var custom: [CustomPartsHex]?
}

enum GradMode: String, CaseIterable, Identifiable {
    case scroll, vertical, rainbow, solid
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CheekMode: String, CaseIterable, Identifiable {
    case face, solid, rainbow, mic, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .face: return "Match face"
        case .solid: return "Solid"
        case .rainbow: return "Rainbow"
        case .mic: return "Voice pulse"
        case .off: return "Off"
        }
    }
}

enum GameKey: String {
    case up, down, left, right, a, b
}

struct GameInfo: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String
    let colors: [UInt32]

    static let all: [GameInfo] = [
        GameInfo(id: "snake", name: "Snake", blurb: "Eat, grow, don't bite yourself", symbol: "scribble.variable", colors: [0x0F5132, 0x3FF2A0]),
        GameInfo(id: "paddle", name: "Paddle Duel", blurb: "First to 7 beats the CPU", symbol: "circle.and.line.horizontal", colors: [0x1E2A78, 0x00E5FF]),
        GameInfo(id: "bricks", name: "Brick Breaker", blurb: "Sideways block smashing", symbol: "square.grid.3x3.fill", colors: [0x5B1A74, 0xFF3FA4]),
        GameInfo(id: "comet", name: "Comet Dodge", blurb: "Weave through the storm", symbol: "sparkles", colors: [0x6B2A00, 0xFF8A00]),
    ]
}
