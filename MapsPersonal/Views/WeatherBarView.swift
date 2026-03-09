import SwiftUI

// MARK: - Weather Panel (toggled from bottom bar button)

struct WeatherBarView: View {
    let weather: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current conditions
            HStack(spacing: 14) {
                if let temp = weather.temperature {
                    Text("\(weather.weatherEmoji) \(String(format: "%.0f°", temp))")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }

                if let uv = weather.uvIndex {
                    HStack(spacing: 3) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(uvColor(uv))
                            .font(.caption)
                        Text(String(format: "UV %.0f", uv))
                            .font(.system(.caption, design: .rounded))
                    }
                }

                if let precip = weather.precipitationProbability, precip > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("\(precip)%")
                            .font(.system(.caption, design: .rounded))
                    }
                }

                if let humidity = weather.humidity {
                    HStack(spacing: 3) {
                        Image(systemName: "humidity.fill")
                            .font(.caption)
                        Text("\(humidity)%")
                            .font(.system(.caption, design: .rounded))
                    }
                }

                if let wind = weather.windSpeed, wind > 5 {
                    HStack(spacing: 3) {
                        Image(systemName: "wind")
                            .font(.caption)
                        Text(String(format: "%.0f km/h", wind))
                            .font(.system(.caption, design: .rounded))
                    }
                }
            }

            // Hourly forecast
            if !weather.hourlyForecast.isEmpty {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(weather.hourlyForecast) { hour in
                            VStack(spacing: 5) {
                                Text(hourLabel(hour.time))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Text(WeatherService.emojiForCode(hour.weatherCode))
                                    .font(.body)

                                Text(String(format: "%.0f°", hour.temperature))
                                    .font(.system(.caption, design: .rounded).weight(.semibold))

                                if hour.precipitationProbability > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "drop.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.blue)
                                        Text("\(hour.precipitationProbability)%")
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(.blue)
                                    }
                                } else {
                                    Text(" ")
                                        .font(.caption2)
                                }

                                if hour.uvIndex >= 3 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "sun.max.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(uvColor(hour.uvIndex))
                                        Text(String(format: "%.0f", hour.uvIndex))
                                            .font(.system(.caption2, design: .rounded))
                                    }
                                } else {
                                    Text(" ")
                                        .font(.caption2)
                                }
                            }
                            .frame(width: 46)
                        }
                    }
                }
            }

            // Source + last update
            if let lastUpdate = weather.lastUpdate {
                Text("\(weather.providerName) · \(timeAgo(lastUpdate))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func uvColor(_ uv: Double) -> Color {
        switch uv {
        case ..<3: return .green
        case ..<6: return .yellow
        case ..<8: return .orange
        case ..<11: return .red
        default: return .purple
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: date) + "h"
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "ahora" }
        if seconds < 3600 { return "hace \(seconds / 60) min" }
        return "hace \(seconds / 3600)h"
    }
}
