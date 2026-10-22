import Foundation
import Darwin

extension Notification.Name {
    static let zoneFlipDidChange = Notification.Name("ZoneFlipDidChange")
}

struct ZoneOption {
    let id: String
    let name: String
    let short: String
    let flag: String
    let helperArg: String
}

final class ZoneController {
    static let cn = ZoneOption(id: "Asia/Shanghai", name: "中国标准时间", short: "中国", flag: "🇨🇳", helperArg: "cn")
    static let usWest = ZoneOption(id: "America/Los_Angeles", name: "美国西部时间", short: "美西", flag: "🇺🇸", helperArg: "us-west")
    static let usEast = ZoneOption(id: "America/New_York", name: "美国东部时间", short: "美东", flag: "🇺🇸", helperArg: "us-east")
    static let usCentral = ZoneOption(id: "America/Chicago", name: "美国中部时间", short: "美中", flag: "🇺🇸", helperArg: "us-central")
    static let usMountain = ZoneOption(id: "America/Denver", name: "美国山地时间", short: "美山", flag: "🇺🇸", helperArg: "us-mountain")

    static let usOptions = [usWest, usEast, usCentral, usMountain]
    static let helperPath = "/usr/local/libexec/zoneflip-tz"
    static let sudoersPath = "/etc/sudoers.d/zoneflip"

    private let defaults = UserDefaults.standard
    private var helperCheckedAt: Date?
    private var helperReadyCache = false
    private(set) var lastExit: ExitInfo?

    // MARK: - Current state

