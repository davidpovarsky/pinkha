import Foundation
import Testing
@testable import PinkhaTorahCore

@Suite("Torah Reader Scroll State Machine")
struct TorahReaderStateMachineTests {

    @Test @MainActor func initialAppearanceDoesNotRequestPreviousEvenIfPreviousExists() {
        let sm = TorahReaderScrollStateMachine()
        let decision = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)
        #expect(decision.shouldLoadPrevious == false)
        #expect(decision.shouldLoadNext == false)
        #expect(sm.isTopTriggerArmed == false)
    }

    @Test @MainActor func initialUnderfilledViewportRequestsNextOnly() {
        let sm = TorahReaderScrollStateMachine()
        let decision = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: true)
        #expect(decision.shouldLoadPrevious == false)
        #expect(decision.shouldLoadNext == true)
    }

    @Test @MainActor func scrollingDownArmsTopTrigger() {
        let sm = TorahReaderScrollStateMachine()
        _ = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)

        #expect(sm.isTopTriggerArmed == false)

        // Scroll down to 120 (past arming threshold of 80)
        _ = sm.onScrollOffsetChanged(offsetY: 120, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(sm.isTopTriggerArmed == true)
    }

    @Test @MainActor func scrollingUpNearTopEdgeAfterArmingRequestsPreviousOnce() {
        let sm = TorahReaderScrollStateMachine()
        _ = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)

        // 1. Scroll down into content -> arms trigger
        _ = sm.onScrollOffsetChanged(offsetY: 150, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(sm.isTopTriggerArmed == true)

        // 2. Scroll up towards top (150 -> 30) -> triggers previous
        let decision = sm.onScrollOffsetChanged(offsetY: 30, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(decision.shouldLoadPrevious == true)
        #expect(sm.isLoadingPrevious == true)
        #expect(sm.isTopTriggerArmed == false)

        // 3. Further events while loading cannot trigger duplicate previous load
        let duplicateDecision = sm.onScrollOffsetChanged(offsetY: 20, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(duplicateDecision.shouldLoadPrevious == false)
    }

    @Test @MainActor func anchorRestorationDisarmsTriggerAndPreventsImmediateRetrigger() {
        let sm = TorahReaderScrollStateMachine()
        _ = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)

        // Scroll down then up to trigger
        _ = sm.onScrollOffsetChanged(offsetY: 150, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        _ = sm.onScrollOffsetChanged(offsetY: 30, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)

        // Prepend finishes and anchor restoration starts
        sm.onPreviousLoadCompleted()
        #expect(sm.isRestoringAnchor == true)

        // Layout shifts offset while restoring anchor -> must NOT trigger
        let shiftDecision = sm.onScrollOffsetChanged(offsetY: 35, contentHeight: 1500, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(shiftDecision.shouldLoadPrevious == false)

        // Anchor restoration completes
        sm.onAnchorRestorationCompleted()
        #expect(sm.isRestoringAnchor == false)
        #expect(sm.isTopTriggerArmed == false)

        // Even though we are still near the top (offsetY = 30), it must NOT trigger again!
        let retriggerDecision = sm.onScrollOffsetChanged(offsetY: 25, contentHeight: 1500, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(retriggerDecision.shouldLoadPrevious == false)

        // User must scroll away down into content (e.g. 100) before it can re-arm
        _ = sm.onScrollOffsetChanged(offsetY: 100, contentHeight: 1500, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(sm.isTopTriggerArmed == true)

        // Now scrolling back up triggers again
        let nextLoadDecision = sm.onScrollOffsetChanged(offsetY: 30, contentHeight: 1500, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(nextLoadDecision.shouldLoadPrevious == true)
    }

    @Test @MainActor func pullDownAtTopEdgeTriggersPreviousLoad() {
        let sm = TorahReaderScrollStateMachine()
        _ = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)

        // User pulls down (rubber banding, negative offset)
        let decision = sm.onScrollOffsetChanged(offsetY: -30, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        #expect(decision.shouldLoadPrevious == true)
    }

    @Test @MainActor func scrollingNearBottomEdgeRequestsNextSection() {
        let sm = TorahReaderScrollStateMachine()
        _ = sm.onInitialLoadComplete(hasPrevious: true, hasNext: true, isUnderfilled: false)

        // contentHeight = 1000, containerHeight = 400.
        // At offsetY = 450, distance to bottom is 1000 - 400 - 450 = 150 (<= 200 threshold)
        // Stay just outside the trigger first, then cross it while scrolling down.
        _ = sm.onScrollOffsetChanged(offsetY: 399, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)
        let decision = sm.onScrollOffsetChanged(offsetY: 450, contentHeight: 1000, containerHeight: 400, hasPrevious: true, hasNext: true)

        #expect(decision.shouldLoadNext == true)
        #expect(sm.isLoadingNext == true)
    }
}
