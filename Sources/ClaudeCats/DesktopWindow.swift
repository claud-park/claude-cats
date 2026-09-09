import AppKit
import ClaudeCatsCore

/// backing scale 이 바뀌면 알려주는 layer-hosting 콘텐츠 뷰.
/// 화면 파라미터 알림 없이 스케일만 바뀌는 경우(창이 다른 배율 디스플레이로 옮겨감)를 잡는다.
private final class DesktopContentView: NSView {
    var onBackingPropertiesChanged: (() -> Void)?

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onBackingPropertiesChanged?()
    }
}

/// 바탕화면 위·아이콘 아래 투명 창. 레이어 diff 만 반영하고 60fps 루프는 없다.
@MainActor
final class DesktopWindow {
    private let window: NSWindow
    private let contentView: DesktopContentView
    private let rootLayer = CALayer()
    private var layers: [String: CatLayer] = [:]
    private var layout = Layout(cats: [])
    private var tailTimer: DispatchSourceTimer?
    private var isRefitting = false

    /// 사용자가 메뉴에서 고른 디스플레이 이름. nil 이면 메인 디스플레이(자동).
    private var preferredDisplayName: String?

    /// 고양이를 화면 바닥에서 얼마나 띄울지. 창은 `frame` 전체를 덮지만 배치는
    /// `visibleFrame` 위에 올려 하단 Dock 에 묻히지 않게 한다. `refitToScreen` 에서 다시 잰다.
    private(set) var sceneBottomInset: CGFloat = SceneConfig().bottomInset

    /// 지금 창 레벨. 화면을 다시 맞춰도 유지된다.
    private var placement: WindowPlacement

    /// 선택한 이름의 디스플레이. 이름이 안 맞거나(뽑아버린 모니터) 없으면 메인으로 폴백한다.
    /// 저장 프로퍼티가 다 차기 전(init)에도 불러야 해서 static 이다.
    private static func targetScreen(preferredDisplayName: String?) -> NSScreen? {
        let screens = NSScreen.screens
        let fallback = screens.first ?? NSScreen.main
        guard let resolved = DisplaySelection.resolve(
            preferredName: preferredDisplayName,
            available: DisplayCatalog.current()
        ) else { return fallback }
        // 이름이 겹치면 resolve 와 같이 첫 번째를 쓴다.
        return screens.first { $0.localizedName == resolved.name } ?? fallback
    }

    private func targetScreen() -> NSScreen? {
        Self.targetScreen(preferredDisplayName: preferredDisplayName)
    }

