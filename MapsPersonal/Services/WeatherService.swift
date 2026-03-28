import Foundation
import CoreLocation
import SwiftUI

// MARK: - Weather Data

struct WeatherData {
    var temperature: Double
    var uvIndex: Double
    var precipitationProbability: Int
    var humidity: Int
    var windSpeed: Double
    var weatherCode: Int
    var isDay: Bool
    var hourlyForecast: [HourlyForecastItem]
}

struct HourlyForecastItem: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let precipitationProbability: Int
    let weatherCode: Int
    let uvIndex: Double
    let windSpeed: Double
    let isDay: Bool
}

// MARK: - Weather Provider Protocol

protocol WeatherProvider {
    func fetchWeather(for location: CLLocationCoordinate2D) async throws -> WeatherData
}

// MARK: - Weather Service

@Observable
class WeatherService {
    var temperature: Double?
    var uvIndex: Double?
    var precipitationProbability: Int?
    var humidity: Int?
    var windSpeed: Double?
    var weatherCode: Int?
    var isDay: Bool = true
    var hourlyForecast: [HourlyForecastItem] = []
    var isLoading = false
    var lastUpdate: Date?
    var providerName: String { provider is OpenMeteoProvider ? "Open-Meteo" : "WeatherKit" }

    private var provider: WeatherProvider
    private var fetchTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    init(provider: WeatherProvider = OpenMeteoProvider()) {
        self.provider = provider
    }

    func switchProvider(_ newProvider: WeatherProvider) {
        provider = newProvider
    }

    /// Fetch current weather for a location
    func fetch(for location: CLLocationCoordinate2D) {
        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                let data = try await provider.fetchWeather(for: location)
                guard !Task.isCancelled else { return }

                temperature = data.temperature
                uvIndex = data.uvIndex
                humidity = data.humidity
                windSpeed = data.windSpeed
                weatherCode = data.weatherCode
                isDay = data.isDay
                precipitationProbability = data.precipitationProbability
                hourlyForecast = data.hourlyForecast

                lastUpdate = Date()
            } catch {
                if !Task.isCancelled {
                    print("WeatherService error: \(error)")
                }
            }
        }
    }

    /// Start auto-refreshing every 10 minutes
    func startAutoRefresh(locationProvider: @escaping () -> CLLocationCoordinate2D?) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                if let loc = locationProvider() {
                    fetch(for: loc)
                }
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func stop() {
        fetchTask?.cancel()
        autoRefreshTask?.cancel()
    }

    // MARK: - Display helpers

    var uvDescription: String {
        guard let uv = uvIndex else { return "--" }
        let level: String
        switch uv {
        case ..<3: level = "OK"
        case ..<6: level = "Crema solar"
        case ..<8: level = "Crema+sombrero"
        case ..<11: level = "Evitar sol"
        default: level = "No salir"
        }
        return String(format: "%.0f %@", uv, level)
    }

    var weatherSymbol: (name: String, color: Color) {
        guard let code = weatherCode else { return ("cloud", .gray) }
        return Self.symbolForCode(code, isDay: isDay)
    }

    static func symbolForCode(_ code: Int, isDay: Bool = true) -> (name: String, color: Color) {
        if !isDay {
            switch code {
            case 0: return ("moon.stars.fill", .indigo)
            case 1, 2: return ("cloud.moon.fill", .indigo)
            case 3: return ("cloud.fill", .gray)
            case 45, 48: return ("cloud.fog.fill", .gray)
            case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", .cyan)
            case 61, 63, 65, 66, 67: return ("cloud.rain.fill", .blue)
            case 71, 73, 75, 77: return ("cloud.snow.fill", .white)
            case 80, 81, 82: return ("cloud.heavyrain.fill", .blue)
            case 85, 86: return ("cloud.snow.fill", .white)
            case 95, 96, 99: return ("cloud.bolt.rain.fill", .yellow)
            default: return ("cloud.moon.fill", .indigo)
            }
        }
        switch code {
        case 0: return ("sun.max.fill", .yellow)
        case 1, 2: return ("cloud.sun.fill", .yellow)
        case 3: return ("cloud.fill", .gray)
        case 45, 48: return ("cloud.fog.fill", .gray)
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", .cyan)
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", .blue)
        case 71, 73, 75, 77: return ("cloud.snow.fill", .white)
        case 80, 81, 82: return ("cloud.heavyrain.fill", .blue)
        case 85, 86: return ("cloud.snow.fill", .white)
        case 95, 96, 99: return ("cloud.bolt.rain.fill", .yellow)
        default: return ("cloud.sun.fill", .yellow)
        }
    }
}

