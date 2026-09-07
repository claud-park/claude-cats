import AppKit
import ClaudeCatsCore

/// 바탕화면 위·아이콘 아래 투명 창. 레이어 diff 만 반영하고 60fps 루프는 없다.
@MainActor
final class DesktopWindow {
    private let window: NSWindow
    private let rootLayer = CALayer()
    private var layers: [String: CatLayer] = [:]
    private var layout = Layout(cats: [])
    private var tailTimer: DispatchSourceTimer?

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        rootLayer.contentsScale = screen.backingScaleFactor
        view.layer = rootLayer          // layer-hosting: wantsLayer 보다 먼저 대입
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
    }

    var screenSize: CGSize { window.frame.size }

    func refitToScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window.setFrame(screen.frame, display: true)
        rootLayer.contentsScale = screen.backingScaleFactor
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