    var currentZoneID: String {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: "/etc/localtime"),
           let range = destination.range(of: "zoneinfo/") {
            return String(destination[range.upperBound...])
        }
        return TimeZone.current.identifier
    }

    var isChina: Bool { currentZoneID == Self.cn.id }

    func option(forZoneID id: String) -> ZoneOption? {
        if id == Self.cn.id { return Self.cn }
        return Self.usOptions.first { $0.id == id }
    }

    var currentOption: ZoneOption? { option(forZoneID: currentZoneID) }

    var prettyName: String {
        currentOption?.name ?? currentZoneID
    }

    func abbreviation(forZoneID id: String) -> String {
        TimeZone(identifier: id)?.abbreviation(for: Date()) ?? ""
    }

    var lastUSOption: ZoneOption {
        let arg = defaults.string(forKey: "lastUS") ?? Self.usWest.helperArg
        return Self.usOptions.first { $0.helperArg == arg } ?? Self.usWest
    }

    var lastExitSummary: String? {
        defaults.string(forKey: "lastExitSummary")
    }

    static func option(forUSIP zoneID: String) -> ZoneOption {
        switch zoneID {
        case "America/New_York": return usEast
        case "America/Chicago": return usCentral
        case "America/Denver", "America/Phoenix": return usMountain
        default: return usWest
        }
    }

    // MARK: - Clock helpers

    func timeString(zoneID: String, date: Date = Date(), withDate: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: zoneID)
        formatter.dateFormat = withDate ? "M月d日 HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    func menuBarTitle() -> String {
        let zone = currentZoneID
        let flag = currentOption?.flag ?? "🌐"
        return "\(flag) \(timeString(zoneID: zone))"
    }

    // MARK: - Privileged helper

    var helperInstalledOnDisk: Bool {
        FileManager.default.fileExists(atPath: Self.helperPath)
    }

    /// True when `sudo -n` succeeds, which means the sudoers rule is in place
    /// and the app can switch without a password prompt.
    var helperReady: Bool {
        if let checkedAt = helperCheckedAt, Date().timeIntervalSince(checkedAt) < 3 {
            return helperReadyCache
        }
        let result = Shell.run("/usr/bin/sudo", ["-n", Self.helperPath, "status"])
        helperReadyCache = result.ok
        helperCheckedAt = Date()
        return helperReadyCache
    }

    func invalidateHelperCache() {
        helperCheckedAt = nil
    }

    static func adminCommand(for option: ZoneOption) -> String {
        let autoValue = option.helperArg == "cn" ? "true" : "false"
        return """
        /usr/sbin/systemsetup -settimezone '\(option.id)' >/dev/null && \
        /usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool \(autoValue)
        """
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func apply(_ option: ZoneOption, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.helperReady {
                let result = Shell.run("/usr/bin/sudo", ["-n", Self.helperPath, option.helperArg])
                if result.ok {
                    DispatchQueue.main.async {
                        self.didApply(option)
                        completion(true, "")
                    }
                    return
                }
            }

            // Fallback: one administrator prompt, works even before the helper is installed.
            let script = "do shell script \"\(Self.escapeAppleScript(Self.adminCommand(for: option)))\" with administrator privileges"
            let result = Shell.run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async {
                if result.ok {
                    self.didApply(option)
                    completion(true, "")
                } else {
                    completion(false, result.output)
                }
            }
        }
    }

    private func didApply(_ option: ZoneOption) {
        if option.helperArg != "cn" {
            defaults.set(option.helperArg, forKey: "lastUS")
        }
        NotificationCenter.default.post(name: .zoneFlipDidChange, object: nil)
    }

    // MARK: - Exit IP follow mode

    var autoFollow: Bool {
        get { defaults.bool(forKey: "autoFollow") }
        set { defaults.set(newValue, forKey: "autoFollow") }
    }

    func refreshExit(completion: ((ExitInfo?) -> Void)? = nil) {
        IPLocator.fetch { [weak self] info in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastExit = info
                if let info {
                    let place = info.city.isEmpty ? info.country : "\(info.city), \(info.country)"
                    self.defaults.set("\(info.ip) · \(place)", forKey: "lastExitSummary")
                }
                completion?(info)
            }
        }
    }

    func followTick() {
        guard autoFollow, helperReady else { return }
        refreshExit { [weak self] info in
            guard let self, let info else { return }
            var target: ZoneOption?
            if info.country == "CN" {
                target = Self.cn
            } else if info.country == "US" {
                target = Self.option(forUSIP: info.timezone)
            }
            guard let target, target.id != self.currentZoneID else { return }
            self.apply(target) { _, _ in }
        }
    }

    // MARK: - Helper install / uninstall

    func installHelper(completion: @escaping (Bool, String) -> Void) {
        guard let resources = Bundle.main.resourcePath else {
            completion(false, "找不到应用资源目录")
            return
        }
        let helperSource = resources + "/zoneflip-tz"
        let sudoersSource = resources + "/zoneflip.sudoers"
        guard FileManager.default.fileExists(atPath: helperSource),
              FileManager.default.fileExists(atPath: sudoersSource) else {
            completion(false, "应用包内缺少助手文件，请重新构建应用")
            return
        }

        let command = """
        /bin/mkdir -p /usr/local/libexec
        /usr/bin/install -o root -g wheel -m 0755 \(Self.shellQuote(helperSource)) /usr/local/libexec/zoneflip-tz
        /usr/bin/install -o root -g wheel -m 0440 \(Self.shellQuote(sudoersSource)) /etc/sudoers.d/zoneflip
        /usr/sbin/visudo -cf /etc/sudoers.d/zoneflip >/dev/null || { /bin/rm -f /etc/sudoers.d/zoneflip; /bin/echo "sudoers validation failed" >&2; exit 1; }
        """
        runAdmin(command) { [weak self] ok, output in
            self?.invalidateHelperCache()
            if ok, self?.helperReady == false {
                completion(false, "安装完成但免密校验未通过：\(output)")
            } else {
                completion(ok, output)
            }
        }
    }

    func uninstallHelper(completion: @escaping (Bool, String) -> Void) {
        let command = """
        /bin/rm -f /usr/local/libexec/zoneflip-tz
        /bin/rm -f /etc/sudoers.d/zoneflip
        /bin/echo removed
        """
        runAdmin(command) { [weak self] ok, output in
            self?.invalidateHelperCache()
            completion(ok, output)
        }
    }

    private func runAdmin(_ command: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = "do shell script \"\(Self.escapeAppleScript(command))\" with administrator privileges"
            let result = Shell.run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async {
                completion(result.ok, result.output)
            }
        }
    }

    // MARK: - Login item

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.jennie.zoneflip.plist"
    }

    var loginItemEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    @discardableResult
    func setLoginItem(_ enabled: Bool) -> Bool {
        if enabled {
            let directory = NSHomeDirectory() + "/Library/LaunchAgents"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.jennie.zoneflip</string>
                <key>ProgramArguments</key>
                <array><string>\(executable)</string></array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
                <key>LimitLoadToSessionType</key>
                <string>Aqua</string>
            </dict>
            </plist>
            """
            do {
                try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
            } catch {
                return false
            }
            let uid = getuid()
            let bootstrap = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", launchAgentPath])
            if !bootstrap.ok {
                _ = Shell.run("/bin/launchctl", ["load", "-w", launchAgentPath])
            }
        } else {
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            try? FileManager.default.removeItem(atPath: launchAgentPath)
        }
        return true
    }
}
