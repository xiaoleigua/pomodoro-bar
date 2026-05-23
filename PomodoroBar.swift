import AppKit
import UserNotifications

// ── Model ─────────────────────────────────────────────────
class PomodoroModel {
    enum Mode: String { case focus, short, long }

    var mode: Mode = .focus {
        didSet { resetForCurrentMode(); onUpdate?() }
    }
    var remaining: Int = 25 * 60
    var total: Int = 25 * 60
    var isRunning = false
    var todayCount: Int { _todayCount }
    var sessionLabel: String { isRunning ? modeLabel : "暂停中" }

    var onUpdate: (() -> Void)?
    var onComplete: ((Mode) -> Void)?

    private var timer: Timer?
    private var _todayCount = 0
    private let defaults = UserDefaults.standard

    var modeLabel: String {
        switch mode {
        case .focus: return "专注中"
        case .short: return "短休中"
        case .long:  return "长休中"
        }
    }

    var modeMinutes: Int {
        switch mode {
        case .focus: return 25
        case .short: return 5
        case .long:  return 15
        }
    }

    var nextMode: Mode {
        switch mode {
        case .focus: return .short
        case .short, .long: return .focus
        }
    }

    init() { loadCount(); resetForCurrentMode() }

    func resetForCurrentMode() {
        timer?.invalidate(); timer = nil
        isRunning = false
        remaining = modeMinutes * 60
        total = remaining
    }

    func toggle() {
        if isRunning { pause() } else { start() }
    }

    func start() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        onUpdate?()
    }

    func pause() {
        timer?.invalidate(); timer = nil
        isRunning = false
        onUpdate?()
    }

    func reset() { resetForCurrentMode(); onUpdate?() }

    func switchTo(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
    }

    private func tick() {
        guard remaining > 0 else {
            complete()
            return
        }
        remaining -= 1
        onUpdate?()
    }

    private func complete() {
        timer?.invalidate(); timer = nil
        isRunning = false

        let completedMode = mode
        if completedMode == .focus {
            _todayCount += 1
            saveCount()
        }

        onComplete?(completedMode)
        mode = nextMode
    }

    // Persist today's count
    private func loadCount() {
        let today = Calendar.current.startOfDay(for: Date())
        let savedDate = defaults.object(forKey: "pomodoro_date") as? Date
        if let sd = savedDate, Calendar.current.isDate(sd, inSameDayAs: today) {
            _todayCount = defaults.integer(forKey: "pomodoro_count")
        } else {
            _todayCount = 0
        }
    }

    private func saveCount() {
        defaults.set(_todayCount, forKey: "pomodoro_count")
        defaults.set(Date(), forKey: "pomodoro_date")
    }
}

// ── Ring View ────────────────────────────────────────────
class RingView: NSView {
    var progress: CGFloat = 0 {
        didSet { updateRing() }
    }

    private let bgLayer = CAShapeLayer()
    private let fgLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        let r: CGFloat = 100
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: r, startAngle: -.pi/2, endAngle: .pi*1.5, clockwise: false)

        bgLayer.path = path
        bgLayer.fillColor = nil
        bgLayer.strokeColor = NSColor(white: 0.85, alpha: 1).cgColor
        bgLayer.lineWidth = 8
        bgLayer.lineCap = .round
        layer?.addSublayer(bgLayer)

        fgLayer.path = path
        fgLayer.fillColor = nil
        fgLayer.strokeColor = NSColor(red: 0.91, green: 0.27, blue: 0.38, alpha: 1).cgColor
        fgLayer.lineWidth = 8
        fgLayer.lineCap = .round
        fgLayer.strokeStart = 0
        fgLayer.strokeEnd = 0
        layer?.addSublayer(fgLayer)
    }

    override func layout() {
        super.layout()
        bgLayer.frame = bounds
        fgLayer.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: 100, startAngle: -.pi/2, endAngle: .pi*1.5, clockwise: false)
        bgLayer.path = path
        fgLayer.path = path
    }

    private func updateRing() { fgLayer.strokeEnd = progress }
}

// ── Popover Content ViewController ───────────────────────
class PomodoroViewController: NSViewController {
    let model: PomodoroModel
    var onTogglePopover: (() -> Void)?

    private var ringView: RingView!
    private var timeLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var startBtn: NSButton!
    private var resetBtn: NSButton!
    private var countLabel: NSTextField!
    private var tabViews: [NSView] = []
    private var tabLabels: [NSTextField] = []

