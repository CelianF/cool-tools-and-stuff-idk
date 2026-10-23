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
    /// Arguments sudo will run without a password: ["disablesleep"] or ["-a", "disablesleep"].
    @ObservationIgnored private var pmsetArgs: [String] = ["disablesleep"]
    var manual = false { didSet { update(announce: true) } }

    @ObservationIgnored private var capsLock = false
    @ObservationIgnored private var assertions: [IOPMAssertionID] = []
    @ObservationIgnored private var batteryTimer: Timer?
    @ObservationIgnored private var lidTimer: Timer?
    @ObservationIgnored private var lastDisplaySleep = Date.distantPast
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
            // Say so when the lid would still put the Mac to sleep, instead of failing silently.
            let lidCovered = !settings.caffeineLidClosed || UserDefaults.standard.bool(forKey: lidFlagKey)
            HUD.show(symbol: active ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                     title: active ? (lidCovered ? "Caffeinated" : "Caffeinated · lid will still sleep") : "Caffeine off")
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
        if lidTimer == nil {
            lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkLid() }
        }
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
        lidTimer?.invalidate()
        lidTimer = nil
    }

    private func releaseAssertions() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
    }

    private func setLidSleep(disabled: Bool) {
        let current = UserDefaults.standard.bool(forKey: lidFlagKey)
        guard disabled != current else { return }
        let status = Shell.run("/usr/bin/sudo", ["-n", Self.pmset] + pmsetArgs + [disabled ? "1" : "0"])
        UserDefaults.standard.set(disabled && status == 0, forKey: lidFlagKey)
    }

    /// With sleep disabled, closing the lid can leave the built-in panel lit against the keyboard.
    /// While the lid is shut, keep the display asleep (re-sleeping it if something wakes it).
    private func checkLid() {
        guard settings.caffeineLidDisplayOff, Self.isLidClosed, CGDisplayIsAsleep(CGMainDisplayID()) == 0,
              Date().timeIntervalSince(lastDisplaySleep) > 5 else { return }
        lastDisplaySleep = Date()
        DispatchQueue.global().async { Shell.run(Self.pmset, ["displaysleepnow"]) }
    }

    static var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool ?? false
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
        // `sudo -l <cmd>` succeeds for any admin, so look for an explicit NOPASSWD rule instead.
        let rules = Shell.output("/usr/bin/sudo", ["-n", "-l"]).split(separator: "\n").filter { $0.contains("NOPASSWD") }
        let form = [["disablesleep"], ["-a", "disablesleep"]].first { args in
            let command = ([Self.pmset] + args).joined(separator: " ")
            return rules.contains { $0.contains(command + " 1") }
        }
        lidRuleInstalled = form != nil
        if let form { pmsetArgs = form }
    }

    /// Asks for an admin password once and installs a sudoers rule that only allows toggling disablesleep.
    func installLidRule() {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: \(Self.pmset) disablesleep 0, \(Self.pmset) disablesleep 1"
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
