#if canImport(UIKit)
import UIKit

final class PlayerSurfacePanGestureRecognizer: UIPanGestureRecognizer {
    var click = RemoteClickInterpreter()
    var onStationaryTap: (() -> Void)?
    private var tap = RemoteTapInterpreter()
    private weak var tapTouch: UITouch?
    private(set) var contactStartTimestamp: TimeInterval?
    private(set) var sampleTimestamp: TimeInterval?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        click.touchBegan()
        if tapTouch == nil, touches.count == 1, let touch = touches.first, touch.type == .indirect {
            tapTouch = touch
            tap.began(at: touch.location(in: view), timestamp: event.timestamp)
        } else {
            tap.cancel()
        }
        contactStartTimestamp = event.timestamp
        sampleTimestamp = event.timestamp
        ScrubDiagnostics.note("remote-touch began")
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        sampleTimestamp = event.timestamp
        observeTapMovement(in: event)
        super.touchesMoved(touches, with: event)
        if state != .possible { tap.cancel() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        sampleTimestamp = event.timestamp
        observeTapMovement(in: event)
        ScrubDiagnostics.note("remote-touch ended click=\(click.suppressesPan)")
        let stationary: Bool
        if let touch = tapTouch, touches.contains(touch), !click.suppressesPan, state == .possible {
            stationary = tap.ended(at: touch.location(in: view), timestamp: event.timestamp)
        } else {
            stationary = false
        }
        tap.cancel()
        tapTouch = nil
        super.touchesEnded(touches, with: event)
        if stationary { onStationaryTap?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        sampleTimestamp = event.timestamp
        tap.cancel()
        tapTouch = nil
        super.touchesCancelled(touches, with: event)
    }

    func cancelTap() {
        tap.cancel()
    }

    private func observeTapMovement(in event: UIEvent) {
        guard let touch = tapTouch else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            tap.moved(to: sample.location(in: view))
        }
    }

    override func reset() {
        super.reset()
        tap.cancel()
        tapTouch = nil
    }
}
#endif
