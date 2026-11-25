#if os(iOS)
import XCTest
import UIKit
@testable import CoreUI
import CoreModels

@MainActor
final class TouchFeedbackTests: XCTestCase {
    func testImmediateActionsAreSilentWhileInactive() {
        var events: [TouchFeedback.Event] = []
        var active = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { active })
        feedback.emit(.impact)
        feedback.emit(.selection)
        feedback.emit(.tension(intensity: 0.25))
        feedback.emit(.tension(intensity: 0.85))
        feedback.emit(.pop)
        active = false
        feedback.emit(.impact)
        feedback.emit(.selection)
        feedback.emit(.tension(intensity: 0.85))
        feedback.emit(.pop)
        XCTAssertEqual(events, [.impact, .selection, .tension(intensity: 0.25), .tension(intensity: 0.85), .pop])
    }

    func testConfirmationIsExplicitAndOneShot() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let confirm = feedback.confirmation()
        XCTAssertTrue(events.isEmpty)
        confirm()
        confirm()
        XCTAssertEqual(events, [.confirmation])
    }

    func testSlowForegroundSuccessHasBothImmediateAndSavedFeedback() async throws {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let confirm = feedback.acknowledgeAction()
        XCTAssertEqual(events, [.impact])
        try await Task.sleep(for: .seconds(3.1))
        confirm()
        confirm()
        XCTAssertEqual(events, [.impact, .confirmation])
    }

    func testStaleProfileConfirmationsStaySilent() {
        var events: [TouchFeedback.Event] = []
        var sameProfile = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let changedProfile = feedback.confirmation(isRelevant: { sameProfile })
        sameProfile = false
        changedProfile()
        sameProfile = true
        changedProfile()
        XCTAssertTrue(events.isEmpty)
        feedback.confirmation()()
        XCTAssertEqual(events, [.confirmation])
    }

    func testErrorFeedbackIsDistinctAndOneShotAfterAcknowledgement() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let reportFailure = feedback.acknowledgeAction(onCompletion: .error)
        XCTAssertEqual(events, [.impact])
        reportFailure()
        reportFailure()
        XCTAssertEqual(events, [.impact, .error])
    }

    func testErrorFeedbackIsCancelledByBackgroundingOrProfileChange() {
        var events: [TouchFeedback.Event] = []
        var sameProfile = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let backgrounded = feedback.acknowledgeAction(onCompletion: .error)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        backgrounded()
        let switched = feedback.acknowledgeAction(onCompletion: .error)
        feedback.invalidatePendingConfirmations()
        switched()
        let stale = feedback.acknowledgeAction(onCompletion: .error, isRelevant: { sameProfile })
        sameProfile = false
        stale()
        sameProfile = true
        stale()
        XCTAssertEqual(events, [.impact, .impact, .impact])
    }

    func testBackgroundingInvalidatesSuccessEvenAfterReturningToForeground() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let confirm = feedback.acknowledgeAction()
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        confirm()
        XCTAssertEqual(events, [.impact])
        feedback.acknowledgeAction()()
        XCTAssertEqual(events, [.impact, .impact, .confirmation])
    }

    func testExplicitProfileActivationCancelsPendingConfirmation() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true })
        let confirm = feedback.acknowledgeAction()
        feedback.invalidatePendingConfirmations()
        confirm()
        XCTAssertEqual(events, [.impact])
    }

    func testBackgroundCompletionIsConsumedWithoutReplayingOnReturn() {
        var events: [TouchFeedback.Event] = []
        var active = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { active })
        let confirm = feedback.confirmation()
        active = false
        confirm()
        active = true
        confirm()
        XCTAssertTrue(events.isEmpty)
    }
}
#endif
