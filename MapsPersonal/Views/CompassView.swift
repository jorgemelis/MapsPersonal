import SwiftUI

// MARK: - Compass View

struct CompassView: View {
    let bearing: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // North arrow
            VStack(spacing: 0) {
                // North triangle (red)
                Triangle()
                    .fill(.red)
                    .frame(width: 8, height: 12)

                // South triangle (white)
                Triangle()
                    .fill(.white)
                    .rotationEffect(.degrees(180))
                    .frame(width: 8, height: 12)
            }
            .rotationEffect(.degrees(-bearing))

            // "N" label
            Text("N")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
                .offset(y: -14)
                .rotationEffect(.degrees(-bearing))
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
