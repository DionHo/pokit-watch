import Combine
import CoreBluetooth
import Foundation
import PokitKit
import WatchKit

/// A Pokit seen while scanning.
struct DiscoveredPokit: Identifiable, Equatable {
    let id: UUID
    var name: String
    var product: PokitProduct
    var rssi: Int
}

/// The device the app is bound to. It is stored, so the watch reconnects on its own.
struct RememberedPokit: Equatable {
    var id: UUID
    var name: String
    var product: PokitProduct
}

/// Static facts read from the device after connecting.
struct DeviceDetails: Equatable {
    var characteristics: DeviceCharacteristics?
    var manufacturer: String?
    var model: String?
    var serialNumber: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
}

enum BluetoothAvailability: Equatable {
    case unknown
    case ready
    case poweredOff
    case unauthorized
    case unsupported
}

enum ConnectionPhase: Equatable {
    /// Nothing in progress.
    case idle
    /// Looking for devices (for the list, or for a remembered device the system lost track of).
    case scanning
    /// Waiting for the remembered device to come into range. This never times out.
    case connecting
    /// Connected, discovering services.
    case preparing
    /// Connected and set up.
    case ready
}

/// The fast-changing measurement state. Kept apart from `PokitCentral` so that only the
/// measurement screen redraws with every reading.
final class MeterState: ObservableObject {
    @Published var display = MeterDisplay.placeholder(for: .dcVoltage)
    @Published var statistics = ReadingStatistics()
    @Published var isHolding = false
    /// Readings for the selected mode are arriving.
    @Published var isReceiving = false
    /// The device answered the last settings write with an error.
    @Published var modeWasRejected = false

    func reset(for mode: MultimeterMode) {
        display = .placeholder(for: mode)
        statistics.reset()
        isHolding = false
        isReceiving = false
        modeWasRejected = false
    }
}

/// Owns the Bluetooth link to one Pokit: scanning, connecting, keeping the connection alive
/// and translating characteristic values into app state.
///
/// Everything runs on the main queue (the central manager is created with `queue: nil`).
final class PokitCentral: NSObject, ObservableObject {
    // MARK: Published state

    @Published private(set) var bluetooth: BluetoothAvailability = .unknown
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var discovered: [DiscoveredPokit] = []
    @Published private(set) var device: RememberedPokit?
    @Published private(set) var details = DeviceDetails()
    @Published private(set) var status: DeviceStatus?
    @Published private(set) var torchIsOn: Bool?
    @Published private(set) var mode: MultimeterMode = .dcVoltage
    @Published private(set) var range: RangeSelection = .auto

    let meter = MeterState()

    // MARK: Private state

    private enum Keys {
        static let deviceID = "device.id"
        static let deviceName = "device.name"
        static let deviceProduct = "device.product"
        static let mode = "meter.mode"
    }

    private enum Timing {
        /// Give up on service discovery after this long and start over.
        static let setupTimeout: TimeInterval = 12
        /// No reading in the selected mode for this long: show "waiting" and re-send the settings.
        static let readingGap: TimeInterval = 3
        static let nudgeInterval: TimeInterval = 4
        /// Not even a read gets answered for this long: the link is dead, reconnect.
        static let deadLinkTimeout: TimeInterval = 12
        static let statusPollInterval: TimeInterval = 30
        static let reconnectDelay: TimeInterval = 0.5
    }

    private enum GATT {
        static let statusMeter = CBUUID(string: PokitUUID.statusServiceMeter)
        static let statusPro = CBUUID(string: PokitUUID.statusServicePro)
        static let multimeter = CBUUID(string: PokitUUID.multimeterService)
        static let deviceInformation = CBUUID(string: PokitUUID.deviceInformationService)

        static let settings = CBUUID(string: PokitUUID.multimeterSettings)
        static let reading = CBUUID(string: PokitUUID.multimeterReading)
        static let deviceCharacteristics = CBUUID(string: PokitUUID.deviceCharacteristics)
        static let status = CBUUID(string: PokitUUID.status)
        static let deviceName = CBUUID(string: PokitUUID.deviceName)
        static let flashLED = CBUUID(string: PokitUUID.flashLED)
        static let torch = CBUUID(string: PokitUUID.torch)
        static let buttonPress = CBUUID(string: PokitUUID.buttonPress)

