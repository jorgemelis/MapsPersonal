import Foundation
import HealthKit

// MARK: - Heart Rate Service

@Observable
class HeartRateService {
    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var workoutBuilder: HKWorkoutBuilder?
    private var workoutStartDate: Date?

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

        // Start a workout builder to trigger continuous HR from Apple Watch
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
        Task {
            do {
                try await builder.beginCollection(at: Date())
                workoutBuilder = builder
                workoutStartDate = Date()
                print("HeartRateService: workout session started for continuous HR")
            } catch {
                print("HeartRateService: failed to start workout: \(error)")
            }
        }

        // Listen for HR samples
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

    /// Finish the active workout and save it to HealthKit
    func saveWorkout(
        start: Date,
        end: Date,
        distance: Double,
        elevationGain: Double
    ) async -> Bool {
        guard isAvailable else { return false }

        // Use the active builder if available, otherwise create a new one
        let builder: HKWorkoutBuilder
        if let active = workoutBuilder {
            builder = active
        } else {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .hiking
            configuration.locationType = .outdoor
            builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
            do {
                try await builder.beginCollection(at: start)
            } catch {
                print("HeartRateService: Failed to begin collection: \(error)")
                return false
            }
        }

        do {
            // Add distance sample
            if distance > 0 {
                let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                    start: start,
                    end: end
                )
                try await builder.addSamples([distanceSample])
            }

            // Add elevation gain as flights climbed
            if elevationGain > 0 {
                let elevationType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
                let flights = elevationGain / 3.0
                let elevationSample = HKQuantitySample(
                    type: elevationType,
                    quantity: HKQuantity(unit: .count(), doubleValue: flights),
                    start: start,
                    end: end
                )
                try await builder.addSamples([elevationSample])
            }

            try await builder.endCollection(at: end)
            try await builder.finishWorkout()

            workoutBuilder = nil
            workoutStartDate = nil

            print("HeartRateService: Workout saved to Health (\(String(format: "%.1f", distance))m, \(String(format: "%.0f", elevationGain))m gain)")
            return true
        } catch {
            print("HeartRateService: Failed to save workout: \(error)")
            try? await builder.endCollection(at: end)
            workoutBuilder = nil
            workoutStartDate = nil
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
