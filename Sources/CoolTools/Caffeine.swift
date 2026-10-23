import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake while Caps Lock is on (or when toggled manually).
/// Idle sleep is blocked with a power assertion; lid-closed sleep needs `pmset disablesleep`,
/// which runs through a narrow sudoers rule the user installs once from Settings.
@Observable
final class Caffeine {
    static let shared = Caffeine()

    private(set) var isActive = false
    private(set) var lidRuleInstalled = false
    var manual = false { didSet { update(announce: true) } }

    @ObservationIgnored private var capsLock = false
    @ObservationIgnored private var assertions: [IOPMAssertionID] = []
    @ObservationIgnored private var batteryTimer: Timer?
    /// Set when low battery switched caffeine off; cleared when the triggers are released.
    @ObservationIgnored private var batteryCutoff = false
    @ObservationIgnored private let lidFlagKey = "lidSleepDisabled"

    private static let pmset = "/usr/bin/pmset"
    private static let ruleFile = "/etc/sudoers.d/cool-tools"

    private var settings: AppSettings { .shared }

    private init() {
        // Undo a lid-sleep override left behind by a crash.
        if UserDefaults.standard.bool(forKey: lidFlagKey) { setLidSleep(disabled: false) }
        refreshLidRule()
    }

    func capsLockChanged(_ on: Bool, announce: Bool) {
        capsLock = on
        update(announce: announce)
    }

    func toggleManual() { manual.toggle() }

    func update(announce: Bool = false) {
        let wanted = manual || (settings.capsLockCaffeine && capsLock)
        if !wanted { batteryCutoff = false }
        let active = wanted && !batteryCutoff
        if active { activate() } else { deactivate() }
        if announce, active != isActive {
            HUD.show(symbol: active ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                     title: active ? "Caffeinated" : "Caffeine off")
        }
        isActive = active
    }

    func shutdown() { deactivate() }

    private func activate() {
        releaseAssertions()
        var types = [kIOPMAssertPreventUserIdleSystemSleep]
        if settings.caffeineKeepsDisplayOn { types.append(kIOPMAssertPreventUserIdleDisplaySleep) }
        for type in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Cool Tools caffeine" as CFString, &id) == kIOReturnSuccess {
                assertions.append(id)
            }
        }
        setLidSleep(disabled: settings.caffeineLidClosed && lidRuleInstalled)
        if batteryTimer == nil {
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkBattery() }
        }
        checkBattery()
    }

    private func deactivate() {
        releaseAssertions()
        if UserDefaults.standard.bool(forKey: lidFlagKey) { setLidSleep(disabled: false) }
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func releaseAssertions() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
    }

    private func setLidSleep(disabled: Bool) {
        let current = UserDefaults.standard.bool(forKey: lidFlagKey)
        guard disabled != current else { return }
        let status = Shell.run("/usr/bin/sudo", ["-n", Self.pmset, "-a", "disablesleep", disabled ? "1" : "0"])
        UserDefaults.standard.set(disabled && status == 0, forKey: lidFlagKey)
    }

    private func checkBattery() {
        guard isActive || manual || capsLock else { return }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let level = d[kIOPSCurrentCapacityKey] as? Int, level <= settings.caffeineBatteryFloor else { continue }
            batteryCutoff = true
            deactivate()
            isActive = false
            HUD.show(symbol: "battery.25", title: "Low battery – caffeine off")
        }
    }

    // MARK: Lid-closed setup

    func refreshLidRule() {
        lidRuleInstalled = Shell.run("/usr/bin/sudo", ["-n", "-l", Self.pmset, "-a", "disablesleep", "1"]) == 0
    }

    /// Asks for an admin password once and installs a sudoers rule that only allows toggling disablesleep.
    func installLidRule() {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: \(Self.pmset) -a disablesleep 0, \(Self.pmset) -a disablesleep 1"
        let shell = """
        tmp=$(mktemp) && printf '%s\\n' '\(rule)' > "$tmp" && /usr/sbin/visudo -cf "$tmp" && \
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(Self.ruleFile); rm -f "$tmp"
        """
        runAsAdmin(shell)
    }

    func removeLidRule() {
        deactivate()
        runAsAdmin("/bin/rm -f \(Self.ruleFile)")
        update()
    }

    private func runAsAdmin(_ shell: String) {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global().async {
            NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(nil)
            DispatchQueue.main.async {
                self.refreshLidRule()
                self.update()
            }
        }
    }
}
