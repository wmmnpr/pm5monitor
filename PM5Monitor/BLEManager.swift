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

    // MARK: - PM5 UUIDs

    private let pm5RowingServiceUUID = CBUUID(string: "CE060030-43E5-11E4-916C-0800200C9A66")
    private let strokeDataUUID = CBUUID(string: "CE060035-43E5-11E4-916C-0800200C9A66")
    private let additionalStrokeDataUUID = CBUUID(string: "CE060036-43E5-11E4-916C-0800200C9A66")
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

    private func parseStrokeData(_ data: Data) {
        // Stroke Data (CE060035):
        // Bytes 12-13: Peak Drive Force (in lbs * 10)
        // Bytes 14-15: Average Drive Force (in lbs * 10)
        guard data.count >= 16 else { return }

        let peakDriveForce = Double(Int(data[12]) + Int(data[13]) * 256) / 10.0
        let avgDriveForce = Double(Int(data[14]) + Int(data[15]) * 256) / 10.0

        if peakDriveForce > 0 && peakDriveForce < 500 {
            addForceToHistory(peakDriveForce)
        }
    }

    private func parseAdditionalStrokeData(_ data: Data) {
        // Additional Stroke Data (CE060036):
        // Bytes 3-4: Stroke Power (watts)
        guard data.count >= 5 else { return }

        let watts = Int(data[3]) + Int(data[4]) * 256
        if watts > 0 && watts < 2000 {
            currentWatts = watts
        }
    }

    private func parseAdditionalStatus2(_ data: Data) {
        // Additional Status 2 (CE060034):
        // Bytes 4-5: Average Power (watts)
        guard data.count >= 6 else { return }

        let watts = Int(data[4]) + Int(data[5]) * 256
        if watts > 0 && watts < 2000 && currentWatts == 0 {
            currentWatts = watts
        }
    }
}