        static let manufacturer = CBUUID(string: PokitUUID.manufacturerName)
        static let model = CBUUID(string: PokitUUID.modelNumber)
        static let serial = CBUUID(string: PokitUUID.serialNumber)
        static let firmware = CBUUID(string: PokitUUID.firmwareRevision)
        static let hardware = CBUUID(string: PokitUUID.hardwareRevision)
        static let software = CBUUID(string: PokitUUID.softwareRevision)

        static let services = [statusMeter, statusPro, multimeter, deviceInformation]
        static let readOnConnect = [
            deviceCharacteristics, status, deviceName, torch,
            manufacturer, model, serial, firmware, hardware, software,
        ]
        static let notifyOnConnect = [reading, status, buttonPress, torch]
    }

    private let defaults = UserDefaults.standard
    /// `nil` only in demo mode, which runs without Bluetooth.
    private var central: CBCentralManager?
    private var demo: DemoMeter?
    /// The peripheral for `device`. Core Bluetooth does not retain peripherals, so this must.
    private var peripheral: CBPeripheral?
    private var seenPeripherals: [UUID: CBPeripheral] = [:]
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var pendingServiceDiscoveries = 0

    private var appIsActive = true
    private var housekeeping: Timer?
    private var setupDeadline: Date?
    private var lastLinkActivity = Date.distantPast
    private var lastMatchingReading = Date.distantPast
    private var lastNudge = Date.distantPast
    private var lastStatusPoll = Date.distantPast
    private var lastHaptic = Date.distantPast
    private var hadContinuity = false

    // MARK: Lifecycle

    override init() {
        super.init()

        if let stored = MultimeterMode(rawValue: UInt8(truncatingIfNeeded: defaults.integer(forKey: Keys.mode))),
           stored != .idle {
            mode = stored
        }
        meter.reset(for: mode)
        device = loadRememberedDevice()

        if let scenario = defaults.string(forKey: DemoMeter.argument) {
            startDemo(scenario)
            return
        }

        central = CBCentralManager(delegate: self, queue: nil)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        housekeeping = timer
    }

    deinit {
        housekeeping?.invalidate()
    }

    private var isPoweredOn: Bool {
        central?.state == .poweredOn
    }

    // MARK: Intents

    /// Starts looking for Pokit devices. Safe to call repeatedly.
    func startScanning() {
        guard isPoweredOn, let central else { return }
        if !central.isScanning {
            central.scanForPeripherals(withServices: [GATT.statusMeter, GATT.statusPro], options: nil)
        }
        phase = .scanning
    }

    /// Clears the list and scans again.
    func rescan() {
        guard device == nil else { return }
        stopScanning()
        discovered = []
        seenPeripherals.removeAll()
        startScanning()
    }

    func connect(to found: DiscoveredPokit) {
        if let demo {
            demo.connect(to: found, central: self)
            return
        }
        remember(RememberedPokit(id: found.id, name: found.name, product: found.product))
        meter.reset(for: mode)
        beginConnection()
    }

