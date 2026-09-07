import Foundation

public struct PowerState: Sendable, Equatable {
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var screenLocked: Bool
    public var displayAsleep: Bool
    public var systemAsleep: Bool
    public var userPaused: Bool

    public init(onBattery: Bool = false, lowPowerMode: Bool = false, screenLocked: Bool = false,
                displayAsleep: Bool = false, systemAsleep: Bool = false, userPaused: Bool = false) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.screenLocked = screenLocked
        self.displayAsleep = displayAsleep
        self.systemAsleep = systemAsleep
        self.userPaused = userPaused
    }
}

public enum PollingMode: Sendable, Equatable {
    case normal
    case lowPower
    case suspended

    public var interval: TimeInterval? {
        switch self {
        case .normal: return 3
        case .lowPower: return 10
        case .suspended: return nil
        }
    }

    public var animationsEnabled: Bool {
        self == .normal
    }
}

public enum PowerPolicy {
    public static func mode(for state: PowerState) -> PollingMode {
        if state.userPaused || state.screenLocked || state.displayAsleep || state.systemAsleep {
            return .suspended
        }
        if state.onBattery || state.lowPowerMode {
            return .lowPower
        }
        return .normal
    }
}
