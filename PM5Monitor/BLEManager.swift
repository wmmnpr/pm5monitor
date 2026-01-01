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

    // MARK: - PM5 UUIDs

    private let pm5RowingServiceUUID = CBUUID(string: "CE060030-43E5-11E4-916C-0800200C9A66")
    private let additionalStrokeDataUUID = CBUUID(string: "CE060036-43E5-11E4-916C-0800200C9A66")
    private let additionalStatus2UUID = CBUUID(string: "CE060034-43E5-11E4-916C-0800200C9A66")

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

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
        // Scan for PM5 devices (they advertise with name "PM5")
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
            // Only show PM5 devices
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
                    peripheral.discoverCharacteristics([additionalStrokeDataUUID, additionalStatus2UUID], for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }

            for characteristic in characteristics {
                // Subscribe to notifications for power data
                if characteristic.uuid == additionalStrokeDataUUID ||
                   characteristic.uuid == additionalStatus2UUID {
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, let data = characteristic.value else { return }

            // Parse watts from PM5 data
            if characteristic.uuid == additionalStrokeDataUUID {
                // Additional Stroke Data: bytes 3-4 are stroke power
                if data.count >= 5 {
                    let watts = Int(data[3]) + Int(data[4]) * 256
                    if watts > 0 && watts < 2000 { // Sanity check
                        currentWatts = watts
                    }
                }
            } else if characteristic.uuid == additionalStatus2UUID {
                // Additional Status 2: bytes 4-5 are average power
                if data.count >= 6 {
                    let watts = Int(data[4]) + Int(data[5]) * 256
                    if watts > 0 && watts < 2000 && currentWatts == 0 {
                        currentWatts = watts
                    }
                }
            }
        }
    }
}