    init(model: PomodoroModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 390))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1).cgColor
        buildUI()
        refreshUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        model.onUpdate = { [weak self] in self?.refreshUI() }
        model.onComplete = { [weak self] mode in
            self?.refreshUI()
            self?.sendNotification(for: mode)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        model.onUpdate = { [weak self] in self?.refreshUI() }
    }

    private func buildUI() {
        let title = NSTextField(labelWithString: "番茄钟")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = NSColor(red: 0.91, green: 0.27, blue: 0.38, alpha: 1)

        // Mode tabs container
        let tabBg = NSView()
        tabBg.wantsLayer = true
        tabBg.layer?.backgroundColor = NSColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1).cgColor
        tabBg.layer?.cornerRadius = 10

        let modes: [(PomodoroModel.Mode, String)] = [(.focus, "专注 25"), (.short, "短休 5"), (.long, "长休 15")]
        for (mode, title) in modes {
            let tabView = NSView()
            tabView.wantsLayer = true
            tabView.layer?.cornerRadius = 8
            tabView.identifier = NSUserInterfaceItemIdentifier(mode.rawValue)

            let lbl = NSTextField(labelWithString: title)
            lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            lbl.alignment = .center
            tabView.addSubview(lbl)
            tabLabels.append(lbl)

            let gesture = NSClickGestureRecognizer(target: self, action: #selector(tabClicked(_:)))
            tabView.addGestureRecognizer(gesture)

            tabViews.append(tabView)
        }

        // Ring
        ringView = RingView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        ringView.translatesAutoresizingMaskIntoConstraints = false

        // Time label (overlaid on ring)
        timeLabel = NSTextField(labelWithString: "25:00")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        timeLabel.textColor = NSColor(white: 0.15, alpha: 1)
        timeLabel.alignment = .center

        statusLabel = NSTextField(labelWithString: "准备开始")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(white: 0.45, alpha: 1)
        statusLabel.alignment = .center

        // Buttons
        startBtn = NSButton(title: "开始", target: self, action: #selector(startClicked))
        startBtn.bezelStyle = .rounded
        startBtn.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        startBtn.contentTintColor = NSColor(red: 0.91, green: 0.27, blue: 0.38, alpha: 1)

        resetBtn = NSButton(title: "重置", target: self, action: #selector(resetClicked))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        resetBtn.isBordered = true
        resetBtn.contentTintColor = NSColor(white: 0.40, alpha: 1)

        // Count
        countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.textColor = NSColor(white: 0.50, alpha: 1)
        countLabel.alignment = .center

        // Add subviews
        view.addSubview(title)
        view.addSubview(tabBg)
        tabViews.forEach { tabBg.addSubview($0) }
        view.addSubview(ringView)
        view.addSubview(timeLabel)
        view.addSubview(statusLabel)
        view.addSubview(startBtn)
        view.addSubview(resetBtn)
        view.addSubview(countLabel)

        // Layout - manual frames for simplicity & compatibility
        title.frame = NSRect(x: 20, y: 350, width: 260, height: 24)

        tabBg.frame = NSRect(x: 20, y: 312, width: 260, height: 32)
        let tabW: CGFloat = 260 / 3
        for (i, tab) in tabViews.enumerated() {
            tab.frame = NSRect(x: CGFloat(i) * tabW + 2, y: 2, width: tabW - 4, height: 28)
            tabLabels[i].frame = tab.bounds
        }

        ringView.frame = NSRect(x: 40, y: 82, width: 220, height: 220)
        timeLabel.frame = NSRect(x: 40, y: 168, width: 220, height: 48)
        statusLabel.frame = NSRect(x: 40, y: 148, width: 220, height: 18)

        startBtn.frame = NSRect(x: 60, y: 50, width: 100, height: 30)
        resetBtn.frame = NSRect(x: 180, y: 50, width: 80, height: 30)
        countLabel.frame = NSRect(x: 20, y: 18, width: 260, height: 18)
    }

    private func refreshUI() {
        timeLabel.stringValue = format(model.remaining)
        statusLabel.stringValue = model.sessionLabel
        ringView.progress = model.total > 0 ? CGFloat(model.remaining) / CGFloat(model.total) : 1

        startBtn.title = model.isRunning ? "暂停" : "开始"
        countLabel.stringValue = "今日完成 \(model.todayCount) 个番茄"

        for (i, tab) in tabViews.enumerated() {
            let isActive = tab.identifier?.rawValue == model.mode.rawValue
            if isActive {
                tab.layer?.backgroundColor = NSColor(red: 0.91, green: 0.27, blue: 0.38, alpha: 1).cgColor
                tabLabels[i].textColor = .white
            } else {
                tab.layer?.backgroundColor = nil
                tabLabels[i].textColor = NSColor(white: 0.40, alpha: 1)
            }
        }
    }

    private func format(_ sec: Int) -> String {
        String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    @objc private func tabClicked(_ gesture: NSClickGestureRecognizer) {
        guard let tab = gesture.view,
              let raw = tab.identifier?.rawValue,
              let mode = PomodoroModel.Mode(rawValue: raw) else { return }
        if model.isRunning {
            let alert = NSAlert()
            alert.messageText = "切换模式将重置计时，确定吗？"
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: view.window!) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.model.switchTo(mode)
                }
            }
        } else {
            model.switchTo(mode)
        }
    }

    @objc private func startClicked() { model.toggle() }

    @objc private func resetClicked() { model.reset() }

    private func sendNotification(for mode: PomodoroModel.Mode) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            if mode == .focus {
                content.title = "番茄钟完成"
                content.body = "专注结束，休息一下吧！已完成 \(self.model.todayCount) 个番茄。"
            }
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }
}

// ── App Delegate ─────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = PomodoroModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupStatusBar()

        // Refresh menu bar time
        model.onUpdate = { [weak self] in self?.updateStatusTitle() }
        model.onComplete = { [weak self] _ in self?.updateStatusTitle() }
        updateStatusTitle()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let vc = PomodoroViewController(model: model)
        vc.onTogglePopover = { [weak self] in self?.togglePopover() }
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 300, height: 390)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Right-click menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        if let button = statusItem.button {
            button.title = "25:00"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
    }

    private func updateStatusTitle() {
        let m = model.remaining / 60
        let s = model.remaining % 60
        let time = String(format: "%02d:%02d", m, s)
        let prefix = model.isRunning ? "● " : ""
        statusItem.button?.title = prefix + time
    }

    @objc private func statusClicked() {
        togglePopover()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Popover closed by clicking outside
    }
}

// ── Entry Point ──────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // hide dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