    /// Disconnects and forgets the device, then goes back to scanning.
    func forgetDevice() {
        if let demo {
            demo.showList(central: self)
            return
        }
        let old = peripheral
        if phase == .ready {
            write(.idle)
        }
        remember(nil)
        peripheral = nil
        linkDown()
        status = nil
        details = DeviceDetails()
        discovered = []
        phase = .idle
        if let old {
            // A moment for the idle command to go out before the link is closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.central?.cancelPeripheralConnection(old)
            }
        }
        if appIsActive {
            startScanning()
        }
    }

    func select(mode newMode: MultimeterMode) {
        guard newMode != .idle else { return }
        if newMode != mode {
            mode = newMode
            range = .auto
            defaults.set(Int(newMode.rawValue), forKey: Keys.mode)
        }
        meter.reset(for: newMode)
        hadContinuity = false
        markLinkFresh()
        applySettings()
    }

    func select(range newRange: RangeSelection) {
        range = newRange
        meter.statistics.reset()
        meter.modeWasRejected = false
        markLinkFresh()
        applySettings()
    }

    func toggleHold() {
        meter.isHolding.toggle()
        WKInterfaceDevice.current().play(.click)
    }

    func resetStatistics() {
        meter.statistics.reset()
    }

    /// Flashes the LED on the device (Pokit Meter).
    func flashLED() {
        guard let peripheral, let characteristic = characteristics[GATT.flashLED] else { return }
        peripheral.writeValue(Data([1]), for: characteristic, type: writeType(for: characteristic))
    }

    /// Switches the torch (Pokit Pro).
    func setTorch(_ on: Bool) {
        guard let peripheral, let characteristic = characteristics[GATT.torch] else { return }
        torchIsOn = on
        peripheral.writeValue(Data([on ? 1 : 0]), for: characteristic, type: writeType(for: characteristic))
    }

    var canFlashLED: Bool {
        phase == .ready && device?.product.supportsFlashLED == true && characteristics[GATT.flashLED] != nil
    }

    var hasTorch: Bool {
        phase == .ready && characteristics[GATT.torch] != nil
    }

    /// Called when the app comes to the front or goes to the background.
    ///
    /// In the background the meter is put into idle: readings would only wake the app for
    /// nothing, and the Pokit saves power. The connection itself is kept where the system
    /// allows it, so measuring resumes immediately when the wrist is raised.
    func setAppActive(_ active: Bool) {
        guard active != appIsActive else { return }
        appIsActive = active
        if active {
            markLinkFresh()
            if phase == .ready {
                applySettings()
                pollStatus()
            } else {
                resume()
            }
        } else {
            if phase == .ready {
                applySettings()
                meter.isReceiving = false
            } else if phase == .scanning, device == nil {
                stopScanning()
                phase = .idle
            }
        }
    }

    // MARK: Connection management

    /// Makes sure whatever should be happening is happening: connecting to the remembered
    /// device, or scanning when there is none.
    private func resume() {
        guard isPoweredOn else { return }
        if device != nil {
            if peripheral == nil || peripheral?.state == .disconnected {
                beginConnection()
            }
        } else if appIsActive, phase != .scanning {
            startScanning()
        }
    }

    private func beginConnection() {
        guard isPoweredOn, let central, let device else { return }

        let candidate: CBPeripheral?
        if let current = peripheral, current.identifier == device.id {
            candidate = current
        } else {
            candidate = seenPeripherals[device.id]
                ?? central.retrievePeripherals(withIdentifiers: [device.id]).first
        }

        guard let target = candidate else {
            // The system no longer knows this identifier (it can change, e.g. after Bluetooth
            // was reset). Scan instead; the device is adopted again when it shows up.
            peripheral = nil
            startScanning()
            return
        }

        stopScanning()
        peripheral = target
        target.delegate = self
        phase = .connecting
        // A pending connection has no timeout: it completes whenever the Pokit is switched on
        // and in range. That is exactly the wanted auto-reconnect behaviour.
        central.connect(target, options: nil)
    }

    private func stopScanning() {
        if isPoweredOn, let central, central.isScanning {
            central.stopScan()
        }
    }

    /// Drops the current link and connects again from scratch.
    private func restartConnection() {
        guard let peripheral else { return }
        linkDown()
        phase = .connecting
        central?.cancelPeripheralConnection(peripheral)
        // The disconnect callback normally triggers the reconnect; this covers the cases
        // where it does not arrive (e.g. cancelling a connection that was still pending).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.resume()
        }
    }

    /// Forgets everything tied to the current link. The peripheral itself is kept.
    private func linkDown() {
        characteristics.removeAll()
        pendingServiceDiscoveries = 0
        setupDeadline = nil
        torchIsOn = nil
        hadContinuity = false
        if meter.isReceiving {
            meter.isReceiving = false
        }
    }

    private func scheduleReconnect() {
        if device != nil {
            phase = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.reconnectDelay) { [weak self] in
                self?.resume()
            }
        } else {
            phase = .idle
            resume()
        }
    }

    /// Bluetooth went away: all peripherals and connections are gone with it.
    private func bluetoothLost() {
        linkDown()
        peripheral = nil
        seenPeripherals.removeAll()
        discovered = []
        phase = .idle
    }

    private func finishSetup(for peripheral: CBPeripheral) {
        guard characteristics[GATT.reading] != nil, characteristics[GATT.settings] != nil else {
            // Without the multimeter service there is nothing to do; discovery probably went wrong.
            restartConnection()
            return
        }
        setupDeadline = nil

        // Notifications first, so the first reading after the settings write is not missed.
        for uuid in GATT.notifyOnConnect {
            if let characteristic = characteristics[uuid], characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        for uuid in GATT.readOnConnect {
            if let characteristic = characteristics[uuid], characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }

        phase = .ready
        lastStatusPoll = Date()
        markLinkFresh()
        applySettings()
    }

    // MARK: Talking to the meter

    private func currentSettings() -> MultimeterSettings {
        // Continuity should react quickly; the other modes do not need more than a few readings a second.
        let interval: UInt32 = mode == .continuity ? 100 : 250
        return MultimeterSettings(mode: mode, range: range, updateInterval: interval)
    }

    /// Sends the selected mode to the meter, or idle while the app is in the background.
    private func applySettings() {
        guard phase == .ready else { return }
        write(appIsActive ? currentSettings() : .idle)
        lastNudge = Date()
    }

    private func write(_ settings: MultimeterSettings) {
        guard let peripheral, let characteristic = characteristics[GATT.settings] else { return }
        peripheral.writeValue(settings.encoded(), for: characteristic, type: writeType(for: characteristic))
    }

    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    }

    private func pollStatus() {
        guard phase == .ready, let peripheral, let characteristic = characteristics[GATT.status] else { return }
        lastStatusPoll = Date()
        peripheral.readValue(for: characteristic)
    }

    private func markLinkFresh() {
        let now = Date()
        lastLinkActivity = now
        lastMatchingReading = now
        lastNudge = now
    }

    private func handleReading(_ data: Data) {
        guard let reading = MultimeterReading(data: data), let device else { return }
        let now = Date()

        // Readings for another mode are leftovers from before a mode change, or the meter
        // reporting that it is idle.
        guard reading.mode == mode, appIsActive else { return }
        lastMatchingReading = now
        if !meter.isReceiving {
            meter.isReceiving = true
        }
        if meter.modeWasRejected {
            meter.modeWasRejected = false
        }

        updateContinuityFeedback(for: reading, at: now)

        guard !meter.isHolding else { return }
        let display = MeterDisplay(reading: reading, product: device.product)
        if display != meter.display {
            meter.display = display
        }
        if display.condition == .normal {
            meter.statistics.add(reading.value)
        }
    }

    /// The Pokit has no beeper, so continuity is signalled on the wrist.
    private func updateContinuityFeedback(for reading: MultimeterReading, at now: Date) {
        let closed = reading.hasContinuity == true
        if closed {
            if !hadContinuity {
                WKInterfaceDevice.current().play(.start)
                lastHaptic = now
            } else if now.timeIntervalSince(lastHaptic) > 0.5 {
                WKInterfaceDevice.current().play(.click)
                lastHaptic = now
            }
        } else if hadContinuity {
            WKInterfaceDevice.current().play(.stop)
        }
        hadContinuity = closed
    }

    /// Runs once a second: setup timeout, battery polling and the reading watchdog.
    private func tick() {
        guard isPoweredOn else { return }
        let now = Date()

        switch phase {
        case .preparing:
            if let setupDeadline, now > setupDeadline {
                restartConnection()
            }

        case .ready:
            guard appIsActive else { return }
            if now.timeIntervalSince(lastStatusPoll) > Timing.statusPollInterval {
                pollStatus()
            }

            if now.timeIntervalSince(lastLinkActivity) > Timing.deadLinkTimeout {
                // Neither notifications nor read responses: the link is dead even though the
                // system has not noticed yet.
                restartConnection()
                return
            }
            if now.timeIntervalSince(lastMatchingReading) > Timing.readingGap {
                if meter.isReceiving {
                    meter.isReceiving = false
                }
                if now.timeIntervalSince(lastNudge) > Timing.nudgeInterval {
                    // The meter may have dropped back to idle on its own (button, switch, error).
                    // Ask again, and read once so a live link can be told from a dead one.
                    applySettings()
                    if let peripheral, let characteristic = characteristics[GATT.reading] {
                        peripheral.readValue(for: characteristic)
                    }
                }
            }

        case .idle, .scanning, .connecting:
            break
        }
    }

    // MARK: Persistence

    private func loadRememberedDevice() -> RememberedPokit? {
        guard let idString = defaults.string(forKey: Keys.deviceID),
              let id = UUID(uuidString: idString),
              let productString = defaults.string(forKey: Keys.deviceProduct),
              let product = PokitProduct(rawValue: productString) else {
            return nil
        }
        let name = defaults.string(forKey: Keys.deviceName) ?? product.displayName
        return RememberedPokit(id: id, name: name, product: product)
    }

    private func remember(_ newDevice: RememberedPokit?) {
        guard newDevice != device else { return }
        device = newDevice
        if let newDevice {
            defaults.set(newDevice.id.uuidString, forKey: Keys.deviceID)
            defaults.set(newDevice.name, forKey: Keys.deviceName)
            defaults.set(newDevice.product.rawValue, forKey: Keys.deviceProduct)
        } else {
            defaults.removeObject(forKey: Keys.deviceID)
            defaults.removeObject(forKey: Keys.deviceName)
            defaults.removeObject(forKey: Keys.deviceProduct)
        }
    }
}