    /// 화면 하나의 Dock 여백. 화면이 없으면(디스플레이가 다 빠짐) 기본 여백만 쓴다.
    private static func bottomInset(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return SceneConfig().bottomInset }
        return LayoutInsets.bottomInset(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            base: SceneConfig().bottomInset
        )
    }

    init(preferredDisplayName: String? = nil, placement: WindowPlacement = .desktop) {
        self.preferredDisplayName = preferredDisplayName
        self.placement = placement
        let screen = Self.targetScreen(preferredDisplayName: preferredDisplayName)
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = screen?.backingScaleFactor ?? 2
        sceneBottomInset = Self.bottomInset(for: screen)

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        Self.apply(placement, to: window)

        contentView = DesktopContentView(frame: NSRect(origin: .zero, size: frame.size))
        rootLayer.contentsScale = scale
        contentView.layer = rootLayer   // layer-hosting: wantsLayer 보다 먼저 대입
        contentView.wantsLayer = true
        window.contentView = contentView
        window.orderFrontRegardless()

        // 모든 저장 프로퍼티가 채워진 뒤라야 self 를 캡처할 수 있다.
        contentView.onBackingPropertiesChanged = { [weak self] in self?.refitToScreen() }
    }

    var screenSize: CGSize { window.frame.size }

    /// 메뉴에서 디스플레이를 고르면 호출된다. nil = 자동(메인).
    func setPreferredDisplay(_ name: String?) {
        preferredDisplayName = name
        refitToScreen()
    }

    /// 메뉴에서 `표시 위치` 를 고르면 호출된다. 창을 다시 만들지 않고 레벨만 바꾼다.
    func setPlacement(_ new: WindowPlacement) {
        guard new != placement else { return }
        placement = new
        Self.apply(new, to: window)
    }

    /// `WindowPlacement` → 실제 `NSWindow.Level` · collectionBehavior.
    private static func apply(_ placement: WindowPlacement, to window: NSWindow) {
        switch placement.levelOffset {
        case let .desktopIcon(offset):
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + offset)
        case .floating:
            window.level = .floating
        }
        // 모든 스페이스에 남고(canJoinAllSpaces), 스페이스를 바꿔도 따라 움직이지 않고(stationary),
        // ⌘⇥ 순환에서 빠진다(ignoresCycle). `항상 위` 일 때만 전체화면 앱 위에도 뜨게
        // fullScreenAuxiliary 를 더한다 — 클릭은 ignoresMouseEvents 로 통과하므로 포커스를 뺏지 않는다.
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if placement == .alwaysOnTop { behavior.insert(.fullScreenAuxiliary) }
        window.collectionBehavior = behavior
    }

    func refitToScreen() {
        // setFrame 이 viewDidChangeBackingProperties 를 다시 부를 수 있어 재진입을 막는다.
        guard !isRefitting, let screen = targetScreen() else { return }
        isRefitting = true
        defer { isRefitting = false }

        // 보조 디스플레이는 frame.origin 이 0 이 아니다. 창은 전역 좌표로 옮기고,
        // 콘텐츠 뷰는 창 좌표계의 원점에 그대로 둔다 — Scene·말풍선 계산은 영향받지 않는다.
        window.setFrame(screen.frame, display: true)
        contentView.frame = NSRect(origin: .zero, size: screen.frame.size)
        // Dock 크기·자동 숨김·위치가 바뀌면 didChangeScreenParameters 가 여기로 온다.
        sceneBottomInset = Self.bottomInset(for: screen)
        let scale = screen.backingScaleFactor
        rootLayer.contentsScale = scale
        // 이미 만들어진 고양이들은 생성 시점 스케일을 들고 있으므로 같이 내려준다.
        for layer in layers.values {
            layer.setContentsScale(scale)
        }
    }

    func apply(_ new: Layout) {
        let diff = LayoutDiffer.diff(from: layout, to: new)
        layout = new
        guard !diff.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in diff.removed {
            guard let layer = layers.removeValue(forKey: id) else { continue }
            fadeOutAndRemove(layer)
        }
        for cat in diff.updated {
            layers[cat.id]?.apply(cat)
        }
        for cat in diff.added {
            let layer = CatLayer(placement: cat, contentsScale: rootLayer.contentsScale)
            layer.opacity = 0
            rootLayer.addSublayer(layer)
            layers[cat.id] = layer
            fadeIn(layer)
        }
        CATransaction.commit()

        updateTailTimer()
    }

    private func fadeIn(_ layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0
        anim.toValue = 1
        anim.duration = 0.3
        layer.opacity = 1
        layer.add(anim, forKey: "fade")
    }

    private func fadeOutAndRemove(_ layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1
        anim.toValue = 0
        anim.duration = 0.3
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        layer.add(anim, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            layer.removeFromSuperlayer()
        }
    }

    // MARK: - 꼬리 애니메이션 (1초 주기, animated 고양이가 있을 때만)

    private func updateTailTimer() {
        let hasAnimated = layers.values.contains { $0.placement.animated }
        if hasAnimated, tailTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.tickTails() }
            }
            timer.resume()
            tailTimer = timer
        } else if !hasAnimated, let timer = tailTimer {
            timer.cancel()
            tailTimer = nil
        }
    }

    private func tickTails() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.values where layer.placement.animated {
            layer.tickTail()
        }
        CATransaction.commit()
    }
}
