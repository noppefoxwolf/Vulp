import Foundation

/// A display frequency supported by automatic sequence playback planning.
public enum ImageSequenceFrameRate: Int, CaseIterable, Sendable {
    case fps60 = 60
    case fps30 = 30
    case fps20 = 20
    case fps15 = 15
    case fps12 = 12
    case fps10 = 10
    case fps6 = 6
    case fps5 = 5
    case fps4 = 4
    case fps3 = 3
    case fps2 = 2
    case fps1 = 1

    /// Minimum time between displayed frames at this update frequency.
    public var frameDuration: TimeInterval {
        1 / Double(rawValue)
    }
}

/// A source-frame schedule matched to a supported display frequency.
public struct ImageSequencePlaybackPlan: Sendable {
    public let frameRate: ImageSequenceFrameRate
    public let frameIndices: [Int]
    public let isAnimated: Bool

    public init(frameDurations: [TimeInterval], levelOfIntegrity: Double) {
        func positions(_ elapsedDurations: [TimeInterval], at frameRate: ImageSequenceFrameRate) -> [Int] {
            elapsedDurations.map { Int(($0 + 1e-9) * Double(frameRate.rawValue)) }
        }

        func frameLossCount(
            elapsedDurations: [TimeInterval],
            frameRate: ImageSequenceFrameRate
        ) -> Double {
            let displayPositions = positions(elapsedDurations, at: frameRate)
            guard !displayPositions.isEmpty else { return 0 }
            var lostFrames = 0
            for index in displayPositions.indices.dropFirst() where displayPositions[index] == displayPositions[index - 1] {
                lostFrames += 1
            }
            if displayPositions[0] == 0 { lostFrames += 1 }
            return Double(lostFrames)
        }

        func frameIndices(
            elapsedDurations: [TimeInterval],
            frameRate: ImageSequenceFrameRate
        ) -> [Int] {
            let displayPositions = positions(elapsedDurations, at: frameRate)
            guard let lastPosition = displayPositions.last else { return [] }
            var result: [Int] = []
            var sourceIndex = 0
            var displayIndex = 1
            while displayIndex <= lastPosition, sourceIndex < displayPositions.count {
                if displayIndex <= displayPositions[sourceIndex] {
                    result.append(sourceIndex)
                    displayIndex += 1
                } else {
                    sourceIndex += 1
                }
            }
            return result
        }

        let durations = frameDurations.map { duration in
            duration.isFinite && duration > 0 ? duration : 0.1
        }
        let integrity = min(max(levelOfIntegrity.isFinite ? levelOfIntegrity : 1, 0), 1)
        var elapsedDurations = durations
        for index in elapsedDurations.indices.dropFirst() {
            elapsedDurations[index] += elapsedDurations[index - 1]
        }

        let chosenRate = ImageSequenceFrameRate.allCases.reversed().first { rate in
            frameLossCount(
                elapsedDurations: elapsedDurations,
                frameRate: rate
            ) <= Double(durations.count) * (1 - integrity)
        } ?? .fps1
        self.frameRate = chosenRate
        self.frameIndices = frameIndices(
            elapsedDurations: elapsedDurations,
            frameRate: chosenRate
        )
        self.isAnimated = Set(self.frameIndices).count > 1
    }
}