// MARK: - Demo mode

/// A made-up meter for the simulator, which has no Bluetooth. Launch the app with
/// `-PokitDemo meter`, `-PokitDemo pro` or `-PokitDemo list` to try the UI or take screenshots;
/// add `-meter.mode 7` (a `MultimeterMode` raw value) to start in a particular mode and
/// `-PokitDemoScreen modes|ranges|device` to open one of the sub-screens right away.
private final class DemoMeter {
    static let argument = "PokitDemo"

    private var timer: Timer?
    private var step = 0

    func connect(to found: DiscoveredPokit, central: PokitCentral) {
        central.demoShowMeter(RememberedPokit(id: found.id, name: found.name, product: found.product))
    }

    func showList(central: PokitCentral) {
        central.demoShowList([
            DiscoveredPokit(id: UUID(), name: "PokitMeter", product: .meter, rssi: -58),
            DiscoveredPokit(id: UUID(), name: "PokitPro", product: .pro, rssi: -81),
        ])
    }

    func start(scenario: String, central: PokitCentral) {
        if scenario == "list" {
            showList(central: central)
        } else {
            let product: PokitProduct = scenario == "pro" ? .pro : .meter
            let name = product == .pro ? "PokitPro" : "PokitMeter"
            central.demoShowMeter(RememberedPokit(id: UUID(), name: name, product: product))
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self, weak central] _ in
            guard let self, let central else { return }
            self.step += 1
            central.demoFeed(self.reading(for: central.mode, product: central.device?.product ?? .meter))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A plausible reading for `mode`, with a little movement in the last digits.
    private func reading(for mode: MultimeterMode, product: PokitProduct) -> Data {
        let wobble = sin(Double(step) / 3)
        let value: Double
        var status: UInt8 = 1
        var range: UInt8 = 0
        switch mode {
        case .dcVoltage:
            value = 4.987 + wobble * 0.002
            range = 2
        case .acVoltage:
            value = 11.82 + wobble * 0.01
            range = 3
        case .dcCurrent:
            value = 0.0423 + wobble * 0.0001
            range = product == .pro ? 3 : 2
        case .acCurrent:
            value = 0.1264 + wobble * 0.0002
            range = product == .pro ? 4 : 2
        case .resistance:
            value = 1234 + wobble * 0.6
            range = 3
        case .continuity:
            value = 0.8 + wobble * 0.05
        case .diode:
            value = 0.612 + wobble * 0.001
            status = 0
        case .temperature, .externalTemperature:
            value = 23.4 + wobble * 0.05
            status = 0
        case .capacitance:
            value = 4.7e-6 + wobble * 1e-9
            range = 1
        case .idle:
            value = 0
            status = 0
        }
        var data = Data([status])
        withUnsafeBytes(of: Float(value).bitPattern.littleEndian) { data.append(contentsOf: $0) }
        data.append(mode.rawValue)
        data.append(range)
        return data
    }
}

extension PokitCentral {
    fileprivate func startDemo(_ scenario: String) {
        let demo = DemoMeter()
        self.demo = demo
        bluetooth = .ready
        demo.start(scenario: scenario, central: self)
    }

