import SwiftUI

// MARK: - Weather Panel (toggled from bottom bar button)

struct WeatherBarView: View {
    let weather: WeatherService
    @State private var showUVTip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current conditions
            HStack(spacing: 14) {
                if let temp = weather.temperature {
                    HStack(spacing: 4) {
                        Image(systemName: weather.weatherSymbol.name)
                            .foregroundStyle(weather.weatherSymbol.color)
                        Text(String(format: "%.0f°", temp))
                    }
                    .font(.system(.body, design: .rounded).weight(.medium))
                }

                if let uv = weather.uvIndex {
                    Button {
                        showUVTip.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(uvColor(uv))
                                .font(.caption)
                            Text("UV")
                                .font(.system(.caption, design: .rounded))
                            Text("\(Int(uv.rounded()))")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showUVTip) {
                        Text(weather.uvDescription)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .padding(10)
                            .presentationCompactAdaptation(.popover)
                    }
                    .fixedSize()
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

                                Image(systemName: WeatherService.symbolForCode(hour.weatherCode, isDay: hour.isDay).name)
                                    .font(.body)
                                    .foregroundStyle(WeatherService.symbolForCode(hour.weatherCode, isDay: hour.isDay).color)

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

                                if hour.uvIndex >= 1 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "sun.max.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(uvColor(hour.uvIndex))
                                        Text("\(Int(hour.uvIndex.rounded()))")
                                            .font(.system(.caption2, design: .rounded).weight(.medium))
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
        uv < 3 ? .green : .red
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
