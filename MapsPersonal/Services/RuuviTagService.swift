import Foundation
import CoreBluetooth

// MARK: - RuuviTag Sensor Data

struct RuuviTagData {
    let temperature: Double      // °C
    let humidity: Double         // RH%
    let pressure: Double         // hPa
    let batteryVoltage: Double   // mV
    let accelerationX: Int16     // mG
    let accelerationY: Int16     // mG
    let accelerationZ: Int16     // mG
    let movementCounter: UInt8
    let sequenceNumber: UInt16
    let rssi: Int                // dBm (signal strength)
    let timestamp: Date
}

// MARK: - RuuviTag Service

/// Scans for RuuviTag BLE advertisements and parses RAWv2 (Data Format 5) sensor data.
/// No pairing required — reads broadcast advertisements only.
@Observable
class RuuviTagService: NSObject {
    private var centralManager: CBCentralManager?
    private var isScanning = false

    /// Latest sensor reading (nil if no RuuviTag found)
    var latestData: RuuviTagData?

    /// Whether a RuuviTag has been detected recently (within last 30s)
    var isConnected: Bool {
        guard let data = latestData else { return false }
        return Date().timeIntervalSince(data.timestamp) < 30
    }

    /// Measured temperature in °C (convenience)
    var temperature: Double? { latestData?.temperature }
    /// Measured humidity in RH% (convenience)
    var humidity: Double? { latestData?.humidity }
    /// Measured pressure in hPa (convenience)
    var pressure: Double? { latestData?.pressure }
    /// Battery voltage in mV (convenience)
    var batteryVoltage: Double? { latestData?.batteryVoltage }

    private static let ruuviCompanyId: UInt16 = 0x0499

    // MARK: - Lifecycle

    func startScanning() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func stopScanning() {
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
        }
        centralManager = nil
        latestData = nil
    }

    // MARK: - RAWv2 Parsing

    /// Parse RAWv2 (Data Format 5) manufacturer-specific data.
    /// Payload starts after the 2-byte company ID (already stripped by CoreBluetooth).
    private func parseRAWv2(_ payload: Data, rssi: Int) -> RuuviTagData? {
        // Format 5 payload: 1 byte format + 23 bytes data = 24 bytes minimum
        guard payload.count >= 24, payload[0] == 0x05 else { return nil }

        let rawTemp = readInt16(payload, offset: 1)
        let rawHum = readUInt16(payload, offset: 3)
        let rawPres = readUInt16(payload, offset: 5)
        let accelX = readInt16(payload, offset: 7)
        let accelY = readInt16(payload, offset: 9)
        let accelZ = readInt16(payload, offset: 11)
        let powerInfo = readUInt16(payload, offset: 13)

        // Invalid value checks (max unsigned = sensor not available)
        guard rawTemp != Int16(bitPattern: 0x8000),
              rawHum != 0xFFFF,
              rawPres != 0xFFFF else { return nil }

        let temperature = Double(rawTemp) * 0.005
        let humidity = Double(rawHum) * 0.0025
        let pressure = (Double(rawPres) + 50000) / 100.0  // Pa → hPa
        let batteryVoltage = Double(powerInfo >> 5) + 1600

        return RuuviTagData(
            temperature: temperature,
            humidity: humidity,
            pressure: pressure,
            batteryVoltage: batteryVoltage,
            accelerationX: accelX,
            accelerationY: accelY,
            accelerationZ: accelZ,
            movementCounter: payload[15],
            sequenceNumber: readUInt16(payload, offset: 16),
            rssi: rssi,
            timestamp: Date()
        )
    }

    // MARK: - Binary Helpers

    private func readInt16(_ data: Data, offset: Int) -> Int16 {
        Int16(data[offset]) << 8 | Int16(data[offset + 1])
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}

// MARK: - CBCentralManagerDelegate

extension RuuviTagService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Scan with duplicates to get continuous advertisement updates
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
            print("RuuviTagService: BLE scanning started")
        case .poweredOff:
            isScanning = false
            print("RuuviTagService: Bluetooth is off")
        case .unauthorized:
            print("RuuviTagService: Bluetooth permission denied")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              manufacturerData.count >= 2 else { return }

        // CoreBluetooth provides company ID as first 2 bytes (little-endian)
        let companyId = UInt16(manufacturerData[0]) | (UInt16(manufacturerData[1]) << 8)
        guard companyId == Self.ruuviCompanyId else { return }

        let payload = manufacturerData.subdata(in: 2..<manufacturerData.count)
        guard let data = parseRAWv2(payload, rssi: RSSI.intValue) else {
            print("RuuviTagService: Ruuvi advert found but parse failed (format byte: \(payload.first.map { String(format: "0x%02X", $0) } ?? "nil"), payload \(payload.count) bytes)")
            return
        }

        // Deduplicate by sequence number
        if let existing = latestData, existing.sequenceNumber == data.sequenceNumber { return }

        print("RuuviTagService: \(String(format: "%.2f°C  %.1f%%  %.1f hPa  bat:%.0fmV  rssi:%d", data.temperature, data.humidity, data.pressure, data.batteryVoltage, data.rssi))")

        DispatchQueue.main.async { [weak self] in
            self?.latestData = data
        }
    }
}
