import Foundation

public struct SchedulerState: Codable, Equatable, Sendable {
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var lastReview: Date?
    public var reps: Int
    public var lapses: Int

    public init(
        stability: Double,
        difficulty: Double,
        due: Date,
        lastReview: Date? = nil,
        reps: Int = 0,
        lapses: Int = 0
    ) {
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lastReview = lastReview
        self.reps = reps
        self.lapses = lapses
    }
}

public struct FSRS: Sendable {
    public static let decay: Double = -0.5
    public static let factor: Double = 19.0 / 81.0
    public static let minimumStability: Double = 0.1

    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105,
        7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395,
        0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]

    public var weights: [Double]
    public var desiredRetention: Double

    public init(weights: [Double] = FSRS.defaultWeights, desiredRetention: Double = 0.9) {
        precondition(weights.count >= 17, "FSRS weights are incomplete")
        self.weights = weights
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.99)
    }

    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * max(elapsedDays, 0) / stability, Self.decay)
    }

    public func initialState(grade: Grade, now: Date) -> SchedulerState {
        let stability = max(weights[grade.rawValue - 1], Self.minimumStability)
        let difficulty = initialDifficulty(grade: grade)
        return SchedulerState(
            stability: stability,
            difficulty: difficulty,
            due: now.addingTimeInterval(intervalDays(stability: stability) * 86_400),
            lastReview: now,
            reps: 1,
            lapses: grade == .again ? 1 : 0
        )
    }

    public func next(state: SchedulerState, grade: Grade, now: Date) -> SchedulerState {
        let lastReview = state.lastReview ?? now
        let elapsed = max(now.timeIntervalSince(lastReview) / 86_400, 0)
        let stability = max(state.stability, Self.minimumStability)
        let retrievability = retrievability(elapsedDays: elapsed, stability: stability)

        let nextDifficulty = nextDifficulty(state.difficulty, grade: grade)
        let nextStability: Double
        var lapses = state.lapses

        if grade == .again {
            nextStability = forgettingStability(
                difficulty: state.difficulty,
                stability: stability,
                retrievability: retrievability
            )
            lapses += 1
        } else {
            nextStability = recallingStability(
                difficulty: nextDifficulty,
                stability: stability,
                retrievability: retrievability,
                grade: grade
            )
        }

        let clamped = max(nextStability, Self.minimumStability)
        return SchedulerState(
            stability: clamped,
            difficulty: nextDifficulty,
            due: now.addingTimeInterval(intervalDays(stability: clamped) * 86_400),
            lastReview: now,
            reps: state.reps + 1,
            lapses: lapses
        )
    }

    public func intervalDays(stability: Double) -> Double {
        let raw = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(max(raw, 1), 365 * 10)
    }

    func initialDifficulty(grade: Grade) -> Double {
        let value = weights[4] - exp(weights[5] * Double(grade.rawValue - 1)) + 1
        return min(max(value, 1), 10)
    }

    func nextDifficulty(_ difficulty: Double, grade: Grade) -> Double {
        let delta = -weights[6] * Double(grade.rawValue - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        let reverted = weights[7] * initialDifficulty(grade: .easy) + (1 - weights[7]) * damped
        return min(max(reverted, 1), 10)
    }

    func recallingStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        grade: Grade
    ) -> Double {
        let hardPenalty = grade == .hard ? weights[15] : 1
        let easyBonus = grade == .easy ? weights[16] : 1
        let growth = exp(weights[8])
            * (11 - difficulty)
            * pow(stability, -weights[9])
            * (exp(weights[10] * (1 - retrievability)) - 1)
            * hardPenalty
            * easyBonus
        return stability * (1 + growth)
    }

    func forgettingStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let value = weights[11]
            * pow(difficulty, -weights[12])
            * (pow(stability + 1, weights[13]) - 1)
            * exp(weights[14] * (1 - retrievability))
        return min(value, stability)
    }
}
