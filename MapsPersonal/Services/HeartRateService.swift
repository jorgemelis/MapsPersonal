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
        let workoutType = HKObjectType.workoutType()
        let elevationType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
        do {
            try await healthStore.requestAuthorization(
                toShare: [workoutType],
                read: [hrType, workoutType, elevationType]
            )
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

    // MARK: - Save Workout to Health

    /// Save a hiking workout to HealthKit after track recording
    func saveWorkout(
        start: Date,
        end: Date,
        distance: Double,
        elevationGain: Double
    ) async -> Bool {
        guard isAvailable else { return false }

        let workout = HKWorkout(
            activityType: .hiking,
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
            metadata: [
                HKMetadataKeyIndoorWorkout: false,
                "MapsPersonalTrack": true
            ]
        )

        do {
            try await healthStore.save(workout)

            // Add elevation gain as a sample associated with the workout
            if elevationGain > 0 {
                let elevationType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
                // Convert meters to flights (1 flight ≈ 3m)
                let flights = elevationGain / 3.0
                let elevationSample = HKQuantitySample(
                    type: elevationType,
                    quantity: HKQuantity(unit: .count(), doubleValue: flights),
                    start: start,
                    end: end
                )
                try await healthStore.addSamples([elevationSample], to: workout)
            }

            print("HeartRateService: Workout saved to Health (\(String(format: "%.1f", distance))m, \(String(format: "%.0f", elevationGain))m gain)")
            return true
        } catch {
            print("HeartRateService: Failed to save workout: \(error)")
            return false
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
