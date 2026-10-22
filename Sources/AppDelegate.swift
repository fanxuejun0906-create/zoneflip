import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var clockTimer: Timer?
    private var followTimer: Timer?
    private let controller = ZoneController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.toolTip = "ZoneFlip — 一键切换中国 / 美国时区"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        updateTitle()

        clockTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(clockTimer!, forMode: .common)

        NotificationCenter.default.addObserver(self, selector: #selector(zoneChanged), name: .zoneFlipDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        if controller.autoFollow {
            if controller.helperReady {
                startFollowTimer()
                controller.followTick()
            } else {
                controller.autoFollow = false
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clockTimer?.invalidate()
        followTimer?.invalidate()
    }

    // MARK: - Clock

    @objc private func tick() {
        updateTitle()
    }

    private func updateTitle() {
        statusItem.button?.title = controller.menuBarTitle()
    }

    @objc private func zoneChanged() {
        updateTitle()
    }

    @objc private func didWake() {
        if controller.autoFollow { controller.followTick() }
    }

    private func startFollowTimer() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(followTick), userInfo: nil, repeats: true)
        RunLoop.main.add(followTimer!, forMode: .common)
    }

    @objc private func followTick() {
        controller.followTick()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let current = controller.currentZoneID
        let helperReady = controller.helperReady

        addInfo(menu, "系统时区  \(controller.prettyName)  \(controller.abbreviation(forZoneID: current))")
        addInfo(menu, "北京时间  \(controller.timeString(zoneID: ZoneController.cn.id, date: now, withDate: true))")
        if current != ZoneController.cn.id {
            addInfo(menu, "洛杉矶    \(controller.timeString(zoneID: ZoneController.usWest.id, date: now, withDate: true))")
            addInfo(menu, "纽约      \(controller.timeString(zoneID: ZoneController.usEast.id, date: now, withDate: true))")
        }
        menu.addItem(.separator())

        let primaryTarget = controller.isChina ? controller.lastUSOption : ZoneController.cn
        let primaryTitle: String
        if controller.isChina {
            primaryTitle = "切换到 \(primaryTarget.name)（\(primaryTarget.short)）"
        } else if controller.currentOption != nil {
            primaryTitle = "回到中国时区（Asia/Shanghai）"
        } else {
            primaryTitle = "切换到 \(primaryTarget.name)（\(primaryTarget.short)）"
        }
        let primary = NSMenuItem(title: primaryTitle, action: #selector(primaryAction), keyEquivalent: "")
        primary.target = self
        primary.attributedTitle = NSAttributedString(
            string: primaryTitle,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        menu.addItem(primary)

        if controller.currentOption == nil {
            let back = NSMenuItem(title: "回到中国时区（Asia/Shanghai）", action: #selector(switchToChina), keyEquivalent: "")
            back.target = self
            menu.addItem(back)
        }

        let usMenu = NSMenu()
        for option in ZoneController.usOptions {
            let item = NSMenuItem(title: "\(option.name)  ·  \(option.id)", action: #selector(selectUSZone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.helperArg
            item.state = controller.lastUSOption.helperArg == option.helperArg ? .on : .off
            usMenu.addItem(item)
        }
        let usRoot = NSMenuItem(title: "选择美国时区", action: nil, keyEquivalent: "")
        usRoot.submenu = usMenu
        menu.addItem(usRoot)

        menu.addItem(.separator())

        let auto = NSMenuItem(title: "跟随出口 IP 自动切换", action: #selector(toggleAutoFollow), keyEquivalent: "")
        auto.target = self
        auto.state = controller.autoFollow ? .on : .off
        menu.addItem(auto)

        let exit = controller.lastExitSummary ?? "尚未检测"
        addInfo(menu, "出口  \(exit)")
        let check = NSMenuItem(title: "立即检测出口 IP", action: #selector(checkNow), keyEquivalent: "")
        check.target = self
        menu.addItem(check)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = controller.loginItemEnabled ? .on : .off
        menu.addItem(login)

        if helperReady {
            addInfo(menu, "免密助手  已就绪")
            let remove = NSMenuItem(title: "卸载免密助手…", action: #selector(uninstallHelperAction), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        } else if controller.helperInstalledOnDisk {
            addInfo(menu, "免密助手  已安装但未生效")
            let repair = NSMenuItem(title: "修复免密助手…", action: #selector(installHelperAction), keyEquivalent: "")
            repair.target = self
            menu.addItem(repair)
        } else {
            let install = NSMenuItem(title: "安装免密助手（只需输一次密码）…", action: #selector(installHelperAction), keyEquivalent: "")
            install.target = self
            menu.addItem(install)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "打开“日期与时间”设置…", action: #selector(openDateTimeSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "退出 ZoneFlip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @discardableResult
    private func addInfo(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func primaryAction() {
        let target = controller.isChina ? controller.lastUSOption : ZoneController.cn
        switchZone(to: target)
    }

    @objc private func switchToChina() {
        switchZone(to: ZoneController.cn)
    }

    @objc private func selectUSZone(_ sender: NSMenuItem) {
        guard
            let arg = sender.representedObject as? String,
            let option = ZoneController.usOptions.first(where: { $0.helperArg == arg })
        else { return }
        switchZone(to: option)
    }

    private func switchZone(to option: ZoneOption) {
        controller.apply(option) { [weak self] ok, message in
            guard let self else { return }
            self.updateTitle()
            if !ok {
                self.showAlert("切换失败", message.isEmpty ? "无法修改系统时区，请检查管理员权限。" : message)
            }
        }
    }

    @objc private func toggleAutoFollow() {
        if controller.autoFollow {
            controller.autoFollow = false
            followTimer?.invalidate()
            followTimer = nil
            return
        }

        if controller.helperReady {
            controller.autoFollow = true
            startFollowTimer()
            controller.followTick()
            return
        }

        let alert = NSAlert()
        alert.messageText = "自动跟随需要免密助手"
        alert.informativeText = "没有助手时，每次自动切换都会弹出管理员密码框。现在安装一次（需要输一次密码），之后切换就完全无感。"
        alert.addButton(withTitle: "安装并开启")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        controller.installHelper { [weak self] ok, message in
            guard let self else { return }
            if ok {
                self.controller.autoFollow = true
                self.startFollowTimer()
                self.controller.followTick()
            } else {
                self.showAlert("安装失败", message)
            }
        }
    }

    @objc private func checkNow() {
        if !controller.helperReady && controller.autoFollow {
            controller.autoFollow = false
            followTimer?.invalidate()
        }
        controller.refreshExit { info in
            if info == nil {
                self.showAlert("检测失败", "无法访问 ipinfo.io，请检查网络后重试。")
            }
        }
    }

    @objc private func toggleLoginItem() {
        let enable = !controller.loginItemEnabled
        if !controller.setLoginItem(enable) {
            showAlert("设置失败", "无法写入登录项，请检查 ~/Library/LaunchAgents 权限。")
        }
    }

    @objc private func installHelperAction() {
        controller.installHelper { [weak self] ok, message in
            guard let self else { return }
            if ok {
                self.showAlert("免密助手已安装", "之后切换时区不再需要输入密码。")
            } else {
                self.showAlert("安装失败", message.isEmpty ? "管理员授权被取消或安装出错。" : message)
            }
        }
    }

    @objc private func uninstallHelperAction() {
        let alert = NSAlert()
        alert.messageText = "卸载免密助手？"
        alert.informativeText = "会删除 /usr/local/libexec/zoneflip-tz 和 /etc/sudoers.d/zoneflip。之后切换时区会重新弹出密码框，功能本身不受影响。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        controller.uninstallHelper { [weak self] ok, message in
            guard let self else { return }
            if ok {
                self.controller.autoFollow = false
                self.followTimer?.invalidate()
                self.showAlert("已卸载", "免密助手已移除。")
            } else {
                self.showAlert("卸载失败", message)
            }
        }
    }

    @objc private func openDateTimeSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.datetime"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
