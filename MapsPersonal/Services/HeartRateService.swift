import Foundation
import HealthKit

// MARK: - Heart Rate Service

@Observable
class HeartRateService {
    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?

    /// Most recent heart rate in BPM, updated live during recording
    var currentHeartRate: Int?

    /// Whether HealthKit authorization has been granted
    var isAuthorized = false

    /// Whether the device supports HealthKit
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [hrType])
            let status = healthStore.authorizationStatus(for: hrType)
            isAuthorized = status == .sharingAuthorized || status != .notDetermined
            return isAuthorized
        } catch {
            return false
        }
    }

    // MARK: - Live HR Monitoring

    func startMonitoring() {
        guard isAvailable else { return }

        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHRSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHRSamples(samples)
        }

        healthStore.execute(query)
        self.query = query
    }

    func stopMonitoring() {
        if let query = query {
            healthStore.stop(query)
            self.query = nil
        }
        currentHeartRate = nil
    }

    /// Fetch HR samples for a specific time range (for retroactive assignment to track points)
    func fetchHeartRate(from start: Date, to end: Date) async -> [(date: Date, bpm: Int)] {
        guard isAvailable else { return [] }

        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortDescriptor = SortDescriptor(\HKQuantitySample.startDate)

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrType, predicate: predicate)],
                sortDescriptors: [sortDescriptor]
            )
            let samples = try await descriptor.result(for: healthStore)
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            return samples.map { sample in
                (date: sample.startDate, bpm: Int(sample.quantity.doubleValue(for: bpmUnit)))
            }
        } catch {
            return []
        }
    }

    // MARK: - Private

    private func processHRSamples(_ samples: [HKSample]?) {
        guard let hrSamples = samples as? [HKQuantitySample],
              let latest = hrSamples.last else { return }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = Int(latest.quantity.doubleValue(for: bpmUnit))

        DispatchQueue.main.async { [weak self] in
            self?.currentHeartRate = bpm
        }
    }
}
