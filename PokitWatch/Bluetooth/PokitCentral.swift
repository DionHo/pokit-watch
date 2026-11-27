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
    /// Waiting for the remembered device to come into range. This does not time out while
    /// the app is on screen.
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
    /// Which of the device's functions is in use.
    @Published private(set) var tool: Tool = .meter

    let meter = MeterState()
    let scope = ScopeState()
    let logger = LoggerState()

    // MARK: Private state

    private enum Keys {
        static let deviceID = "device.id"
        static let deviceName = "device.name"
        static let deviceProduct = "device.product"
        static let mode = "meter.mode"
        static let loggerMode = "logger.mode"
        static let loggerInterval = "logger.interval"
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
        /// How long to wait after connecting for the data logger's state before assuming
        /// that it is not recording.
        static let startupTimeout: TimeInterval = 1.5
        /// The oscilloscope and the logger can be silent for a long time (waiting for a
        /// trigger, recording). A small read this often keeps a live link apart from a dead one.
        static let keepAliveInterval: TimeInterval = 4
        static let loggerPollInterval: TimeInterval = 10
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

        static let dso = CBUUID(string: PokitUUID.dsoService)
        static let dsoSettings = CBUUID(string: PokitUUID.dsoSettings)
        static let dsoMetadata = CBUUID(string: PokitUUID.dsoMetadata)
        static let dsoReading = CBUUID(string: PokitUUID.dsoReading)
        static let logger = CBUUID(string: PokitUUID.loggerService)
        static let loggerSettings = CBUUID(string: PokitUUID.loggerSettings)
        static let loggerMetadata = CBUUID(string: PokitUUID.loggerMetadata)
        static let loggerReading = CBUUID(string: PokitUUID.loggerReading)

        static let manufacturer = CBUUID(string: PokitUUID.manufacturerName)
        static let model = CBUUID(string: PokitUUID.modelNumber)
        static let serial = CBUUID(string: PokitUUID.serialNumber)
        static let firmware = CBUUID(string: PokitUUID.firmwareRevision)
        static let hardware = CBUUID(string: PokitUUID.hardwareRevision)
        static let software = CBUUID(string: PokitUUID.softwareRevision)

        static let services = [statusMeter, statusPro, multimeter, dso, logger, deviceInformation]
        // The logger's state comes first: nothing is started on the device before it is known.
        static let readOnConnect = [
            loggerMetadata, deviceCharacteristics, status, deviceName, torch,
            manufacturer, model, serial, firmware, hardware, software,
        ]
        static let notifyOnConnect = [
            reading, status, buttonPress, torch, dsoMetadata, dsoReading, loggerMetadata, loggerReading,
        ]
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

    /// The app is on screen. Only then is there a link to the meter, see `setAppActive`.
    private var appIsActive = true
    /// Closes the link shortly after the app left the screen, once the idle command is out.
    private var pendingClose: DispatchWorkItem?
    private var housekeeping: Timer?
    private var setupDeadline: Date?
    private var lastLinkActivity = Date.distantPast
    private var lastMatchingReading = Date.distantPast
    private var lastNudge = Date.distantPast
    private var lastStatusPoll = Date.distantPast
    private var lastHaptic = Date.distantPast
    private var lastConnectCheck = Date.distantPast
    private var hadContinuity = false
    /// Restarts in a row without a single reading in between; slows down the retries.
    private var consecutiveFailures = 0
    /// Connected and set up, but still waiting to learn whether the data logger is recording.
    /// Until that is known nothing is written to the device, see `finishSetup`.
    private var awaitingStartup = false
    private var startupDeadline = Date.distantPast
    private var lastKeepAlive = Date.distantPast

    // Oscilloscope: one capture is assembled from a Metadata value and many sample packets.
    private var scopeRaw: [Int16] = []
    private var scopeMetadata: ScopeMetadata?
    private var scopeArmedAt = Date.distantPast
    private var lastScopePacket = Date.distantPast
    private var scopeRearm: DispatchWorkItem?
    /// The range the app's own auto-ranging has arrived at; `nil` starts from the highest.
    private var scopeAutoRange: UInt8?

    // Data logger: a fetch is assembled the same way.
    private var loggerRaw: [Int16] = []
    private var loggerFetchMetadata: LoggerMetadata?
    private var lastLoggerPacket = Date.distantPast
    private var lastLoggerPoll = Date.distantPast

    // MARK: Lifecycle

    override init() {
        super.init()

        if let stored = MultimeterMode(rawValue: UInt8(truncatingIfNeeded: defaults.integer(forKey: Keys.mode))),
           stored != .idle {
            mode = stored
        }
        device = loadRememberedDevice()
        if let device {
            reconcileSelection(with: device.product)
        }
        meter.reset(for: mode)
        if let stored = LoggerMode(rawValue: UInt8(truncatingIfNeeded: defaults.integer(forKey: Keys.loggerMode))) {
            logger.mode = stored
        }
        let storedInterval = UInt32(truncatingIfNeeded: defaults.integer(forKey: Keys.loggerInterval))
        if LoggerState.intervals.contains(storedInterval) {
            logger.interval = storedInterval
        }

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
        if let demo {
            demo.showList(central: self)
            return
        }
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
        range = .auto
        reconcileSelection(with: found.product)
        meter.reset(for: mode)
        consecutiveFailures = 0
        beginConnection()
    }

    /// Disconnects and forgets the device, then goes back to scanning.
    func forgetDevice() {
        if let demo {
            demo.showList(central: self)
            return
        }
        let old = peripheral
        if phase == .ready, !awaitingStartup {
            stopDeviceActivity()
        }
        remember(nil)
        peripheral = nil
        linkDown()
        tool = .meter
        scope.capture = nil
        scopeAutoRange = nil
        logger.metadata = nil
        logger.log = nil
        status = nil
        details = DeviceDetails()
        discovered = []
        seenPeripherals.removeAll()
        consecutiveFailures = 0
        phase = .idle
        if let old {
            // A moment for the idle command to go out before the link is closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                // Leave it alone if the user picked the same device again in the meantime.
                guard let self, self.peripheral !== old else { return }
                self.central?.cancelPeripheralConnection(old)
            }
        }
        // A scan that is already running does not report the same devices a second time,
        // so start a fresh one for the now empty list.
        stopScanning()
        if appIsActive {
            startScanning()
        }
    }

    func select(mode newMode: MultimeterMode) {
        guard newMode != .idle else { return }
        if tool != .meter {
            // Starting a measurement would end a running log.
            guard !logger.isSampling else { return }
            leaveTool()
            tool = .meter
        }
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

    // MARK: Tools

    /// Switches between multimeter, oscilloscope and data logger.
    func open(_ newTool: Tool) {
        guard newTool != tool, !logger.isSampling else { return }
        leaveTool()
        tool = newTool
        if let demo {
            demo.show(newTool, central: self)
            return
        }
        startTool()
    }

    func setScope(mode newMode: MultimeterMode) {
        guard ScopeSettings.modes.contains(newMode), newMode != scope.mode else { return }
        scope.mode = newMode
        scope.range = .auto
        scopeAutoRange = nil
        scope.capture = nil
        restartScope()
    }

    func setScope(range newRange: RangeSelection) {
        guard newRange != scope.range else { return }
        scope.range = newRange
        restartScope()
    }

    func setScope(window newWindow: UInt32) {
        guard newWindow != scope.window else { return }
        scope.window = newWindow
        restartScope()
    }

    func setScope(trigger newTrigger: ScopeTriggerKind) {
        guard newTrigger != scope.trigger else { return }
        scope.trigger = newTrigger
        restartScope()
    }

    /// Run / hold for the oscilloscope.
    func toggleScopeRunning() {
        scope.isRunning.toggle()
        WKInterfaceDevice.current().play(.click)
        if scope.isRunning {
            armScope()
        } else {
            scopeRearm?.cancel()
            scopeRearm = nil
            if scope.activity == .waiting, phase == .ready {
                // Cancels a capture that is still waiting for its trigger.
                writeScope(.idle)
            }
            scope.activity = .idle
        }
    }

    func setLogger(mode newMode: LoggerMode) {
        guard newMode != logger.mode else { return }
        logger.mode = newMode
        logger.rangeIndex = nil
        defaults.set(Int(newMode.rawValue), forKey: Keys.loggerMode)
    }

    func setLogger(rangeIndex newIndex: UInt8) {
        logger.rangeIndex = newIndex
    }

    func setLogger(interval newInterval: UInt32) {
        logger.interval = newInterval
        defaults.set(Int(newInterval), forKey: Keys.loggerInterval)
    }

    /// Starts a recording on the device. It keeps running without the watch.
    func startLogger() {
        guard demo == nil else { return }
        guard phase == .ready, tool == .logger, !awaitingStartup, !logger.isSampling, let device else { return }
        let ranges = device.product.ranges(for: logger.mode.multimeterMode)
        var index = ranges.last?.index ?? 0
        if let chosen = logger.rangeIndex, ranges.contains(where: { $0.index == chosen }) {
            index = chosen
        }
        logger.startWasRejected = false
        logger.log = nil
        // The start time rides along as the timestamp, so the log can be dated later.
        writeLogger(.start(
            mode: logger.mode,
            rangeIndex: index,
            interval: logger.interval,
            timestamp: UInt32(clamping: Int(Date().timeIntervalSince1970))
        ))
        readLoggerMetadata(after: 0.6)
    }

    /// Ends the recording and fetches what was recorded.
    func stopLogger() {
        guard demo == nil else { return }
        guard phase == .ready, !awaitingStartup else { return }
        writeLogger(.stop)
        readLoggerMetadata(after: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.fetchLog()
        }
    }

    /// Asks the device for everything recorded so far. Works during a recording too.
    func fetchLog() {
        guard demo == nil else { return }
        guard phase == .ready, !awaitingStartup, !logger.isFetching,
              characteristics[GATT.loggerSettings] != nil else { return }
        loggerRaw.removeAll(keepingCapacity: true)
        loggerFetchMetadata = nil
        lastLoggerPacket = Date()
        logger.isFetching = true
        writeLogger(.refresh)
    }

    /// Called when the app appears on screen or leaves it (another app, the watch face, or
    /// the system returning to the clock after the wrist has been down for a while).
    ///
    /// The link only exists while the app is on screen. A connected Pokit uses more power than
    /// one that is just waiting, and a pending connection would grab the meter the moment it
    /// is switched on, whether anybody is looking or not. So leaving the screen ends the
    /// measurement and the connection; coming back reconnects to the remembered device.
    func setAppActive(_ active: Bool) {
        guard active != appIsActive else { return }
        appIsActive = active
        guard demo == nil else { return }
        if active {
            pendingClose?.cancel()
            pendingClose = nil
            consecutiveFailures = 0
            markLinkFresh()
            if device != nil {
                phase = .connecting
            }
            resume()
        } else {
            suspendLink()
        }
    }

    // MARK: Connection management

    /// Makes sure whatever should be happening is happening: connecting to the remembered
    /// device, or scanning when there is none.
    private func resume() {
        guard isPoweredOn, appIsActive else { return }
        if device != nil {
            if let peripheral, peripheral.state == .connected {
                if phase != .ready, phase != .preparing {
                    // Still connected from before the app left the screen (it came back before
                    // the link was closed): set the link up again instead of reconnecting.
                    prepare(peripheral)
                }
            } else if peripheral == nil || peripheral?.state == .disconnected {
                beginConnection()
            }
        } else {
            startScanning()
        }
    }

    /// Ends the measurement and the connection because the app is no longer on screen.
    /// The device stays remembered; `setAppActive(true)` brings the link back.
    private func suspendLink() {
        stopScanning()
        let wasReady = phase == .ready
        if wasReady, !awaitingStartup {
            stopDeviceActivity()
        }
        linkDown()
        phase = .idle
        guard let peripheral else { return }

        guard wasReady else {
            // Also withdraws a connection request that is still waiting for the device.
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        // A moment for the stop command to go out before the link is closed.
        let close = DispatchWorkItem { [weak self] in
            guard let self, !self.appIsActive else { return }
            self.pendingClose = nil
            self.central?.cancelPeripheralConnection(peripheral)
        }
        pendingClose = close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: close)
        // Ask for the runtime to get that far before the app is suspended.
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Disconnect the meter") { expired in
            if !expired {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    /// Starts service discovery on a connected peripheral.
    private func prepare(_ peripheral: CBPeripheral) {
        linkDown()
        phase = .preparing
        setupDeadline = Date().addingTimeInterval(Timing.setupTimeout)
        peripheral.delegate = self
        peripheral.discoverServices(GATT.services)
    }

    /// Makes mode and range valid for `product`: a mode the product does not have (capacitance
    /// on a Pokit Meter) or a range index from the other product's table would be rejected.
    private func reconcileSelection(with product: PokitProduct) {
        if !product.measurementModes.contains(mode) {
            mode = .dcVoltage
            range = .auto
            defaults.set(Int(mode.rawValue), forKey: Keys.mode)
            meter.reset(for: mode)
        } else if case .fixed(let index) = range, product.range(for: mode, index: index) == nil {
            range = .auto
        }
    }

    private func beginConnection() {
        guard isPoweredOn, appIsActive, let central, let device else { return }

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
        // and in range. That is the wanted auto-reconnect behaviour while the app is on
        // screen; `suspendLink` withdraws the request when it leaves.
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
        consecutiveFailures += 1
        linkDown()
        phase = appIsActive ? .connecting : .idle
        central?.cancelPeripheralConnection(peripheral)
        // The disconnect callback normally triggers the reconnect; this covers the cases
        // where it does not arrive (e.g. cancelling a connection that was still pending).
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay + 1.5) { [weak self] in
            self?.resume()
        }
    }

    /// Half a second normally; up to a few seconds when restarts keep failing, so a device
    /// that cannot be set up is not hammered with connection attempts.
    private var reconnectDelay: TimeInterval {
        min(4, Timing.reconnectDelay * pow(2, Double(min(consecutiveFailures, 4))))
    }

    /// Forgets everything tied to the current link. The peripheral itself is kept.
    private func linkDown() {
        characteristics.removeAll()
        pendingServiceDiscoveries = 0
        setupDeadline = nil
        torchIsOn = nil
        hadContinuity = false
        // Battery and switch position may have changed by the time the link is back.
        status = nil
        awaitingStartup = false
        scopeRearm?.cancel()
        scopeRearm = nil
        scopeRaw.removeAll()
        scopeMetadata = nil
        if scope.activity != .idle {
            scope.activity = .idle
        }
        loggerRaw.removeAll()
        loggerFetchMetadata = nil
        if logger.isFetching {
            logger.isFetching = false
        }
        if meter.isReceiving {
            meter.isReceiving = false
        }
        if meter.modeWasRejected {
            meter.modeWasRejected = false
        }
    }

    private func scheduleReconnect() {
        guard appIsActive else {
            // Nobody is looking: stay disconnected until the app is back on screen.
            phase = .idle
            return
        }
        if device != nil {
            phase = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
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

        // Starting a measurement could end a recording the data logger is making, possibly
        // one started hours ago. So the first command waits until the logger's state, which
        // was just requested, has arrived (or it is clear that it will not).
        awaitingStartup = true
        startupDeadline = Date().addingTimeInterval(Timing.startupTimeout)
        if characteristics[GATT.loggerMetadata] == nil {
            beginActivity(loggerIsSampling: false)
        }
    }

    /// Ends the wait after connecting and starts what the current tool needs.
    private func beginActivity(loggerIsSampling: Bool) {
        guard awaitingStartup else { return }
        awaitingStartup = false
        if loggerIsSampling {
            // A recording is in progress: show it and keep the hands off everything else.
            tool = .logger
        }
        startTool()
    }

    /// Puts the device into the state the current tool needs.
    private func startTool() {
        guard phase == .ready, appIsActive, !awaitingStartup else { return }
        markLinkFresh()
        switch tool {
        case .meter:
            applySettings()
        case .scope:
            if scope.isRunning {
                armScope()
            }
        case .logger:
            readLoggerMetadata()
        }
    }

    /// Ends what the current tool was doing on the device, before another tool takes over.
    private func leaveTool() {
        switch tool {
        case .meter:
            if phase == .ready, !awaitingStartup {
                write(.idle)
            }
            if meter.isReceiving {
                meter.isReceiving = false
            }
        case .scope:
            scopeRearm?.cancel()
            scopeRearm = nil
            if phase == .ready, !awaitingStartup {
                writeScope(.idle)
            }
            scopeRaw.removeAll()
            scopeMetadata = nil
            scope.activity = .idle
        case .logger:
            loggerRaw.removeAll()
            loggerFetchMetadata = nil
            logger.isFetching = false
        }
    }

    /// Tells the device to stop what the current tool started, before the link is closed.
    /// A data log is left running: recording without the watch is its purpose.
    private func stopDeviceActivity() {
        switch tool {
        case .meter:
            write(.idle)
        case .scope:
            writeScope(.idle)
        case .logger:
            break
        }
    }

    // MARK: Talking to the meter

    private func currentSettings() -> MultimeterSettings {
        // Continuity should react quickly; the other modes do not need more than a few readings a second.
        let interval: UInt32 = mode == .continuity ? 100 : 250
        return MultimeterSettings(mode: mode, range: range, updateInterval: interval)
    }

    /// Sends the selected mode and range to the meter.
    private func applySettings() {
        guard phase == .ready, appIsActive, tool == .meter, !awaitingStartup else { return }
        write(currentSettings())
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

    // MARK: Oscilloscope

    private func writeScope(_ settings: ScopeSettings) {
        guard let peripheral, let characteristic = characteristics[GATT.dsoSettings] else { return }
        peripheral.writeValue(settings.encoded(), for: characteristic, type: writeType(for: characteristic))
    }

    /// Changed settings apply to a new capture, also when the display was on hold.
    private func restartScope() {
        if !scope.isRunning {
            scope.isRunning = true
        }
        armScope()
    }

    /// Requests one capture. The device answers with Metadata and then the samples.
    private func armScope() {
        scopeRearm?.cancel()
        scopeRearm = nil
        guard phase == .ready, appIsActive, tool == .scope, !awaitingStartup, let device else { return }

        let ranges = device.product.ranges(for: scope.mode)
        // Without a better idea the highest range is the safe one to start from.
        var index = ranges.last?.index ?? 0
        switch scope.range {
        case .fixed(let fixed):
            if ranges.contains(where: { $0.index == fixed }) {
                index = fixed
            }
        case .auto:
            if let chosen = scopeAutoRange, ranges.contains(where: { $0.index == chosen }) {
                index = chosen
            }
        }

        let trigger: ScopeTrigger
        switch scope.trigger {
        case .off: trigger = .freeRunning
        case .rising: trigger = .risingEdge(level: scopeTriggerLevel)
        case .falling: trigger = .fallingEdge(level: scopeTriggerLevel)
        }

        scopeRaw.removeAll(keepingCapacity: true)
        scopeMetadata = nil
        scopeArmedAt = Date()
        if scope.activity != .waiting {
            scope.activity = .waiting
        }
        writeScope(ScopeSettings(
            trigger: trigger,
            mode: scope.mode,
            rangeIndex: index,
            window: scope.window,
            sampleCount: ScopeState.sampleCount
        ))
    }

    /// Halfway between the extremes of the last capture, so that the trigger fires on
    /// whatever signal is there without a level having to be dialled in on a watch.
    private var scopeTriggerLevel: Float {
        guard let capture = scope.capture, capture.mode == scope.mode, let summary = capture.summary else {
            return 0
        }
        return Float((summary.minimum + summary.maximum) / 2)
    }

    private func handleScopeMetadata(_ data: Data) {
        guard tool == .scope, let metadata = ScopeMetadata(data: data) else { return }
        switch metadata.status {
        case .done:
            scopeMetadata = metadata
            finishScopeCapture(givingUp: false)
        case .error:
            scopeRaw.removeAll(keepingCapacity: true)
            scopeMetadata = nil
            scope.activity = .failed
        case .sampling, .bufferFull, .unknown:
            break
        }
    }

    private func handleScopeSamples(_ data: Data) {
        guard tool == .scope, scope.activity == .waiting || scope.activity == .receiving,
              let samples = SampleDecoder.samples(from: data) else { return }
        scopeRaw.append(contentsOf: samples)
        lastScopePacket = Date()
        if scope.activity != .receiving {
            scope.activity = .receiving
        }
        finishScopeCapture(givingUp: false)
    }

    /// Turns the collected samples into a capture once all of them are there.
    ///
    /// - Parameter givingUp: the samples stopped coming before the announced number was
    ///   reached; show what arrived instead of waiting forever.
    private func finishScopeCapture(givingUp: Bool) {
        guard tool == .scope, let device, !scopeRaw.isEmpty else { return }
        guard let metadata = scopeMetadata, metadata.scale.isFinite, metadata.scale != 0 else {
            if givingUp {
                // Samples that cannot be scaled are useless.
                scopeRaw.removeAll(keepingCapacity: true)
                scope.activity = .failed
            }
            return
        }
        let isComplete = metadata.sampleCount > 0 && scopeRaw.count >= metadata.sampleCount
        guard isComplete || givingUp else { return }

        let count = isComplete ? metadata.sampleCount : scopeRaw.count
        let values = scopeRaw.prefix(count).map { Double($0) * metadata.scale }
        // The window covers the samples that were asked for. The rate the device reports is
        // not used: the one capture from a Pokit Pro on record does not add up.
        let window = Double(metadata.window > 0 ? metadata.window : scope.window) / 1_000_000
        let perWindow = isComplete ? count : Int(ScopeState.sampleCount)
        let rate = window > 0 ? Double(perWindow) / window : 0
        let captureMode = MultimeterMode(rawValue: metadata.modeByte).flatMap {
            ScopeSettings.modes.contains($0) ? $0 : nil
        } ?? scope.mode
        let summary = WaveformSummary(samples: values, sampleRate: rate)

        scopeRaw.removeAll(keepingCapacity: true)
        scopeMetadata = nil
        scope.capture = ScopeCapture(
            values: values,
            sampleRate: rate,
            mode: captureMode,
            range: device.product.range(for: captureMode, index: metadata.rangeIndex),
            summary: summary
        )
        scope.activity = .idle
        consecutiveFailures = 0

        if scope.range == .auto, let summary {
            scopeAutoRange = ScopeRangeAdvisor.nextRange(
                current: metadata.rangeIndex,
                peak: max(abs(summary.minimum), abs(summary.maximum)),
                ranges: device.product.ranges(for: captureMode)
            )
        }
        if scope.isRunning {
            // A short pause, so a fast time base does not turn the display into a flicker.
            let rearm = DispatchWorkItem { [weak self] in
                self?.armScope()
            }
            scopeRearm = rearm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: rearm)
        }
    }

    private func scopeTick(_ now: Date) {
        switch scope.activity {
        case .receiving:
            if now.timeIntervalSince(lastScopePacket) > 1 {
                finishScopeCapture(givingUp: true)
            }
        case .waiting:
            // A capture without trigger arrives right after its window. With a trigger the
            // wait is open-ended, and that is fine.
            let expected = Double(scope.window) / 1_000_000 + 4
            if scope.trigger == .off, now.timeIntervalSince(scopeArmedAt) > expected {
                armScope()
            }
        case .idle, .failed:
            // Safety net for a re-arm that got lost, and the retry after an error.
            if scope.isRunning, scopeRearm == nil, now.timeIntervalSince(scopeArmedAt) > 2 {
                armScope()
            }
        }
    }

    // MARK: Data logger

    /// The Pokit Meter and the Pokit Pro use different layouts. What the device itself sent
    /// is the best evidence; before that, the product decides.
    private var loggerLayout: LoggerLayout {
        logger.metadata?.layout ?? LoggerLayout(product: device?.product ?? .meter)
    }

    private func writeLogger(_ settings: LoggerSettings) {
        guard let peripheral, let characteristic = characteristics[GATT.loggerSettings] else { return }
        peripheral.writeValue(
            settings.encoded(layout: loggerLayout),
            for: characteristic,
            type: writeType(for: characteristic)
        )
    }

    private func readLoggerMetadata() {
        guard phase == .ready, let peripheral, let characteristic = characteristics[GATT.loggerMetadata] else {
            return
        }
        lastLoggerPoll = Date()
        peripheral.readValue(for: characteristic)
    }

    private func readLoggerMetadata(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.readLoggerMetadata()
        }
    }

    private func handleLoggerMetadata(_ data: Data) {
        guard let metadata = LoggerMetadata(data: data) else {
            beginActivity(loggerIsSampling: false)
            return
        }
        if logger.metadata != metadata {
            logger.metadata = metadata
        }
        beginActivity(loggerIsSampling: metadata.status == .sampling)
        if logger.isFetching {
            loggerFetchMetadata = metadata
            lastLoggerPacket = Date()
            finishLogFetch(givingUp: false)
        }
    }

    private func handleLoggerSamples(_ data: Data) {
        guard logger.isFetching, let samples = SampleDecoder.samples(from: data) else { return }
        loggerRaw.append(contentsOf: samples)
        lastLoggerPacket = Date()
        finishLogFetch(givingUp: false)
    }

    /// Turns the fetched samples into a log once all of them are there.
    ///
    /// - Parameter givingUp: nothing has arrived for a while; take what is there.
    private func finishLogFetch(givingUp: Bool) {
        guard logger.isFetching else { return }
        guard let metadata = loggerFetchMetadata ?? (givingUp ? logger.metadata : nil) else {
            if givingUp {
                loggerRaw.removeAll()
                logger.isFetching = false
            }
            return
        }
        guard givingUp || loggerRaw.count >= metadata.sampleCount else { return }

        let count = givingUp ? loggerRaw.count : metadata.sampleCount
        let scale = metadata.scale.isFinite ? metadata.scale : 0
        let values = loggerRaw.prefix(count).map { Double($0) * scale }
        loggerRaw.removeAll()
        loggerFetchMetadata = nil
        logger.log = LoggedData(
            values: values,
            mode: metadata.mode,
            interval: metadata.interval,
            start: metadata.startDate,
            summary: WaveformSummary(samples: values)
        )
        logger.isFetching = false
    }

    private func loggerTick(_ now: Date) {
        if logger.isFetching {
            if now.timeIntervalSince(lastLoggerPacket) > 3 {
                finishLogFetch(givingUp: true)
            }
        } else if logger.isSampling, now.timeIntervalSince(lastLoggerPoll) > Timing.loggerPollInterval {
            // Keeps the sample count on screen moving.
            readLoggerMetadata()
        }
    }

    // MARK: Multimeter readings

    private func handleReading(_ data: Data) {
        guard let reading = MultimeterReading(data: data), let device else { return }
        let now = Date()

        // Readings for another mode are leftovers from before a mode change, or the meter
        // reporting that it is idle.
        guard reading.mode == mode, appIsActive, tool == .meter else { return }
        lastMatchingReading = now
        consecutiveFailures = 0
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
        guard isPoweredOn, appIsActive else { return }
        let now = Date()

        switch phase {
        case .preparing:
            if let setupDeadline, now > setupDeadline {
                restartConnection()
            }

        case .ready:
            if awaitingStartup {
                if now > startupDeadline {
                    // No answer about the logger: carry on as if it were not recording.
                    beginActivity(loggerIsSampling: false)
                }
                return
            }
            if now.timeIntervalSince(lastStatusPoll) > Timing.statusPollInterval {
                pollStatus()
            }

            if now.timeIntervalSince(lastLinkActivity) > Timing.deadLinkTimeout {
                // Neither notifications nor read responses: the link is dead even though the
                // system has not noticed yet.
                restartConnection()
                return
            }
            guard tool == .meter else {
                if tool == .scope {
                    scopeTick(now)
                } else {
                    loggerTick(now)
                }
                if now.timeIntervalSince(lastLinkActivity) > Timing.keepAliveInterval,
                   now.timeIntervalSince(lastKeepAlive) > Timing.keepAliveInterval {
                    lastKeepAlive = now
                    pollStatus()
                }
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

        case .connecting:
            // A connection request can get lost without a callback. Asking again is harmless
            // when it is still pending.
            if now.timeIntervalSince(lastConnectCheck) > 5 {
                lastConnectCheck = now
                resume()
            }

        case .idle, .scanning:
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
            switch UserDefaults.standard.string(forKey: "PokitDemoTool") {
            case "scope": central.open(.scope)
            case "logger": central.open(.logger)
            default: break
            }
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self, weak central] _ in
            guard let self, let central else { return }
            self.step += 1
            central.demoFeed(self.reading(for: central.mode, product: central.device?.product ?? .meter))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Fills the oscilloscope or the logger with made-up data.
    func show(_ tool: Tool, central: PokitCentral) {
        switch tool {
        case .meter:
            break
        case .scope:
            // Two and a half periods of a 5 V square wave with a bit of overshoot.
            let count = Int(ScopeState.sampleCount)
            let values = (0..<count).map { index -> Double in
                let periods = Double(index) / Double(count) * 2.5
                let position = periods - periods.rounded(.down)
                let isHigh = position < 0.5
                let sinceEdge = isHigh ? position : position - 0.5
                let decay: Double = exp(-sinceEdge * 40)
                let ring: Double = 0.6 * decay * cos(sinceEdge * 180)
                return isHigh ? 5.0 + ring : 0.0 - ring
            }
            let rate = Double(count) / (Double(central.scope.window) / 1_000_000)
            central.demoShowCapture(values: values, sampleRate: rate)
        case .logger:
            // A battery slowly running down, one sample every ten seconds.
            let values = (0..<90).map { index -> Double in
                let step = Double(index)
                let slope: Double = 4.1 - step * 0.004
                let wave: Double = 0.05 * sin(step / 6)
                let noise: Double = 0.01 * sin(step * 1.7)
                return slope - wave + noise
            }
            // `-PokitDemoScreen log` shows a finished recording instead of a running one.
            let isSampling = UserDefaults.standard.string(forKey: "PokitDemoScreen") != "log"
            central.demoShowLog(values: values, isSampling: isSampling)
        }
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

    fileprivate func demoShowCapture(values: [Double], sampleRate: Double) {
        let product = device?.product ?? .meter
        scope.capture = ScopeCapture(
            values: values,
            sampleRate: sampleRate,
            mode: scope.mode,
            range: product.ranges(for: scope.mode).first { $0.fullScale >= 6 },
            summary: WaveformSummary(samples: values, sampleRate: sampleRate)
        )
        scope.activity = .idle
    }

    fileprivate func demoShowLog(values: [Double], isSampling: Bool) {
        // Metadata as a Pokit Pro sends it: status, scale, mode, range, interval (10 s),
        // sample count, six unknown bytes, start time.
        let start = UInt32(clamping: Int(Date().timeIntervalSince1970) - values.count * 10)
        var raw = Data([isSampling ? 1 : 0, 0x39, 0xF0, 0x45, 0x3C, LoggerMode.dcVoltage.rawValue, 2])
        raw.append(contentsOf: [0x10, 0x27, 0x00, 0x00])
        raw.append(UInt8(truncatingIfNeeded: values.count))
        raw.append(UInt8(truncatingIfNeeded: values.count >> 8))
        raw.append(contentsOf: [0, 0, 0, 0, 0, 0])
        raw.append(UInt8(truncatingIfNeeded: start))
        raw.append(UInt8(truncatingIfNeeded: start >> 8))
        raw.append(UInt8(truncatingIfNeeded: start >> 16))
        raw.append(UInt8(truncatingIfNeeded: start >> 24))
        logger.metadata = LoggerMetadata(data: raw)
        logger.log = LoggedData(
            values: values,
            mode: .dcVoltage,
            interval: 10,
            start: Date(timeIntervalSince1970: TimeInterval(start)),
            summary: WaveformSummary(samples: values)
        )
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
           device.id == found.id
            || (device.product == found.product && (device.name == found.name || device.name == peripheral.name)) {
            remember(RememberedPokit(id: found.id, name: found.name, product: found.product))
            beginConnection()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // A connection that completes after the app left the screen is not wanted any more.
        guard peripheral.identifier == self.peripheral?.identifier, appIsActive else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        prepare(peripheral)
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
            reconcileSelection(with: product)
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
        guard error == nil, let data = characteristic.value else {
            if characteristic.uuid == GATT.loggerMetadata {
                // The logger's state cannot be read; do not wait for it.
                beginActivity(loggerIsSampling: false)
            }
            return
        }

        switch characteristic.uuid {
        case GATT.reading:
            handleReading(data)
        case GATT.dsoMetadata:
            handleScopeMetadata(data)
        case GATT.dsoReading:
            handleScopeSamples(data)
        case GATT.loggerMetadata:
            handleLoggerMetadata(data)
        case GATT.loggerReading:
            handleLoggerSamples(data)
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
                switch tool {
                case .meter: toggleHold()
                case .scope: toggleScopeRunning()
                case .logger: break
                }
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
            // Only a real answer from the device counts; a write that fails because the link
            // dropped says nothing about the mode.
            let rejected = (error as? CBATTError) != nil && appIsActive
            if meter.modeWasRejected != rejected {
                meter.modeWasRejected = rejected
            }
        } else if characteristic.uuid == GATT.torch, error != nil {
            peripheral.readValue(for: characteristic)
        } else if characteristic.uuid == GATT.dsoSettings, (error as? CBATTError) != nil {
            if tool == .scope, scope.activity == .waiting {
                scope.activity = .failed
            }
        } else if characteristic.uuid == GATT.loggerSettings, (error as? CBATTError) != nil {
            if tool == .logger, !logger.isSampling, !logger.isFetching {
                logger.startWasRejected = true
            }
            logger.isFetching = false
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