    fileprivate func demoShowList(_ devices: [DiscoveredPokit]) {
        device = nil
        discovered = devices
        phase = .scanning
    }

    fileprivate func demoShowMeter(_ device: RememberedPokit) {
        self.device = device
        meter.reset(for: mode)
        status = DeviceStatus(data: device.product == .pro
            ? Data([0x02, 0x64, 0x3B, 0x83, 0x40, 0x01, 0x00, 0x00])
            : Data([0x00, 0x25, 0x07, 0x33, 0x40]))
        phase = .ready
    }

    fileprivate func demoFeed(_ data: Data) {
        guard phase == .ready else { return }
        handleReading(data)
    }
}

// MARK: - CBCentralManagerDelegate

extension PokitCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetooth = .ready
            resume()
        case .poweredOff:
            bluetooth = .poweredOff
            bluetoothLost()
        case .unauthorized:
            bluetooth = .unauthorized
            bluetoothLost()
        case .unsupported:
            bluetooth = .unsupported
            bluetoothLost()
        case .resetting, .unknown:
            bluetooth = .unknown
            bluetoothLost()
        @unknown default:
            bluetooth = .unknown
            bluetoothLost()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let product: PokitProduct = advertised.contains(GATT.statusPro) ? .pro : .meter
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? product.displayName
        let found = DiscoveredPokit(id: peripheral.identifier, name: name, product: product, rssi: RSSI.intValue)

