import SwiftUI

// MARK: - Weather Panel (toggled from bottom bar button)

struct WeatherBarView: View {
    let weather: WeatherService
    @State private var showUVTip = false
    @State private var selectedHour: HourlyForecastItem?

    private var isShowingCurrent: Bool { selectedHour == nil }

    // Active display values (current or selected hour)
    private var displayTemp: Double? {
        selectedHour?.temperature ?? weather.temperature
    }
    private var displayUV: Double? {
        selectedHour?.uvIndex ?? weather.uvIndex
    }
    private var displayPrecip: Int? {
        if let hour = selectedHour { return hour.precipitationProbability }
        return weather.precipitationProbability
    }
    private var displayHumidity: Int? {
        if selectedHour != nil { return nil }  // hourly doesn't have humidity
        return weather.humidity
    }
    private var displayWind: Double? {
        selectedHour?.windSpeed ?? weather.windSpeed
    }
    private var displaySymbol: (name: String, color: Color) {
        if let hour = selectedHour {
            return WeatherService.symbolForCode(hour.weatherCode, isDay: hour.isDay)
        }
        return weather.weatherSymbol
    }
    private var displayLabel: String {
        if let hour = selectedHour {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: hour.time)
        }
        return "Ahora"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Detail header (current or selected hour)
            HStack(spacing: 14) {
                // Time label
                Text(displayLabel)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(isShowingCurrent ? Color.primary : Color.blue)

                if let temp = displayTemp {
                    HStack(spacing: 4) {
                        Image(systemName: displaySymbol.name)
                            .foregroundStyle(displaySymbol.color)
                        Text(String(format: "%.0f°", temp))
                    }
                    .font(.system(.body, design: .rounded).weight(.medium))
                }

                if let uv = displayUV {
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

                if let precip = displayPrecip, precip > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("\(precip)%")
                            .font(.system(.caption, design: .rounded))
                    }
                }

                if let humidity = displayHumidity {
                    HStack(spacing: 3) {
                        Image(systemName: "humidity.fill")
                            .font(.caption)
                        Text("\(humidity)%")
                            .font(.system(.caption, design: .rounded))
                    }
                }

                if let wind = displayWind, wind > 5 {
                    HStack(spacing: 3) {
                        Image(systemName: "wind")
                            .font(.caption)
                        Text(String(format: "%.0f", wind))
                            .font(.system(.caption, design: .rounded))
                    }
                }
            }

            // Hourly forecast scroll
            if !weather.hourlyForecast.isEmpty {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // "Now" pill
                        hourCell(
                            label: "Ahora",
                            symbol: weather.weatherSymbol,
                            temp: weather.temperature ?? 0,
                            precip: weather.precipitationProbability ?? 0,
                            uv: weather.uvIndex ?? 0,
                            isSelected: isShowingCurrent
                        )
                        .onTapGesture { selectedHour = nil }

                        // Hourly pills
                        ForEach(weather.hourlyForecast) { hour in
                            hourCell(
                                label: hourLabel(hour.time),
                                symbol: WeatherService.symbolForCode(hour.weatherCode, isDay: hour.isDay),
                                temp: hour.temperature,
                                precip: hour.precipitationProbability,
                                uv: hour.uvIndex,
                                isSelected: selectedHour?.id == hour.id
                            )
                            .onTapGesture { selectedHour = hour }
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

    // MARK: - Hour Cell

    private func hourCell(label: String, symbol: (name: String, color: Color), temp: Double, precip: Int, uv: Double, isSelected: Bool) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(isSelected ? .blue : .secondary)

            Image(systemName: symbol.name)
                .font(.body)
                .foregroundStyle(symbol.color)

            Text(String(format: "%.0f°", temp))
                .font(.system(.caption, design: .rounded).weight(.semibold))

            if precip > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                    Text("\(precip)%")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.blue)
                }
            } else {
                Text(" ")
                    .font(.caption2)
            }

            if uv >= 1 {
                HStack(spacing: 2) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(uvColor(uv))
                    Text("\(Int(uv.rounded()))")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                }
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(width: 46)
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
