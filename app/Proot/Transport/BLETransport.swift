import CoreBluetooth
import Foundation

/// Proot GATT service. Each packet starts with a header byte:
/// bit7 = binary payload, bit6 = first packet, bit5 = last packet.
enum ProotUUID {
    static let service = CBUUID(string: "7f3e0001-4a2b-4d7e-9c1a-70726f6f7401")
    static let rx = CBUUID(string: "7f3e0002-4a2b-4d7e-9c1a-70726f6f7401")
    static let tx = CBUUID(string: "7f3e0003-4a2b-4d7e-9c1a-70726f6f7401")
}

struct DiscoveredVisor: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
}

/// Owns the CBCentralManager: scanning, and creating per-connection transports.
final class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var visors: [DiscoveredVisor] = []
    @Published var poweredOn = false
    @Published var unauthorized = false

    private(set) var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var wantScan = false
    fileprivate var active: BLETransport?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        wantScan = true
        guard poweredOn else { return }
        visors.removeAll()
        central.scanForPeripherals(withServices: [ProotUUID.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        for p in central.retrieveConnectedPeripherals(withServices: [ProotUUID.service]) {
            peripherals[p.identifier] = p
            upsert(DiscoveredVisor(id: p.identifier, name: p.name ?? "Visor", rssi: -50))
        }
    }

    func stopScan() {
        wantScan = false
        if central.state == .poweredOn { central.stopScan() }
    }

    func connect(_ id: UUID) -> BLETransport? {
        let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let p else { return nil }
        peripherals[id] = p
        stopScan()
        let t = BLETransport(peripheral: p, scanner: self)
        active = t
        central.connect(p, options: nil)
        return t
    }

    private func upsert(_ v: DiscoveredVisor) {
        if let i = visors.firstIndex(where: { $0.id == v.id }) { visors[i] = v } else { visors.append(v) }
        visors.sort { $0.rssi > $1.rssi }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        poweredOn = c.state == .poweredOn
        unauthorized = c.state == .unauthorized
        if poweredOn && wantScan { startScan() }
        if !poweredOn { active?.onState?(.failed("Bluetooth is off")) }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        peripherals[p.identifier] = p
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "Visor"
        upsert(DiscoveredVisor(id: p.identifier, name: name, rssi: rssi.intValue))
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { active?.didConnect() }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        active?.onState?(.failed(error?.localizedDescription ?? "Could not connect"))
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        active?.onState?(.failed("Disconnected"))
    }
}

final class BLETransport: NSObject, Transport, CBPeripheralDelegate {
    var onMessage: ((Data, Bool) -> Void)?
    var onState: ((LinkState) -> Void)?
    let isBLE = true
    let maxBinaryChunk = 2048

    private let peripheral: CBPeripheral
    private weak var scanner: BLEScanner?
    private var rx: CBCharacteristic?
    private var inbox = Data()
    private var inboxBinary = false
    private var outbox: [Data] = []

    init(peripheral: CBPeripheral, scanner: BLEScanner) {
        self.peripheral = peripheral
        self.scanner = scanner
        super.init()
        peripheral.delegate = self
        DispatchQueue.main.async { self.onState?(.connecting) }
    }

    fileprivate func didConnect() { peripheral.discoverServices([ProotUUID.service]) }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == ProotUUID.service }) else {
            onState?(.failed("Not a Proot visor"))
            return
        }
        p.discoverCharacteristics([ProotUUID.rx, ProotUUID.tx], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == ProotUUID.rx { rx = c }
            if c.uuid == ProotUUID.tx { p.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if c.uuid == ProotUUID.tx, c.isNotifying, rx != nil { onState?(.connected) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let v = c.value, let h = v.first else { return }
        if h & 0x40 != 0 {
            inbox.removeAll(keepingCapacity: true)
            inboxBinary = h & 0x80 != 0
        }
        inbox.append(v.dropFirst())
        if h & 0x20 != 0 {
            onMessage?(inbox, inboxBinary)
            inbox.removeAll(keepingCapacity: true)
        }
    }

    func send(_ data: Data, binary: Bool) {
        let chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse) - 1)
        var off = 0
        repeat {
            let n = min(chunk, data.count - off)
            var header: UInt8 = binary ? 0x80 : 0
            if off == 0 { header |= 0x40 }
            if off + n == data.count { header |= 0x20 }
            var pkt = Data([header])
            pkt.append(data.subdata(in: off..<(off + n)))
            outbox.append(pkt)
            off += n
        } while off < data.count
        pump()
    }

    private func pump() {
        guard let rx else { return }
        while !outbox.isEmpty, peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(outbox.removeFirst(), for: rx, type: .withoutResponse)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { pump() }

    func close() {
        outbox.removeAll()
        scanner?.central.cancelPeripheralConnection(peripheral)
    }
}