        seenPeripherals[peripheral.identifier] = peripheral

        if let index = discovered.firstIndex(where: { $0.id == found.id }) {
            let known = discovered[index]
            // Skip tiny signal changes so the list does not redraw constantly.
            if known.name != found.name || known.product != found.product || abs(known.rssi - found.rssi) >= 6 {
                discovered[index] = found
            }
        } else {
            discovered.append(found)
        }

        // Scanning on behalf of a remembered device whose identifier the system lost.
        if let device, self.peripheral == nil,
           device.id == found.id || (device.name == found.name && device.product == found.product) {
            remember(RememberedPokit(id: found.id, name: found.name, product: found.product))
            beginConnection()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        linkDown()
        phase = .preparing
        setupDeadline = Date().addingTimeInterval(Timing.setupTimeout)
        peripheral.delegate = self
        peripheral.discoverServices(GATT.services)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        linkDown()
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        linkDown()
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension PokitCentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            restartConnection()
            return
        }

        // The Status service UUID is the reliable way to tell Meter and Pro apart.
        let product = services.compactMap { PokitProduct(statusServiceUUID: $0.uuid.uuidString) }.first
        if let product, var device, device.product != product {
            device.product = product
            remember(device)
        }

        pendingServiceDiscoveries = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, phase == .preparing else { return }
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }
        pendingServiceDiscoveries -= 1
        if pendingServiceDiscoveries == 0 {
            finishSetup(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        // Any answer, even an error, proves the link is alive.
        lastLinkActivity = Date()
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case GATT.reading:
            handleReading(data)
        case GATT.status:
            if let newStatus = DeviceStatus(data: data), newStatus != status {
                status = newStatus
            }
        case GATT.deviceCharacteristics:
            details.characteristics = DeviceCharacteristics(data: data)
        case GATT.deviceName:
            if let name = PokitText.decode(data), var device, device.name != name {
                device.name = name
                remember(device)
            }
        case GATT.torch:
            torchIsOn = data.first.map { $0 != 0 }
        case GATT.buttonPress:
            // The button on the Pokit Pro doubles as a remote "hold" key.
            if ButtonEvent(data: data) == .pressed, phase == .ready, appIsActive {
                toggleHold()
            }
        case GATT.manufacturer:
            details.manufacturer = PokitText.decode(data)
        case GATT.model:
            details.model = PokitText.decode(data)
        case GATT.serial:
            details.serialNumber = PokitText.decode(data)
        case GATT.firmware:
            details.firmwareRevision = PokitText.decode(data)
        case GATT.hardware:
            details.hardwareRevision = PokitText.decode(data)
        case GATT.software:
            details.softwareRevision = PokitText.decode(data)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if characteristic.uuid == GATT.settings {
            // The Pokit answers a mode it cannot do right now with an error and stays idle.
            let rejected = error != nil && appIsActive
            if meter.modeWasRejected != rejected {
                meter.modeWasRejected = rejected
            }
        } else if characteristic.uuid == GATT.torch, error != nil {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if characteristic.uuid == GATT.reading, error != nil {
            // Without reading notifications the app is useless; try again from a clean link.
            restartConnection()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        restartConnection()
    }
}
