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

    /// 스펙의 "메인 디스플레이" = 원점을 포함한 주 디스플레이(`screens.first`).
    /// `NSScreen.main` 은 키보드 포커스가 있는 화면이라 다르다 — 포커스 따라 고양이가 옮겨다닌다.
    private static var mainDisplay: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    init() {
        let screen = Self.mainDisplay
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = screen?.backingScaleFactor ?? 2

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

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

    func refitToScreen() {
        // setFrame 이 viewDidChangeBackingProperties 를 다시 부를 수 있어 재진입을 막는다.
        guard !isRefitting, let screen = Self.mainDisplay else { return }
        isRefitting = true
        defer { isRefitting = false }

        window.setFrame(screen.frame, display: true)
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
