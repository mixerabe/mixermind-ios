import SwiftUI

struct AudioWaveView: View {
    var isPlaying: Bool

    @State private var animate = false

    private let barCount = 5
    private let barWidth: CGFloat = 6
    private let barSpacing: CGFloat = 6
    private let maxBarHeight: CGFloat = 40
    private let minBarHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(.white)
                        .frame(width: barWidth, height: barHeight(for: index))
                        .animation(
                            isPlaying
                                ? .easeInOut(duration: durations[index % durations.count])
                                    .repeatForever(autoreverses: true)
                                : .easeInOut(duration: 0.3),
                            value: animate
                        )
                }
            }
        }
        .onChange(of: isPlaying) {
            animate = isPlaying
        }
        .onAppear {
            if isPlaying { animate = true }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if animate {
            return heights[index % heights.count]
        }
        return minBarHeight
    }

    private let heights: [CGFloat] = [32, 18, 40, 24, 36]
    private let durations: [Double] = [0.5, 0.7, 0.4, 0.6, 0.55]
}
