import Testing
@testable import ClaudeCatsCore

@Suite struct PowerPolicyTests {
    @Test func acPowerIsNormal() {
        #expect(PowerPolicy.mode(for: PowerState()) == .normal)
        #expect(PollingMode.normal.interval == 3)
        #expect(PollingMode.normal.animationsEnabled)
    }

    @Test func batteryOrLowPowerIsLowPower() {
        #expect(PowerPolicy.mode(for: PowerState(onBattery: true)) == .lowPower)
        #expect(PowerPolicy.mode(for: PowerState(lowPowerMode: true)) == .lowPower)
        #expect(PollingMode.lowPower.interval == 10)
        #expect(!PollingMode.lowPower.animationsEnabled)
    }

    @Test func lockSleepSaverPauseSuspend() {
        #expect(PowerPolicy.mode(for: PowerState(screenLocked: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(displayAsleep: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(systemAsleep: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(userPaused: true)) == .suspended)
        #expect(PollingMode.suspended.interval == nil)
        #expect(!PollingMode.suspended.animationsEnabled)
    }

    @Test func suspendBeatsLowPower() {
        #expect(PowerPolicy.mode(for: PowerState(onBattery: true, screenLocked: true)) == .suspended)
    }
}
