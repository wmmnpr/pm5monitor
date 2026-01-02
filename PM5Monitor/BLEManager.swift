import Foundation
import CoreBluetooth

@MainActor
class BLEManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isBluetoothOn = false
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var devices: [CBPeripheral] = []
    @Published var currentWatts: Int = 0
    @Published var forceHistory: [Double] = []

    /// Complete rowing metrics for racing
    @Published var currentMetrics = RowingMetrics()

    // MARK: - PM5 UUIDs

    private let pm5RowingServiceUUID = CBUUID(string: "CE060030-43E5-11E4-916C-0800200C9A66")

    // General Status - provides elapsed time, distance, workout state
    private let generalStatusUUID = CBUUID(string: "CE060031-43E5-11E4-916C-0800200C9A66")

    // Additional Status 1 - provides stroke rate, pace, stroke count
    private let additionalStatus1UUID = CBUUID(string: "CE060032-43E5-11E4-916C-0800200C9A66")

    // Stroke Data - provides drive force
    private let strokeDataUUID = CBUUID(string: "CE060035-43E5-11E4-916C-0800200C9A66")

    // Additional Stroke Data - provides stroke power (watts)
    private let additionalStrokeDataUUID = CBUUID(string: "CE060036-43E5-11E4-916C-0800200C9A66")

    // Additional Status 2 - provides average power
    private let additionalStatus2UUID = CBUUID(string: "CE060034-43E5-11E4-916C-0800200C9A66")

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private let maxForceHistorySize = 20

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    func startScanning() {
        guard isBluetoothOn else { return }
        devices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        isConnecting = true
        peripheral.delegate = self
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    private func cleanup() {
        connectedPeripheral = nil
        isConnected = false
        isConnecting = false
        currentWatts = 0
        forceHistory.removeAll()
        currentMetrics = RowingMetrics()
    }

    private func addForceToHistory(_ force: Double) {
        forceHistory.append(force)
        if forceHistory.count > maxForceHistorySize {
            forceHistory.removeFirst()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothOn = central.state == .poweredOn
            if !isBluetoothOn {
                isScanning = false
                devices.removeAll()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard let name = peripheral.name,
                  name.uppercased().contains("PM5") else { return }

            if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
                devices.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnecting = false
            isConnected = true
            peripheral.discoverServices([pm5RowingServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            cleanup()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnecting = false
            print("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }

            for service in services {
                if service.uuid == pm5RowingServiceUUID {
                    peripheral.discoverCharacteristics([
                        generalStatusUUID,
                        additionalStatus1UUID,
                        strokeDataUUID,
                        additionalStrokeDataUUID,
                        additionalStatus2UUID
                    ], for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }

            for characteristic in characteristics {
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, let data = characteristic.value else { return }

            switch characteristic.uuid {
            case generalStatusUUID:
                parseGeneralStatus(data)
            case additionalStatus1UUID:
                parseAdditionalStatus1(data)
            case strokeDataUUID:
                parseStrokeData(data)
            case additionalStrokeDataUUID:
                parseAdditionalStrokeData(data)
            case additionalStatus2UUID:
                parseAdditionalStatus2(data)
            default:
                break
            }
        }
    }

    // MARK: - Data Parsing

    private func parseGeneralStatus(_ data: Data) {
        // General Status (CE060031) - 19 bytes according to PM5 protocol:
        // Bytes 0-2: Elapsed Time (0.01 second resolution, little-endian)
        // Bytes 3-5: Distance (0.1 meter resolution, little-endian)
        // Byte 6: Workout Type
        // Byte 7: Interval Type
        // Byte 8: Workout State
        // Byte 9: Rowing State
        // Byte 10: Stroke State
        // Bytes 11-13: Total Work Distance (joules)
        // Bytes 14-16: Workout Duration
        // Byte 17: Workout Duration Type
        // Byte 18: Drag Factor

        guard data.count >= 19 else { return }

        // Elapsed time: 3 bytes, 0.01s resolution
        let elapsedTimeRaw = Int(data[0]) + Int(data[1]) * 256 + Int(data[2]) * 65536
        let elapsedTime = TimeInterval(elapsedTimeRaw) / 100.0

        // Distance: 3 bytes, 0.1m resolution
        let distanceRaw = Int(data[3]) + Int(data[4]) * 256 + Int(data[5]) * 65536
        let distance = Double(distanceRaw) / 10.0

        // Drag factor: byte 18
        let dragFactor = Int(data[18])

        currentMetrics.elapsedTime = elapsedTime
        currentMetrics.distance = distance
        currentMetrics.dragFactor = dragFactor
        currentMetrics.timestamp = Date()
    }

    private func parseAdditionalStatus1(_ data: Data) {
        // Additional Status 1 (CE060032):
        // Bytes 0-2: Elapsed Time (0.01 second resolution)
        // Byte 3: Stroke Rate (strokes per minute)
        // Bytes 4-5: Stroke Count (little-endian)
        // Bytes 6-8: Pace (split per 500m, 0.01 second resolution)
        // Bytes 9-10: Avg Pace
        // Byte 11: Rest Distance (for interval workouts)
        // Bytes 12-14: Rest Time

        guard data.count >= 9 else { return }

        // Stroke rate: byte 3
        let strokeRate = Int(data[3])

        // Stroke count: bytes 4-5
        let strokeCount = Int(data[4]) + Int(data[5]) * 256

        // Pace (split per 500m): bytes 6-8, 0.01s resolution
        let paceRaw = Int(data[6]) + Int(data[7]) * 256 + Int(data[8]) * 65536
        let pace = TimeInterval(paceRaw) / 100.0

        if strokeRate > 0 && strokeRate < 100 {
            currentMetrics.strokeRate = strokeRate
        }

        currentMetrics.strokeCount = strokeCount

        if pace > 0 && pace < 600 { // Pace should be under 10 minutes
            currentMetrics.pace = pace
        }
    }

    private func parseStrokeData(_ data: Data) {
        // Stroke Data (CE060035):
        // Bytes 12-13: Peak Drive Force (in lbs * 10)
        // Bytes 14-15: Average Drive Force (in lbs * 10)
        guard data.count >= 16 else { return }

        let peakDriveForce = Double(Int(data[12]) + Int(data[13]) * 256) / 10.0
        let avgDriveForce = Double(Int(data[14]) + Int(data[15]) * 256) / 10.0

        if peakDriveForce > 0 && peakDriveForce < 500 {
            addForceToHistory(peakDriveForce)
            currentMetrics.peakForce = peakDriveForce
            currentMetrics.avgForce = avgDriveForce
        }
    }

    private func parseAdditionalStrokeData(_ data: Data) {
        // Additional Stroke Data (CE060036):
        // Bytes 3-4: Stroke Power (watts)
        guard data.count >= 5 else { return }

        let watts = Int(data[3]) + Int(data[4]) * 256
        if watts > 0 && watts < 2000 {
            currentWatts = watts
            currentMetrics.watts = watts
        }
    }

    private func parseAdditionalStatus2(_ data: Data) {
        // Additional Status 2 (CE060034):
        // Bytes 4-5: Average Power (watts)
        guard data.count >= 6 else { return }

        let watts = Int(data[4]) + Int(data[5]) * 256
        if watts > 0 && watts < 2000 {
            currentMetrics.avgWatts = watts
            if currentWatts == 0 {
                currentWatts = watts
                currentMetrics.watts = watts
            }
        }
    }
}