// MARK: - Open-Meteo Provider

struct OpenMeteoProvider: WeatherProvider {
    func fetchWeather(for location: CLLocationCoordinate2D) async throws -> WeatherData {
        let lat = location.latitude
        let lon = location.longitude
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,uv_index,is_day&hourly=temperature_2m,precipitation_probability,weather_code,uv_index,wind_speed_10m,is_day&forecast_hours=24&timezone=auto"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        // Parse hourly forecast
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dateFormatter.timeZone = TimeZone.current

        var hourly: [HourlyForecastItem] = []
        let count = min(
            response.hourly.time.count,
            response.hourly.temperature_2m.count,
            response.hourly.precipitation_probability.count
        )

        let now = Date()
        for i in 0..<count {
            guard let date = dateFormatter.date(from: response.hourly.time[i]) else { continue }
            // Only include future hours
            guard date > now else { continue }

            let isDay = i < response.hourly.is_day.count ? response.hourly.is_day[i] == 1 : true
            hourly.append(HourlyForecastItem(
                time: date,
                temperature: response.hourly.temperature_2m[i],
                precipitationProbability: response.hourly.precipitation_probability[i],
                weatherCode: Int(response.hourly.weather_code[i]),
                uvIndex: response.hourly.uv_index[i],
                windSpeed: response.hourly.wind_speed_10m[i],
                isDay: isDay
            ))
        }

        return WeatherData(
            temperature: response.current.temperature_2m,
            uvIndex: response.current.uv_index,
            precipitationProbability: response.hourly.precipitation_probability.first ?? 0,
            humidity: Int(response.current.relative_humidity_2m),
            windSpeed: response.current.wind_speed_10m,
            weatherCode: Int(response.current.weather_code),
            isDay: response.current.is_day == 1,
            hourlyForecast: hourly
        )
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeather

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let weather_code: Double
        let wind_speed_10m: Double
        let uv_index: Double
        let is_day: Int
    }

    struct HourlyWeather: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let precipitation_probability: [Int]
        let weather_code: [Double]
        let uv_index: [Double]
        let wind_speed_10m: [Double]
        let is_day: [Int]
    }
}

// MARK: - WeatherKit Provider (requires Apple Developer Program)
//
// To enable:
// 1. Add WeatherKit capability in Xcode (Signing & Capabilities)
// 2. Uncomment the code below
// 3. In ContentView, init weather with: WeatherService(provider: AppleWeatherProvider())
//
// import WeatherKit
//
// struct AppleWeatherProvider: WeatherProvider {
//     func fetchWeather(for location: CLLocationCoordinate2D) async throws -> WeatherData {
//         let ws = WeatherKit.WeatherService.shared
//         let loc = CLLocation(latitude: location.latitude, longitude: location.longitude)
//         let weather = try await ws.weather(for: loc)
//         let current = weather.currentWeather
//
//         let hourly = weather.hourlyForecast.prefix(24).map { hour in
//             HourlyForecastItem(
//                 time: hour.date,
//                 temperature: hour.temperature.value,
//                 precipitationProbability: Int(hour.precipitationChance * 100),
//                 weatherCode: mapConditionToCode(hour.condition),
//                 uvIndex: Double(hour.uvIndex.value),
//                 windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value
//             )
//         }
//
//         return WeatherData(
//             temperature: current.temperature.value,
//             uvIndex: Double(current.uvIndex.value),
//             precipitationProbability: Int((weather.hourlyForecast.first?.precipitationChance ?? 0) * 100),
//             humidity: Int(current.humidity * 100),
//             windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
//             weatherCode: mapConditionToCode(current.condition),
//             hourlyForecast: hourly
//         )
//     }
//
//     private func mapConditionToCode(_ condition: WeatherCondition) -> Int {
//         switch condition {
//         case .clear, .hot: return 0
//         case .mostlyClear, .partlyCloudy: return 1
//         case .mostlyCloudy, .cloudy: return 3
//         case .foggy: return 45
//         case .drizzle: return 51
//         case .rain, .heavyRain: return 63
//         case .snow, .heavySnow, .flurries: return 73
//         case .sleet, .freezingRain: return 66
//         case .thunderstorms, .strongStorms: return 95
//         case .haze, .smoky: return 48
//         case .blizzard: return 75
//         case .windy, .breezy: return 2
//         default: return 0
//         }
//     }
// }
