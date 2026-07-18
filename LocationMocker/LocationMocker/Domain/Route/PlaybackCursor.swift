import Foundation

final class PlaybackCursor {
    private let samples: [RouteSample]
    private let mode: PlaybackMode
    private var index = 0
    private var direction = 1
    private var completed = false

    init(samples: [RouteSample], mode: PlaybackMode) {
        self.samples = samples
        self.mode = mode
    }

    func next() -> RouteSample? {
        guard !samples.isEmpty, !completed else { return nil }
        if samples.count == 1 {
            if mode == .once { completed = true }
            return samples[0]
        }
        let current = samples[index]
        advance()
        return current
    }

    func reset() {
        index = 0
        direction = 1
        completed = false
    }

    private func advance() {
        switch mode {
        case .once:
            if index >= samples.count - 1 {
                completed = true
            } else {
                index += 1
            }
        case .loop:
            index = index >= samples.count - 1 ? 0 : index + 1
        case .pingPong:
            let nextIndex = index + direction
            if nextIndex > samples.count - 1 {
                direction = -1
                index = samples.count - 2
            } else if nextIndex < 0 {
                direction = 1
                index = 1
            } else {
                index = nextIndex
            }
        }
    }
}
