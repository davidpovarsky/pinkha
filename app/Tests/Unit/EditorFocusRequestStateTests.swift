import Testing
import PinkhaRichText

@Suite("Editor focus request state")
struct EditorFocusRequestStateTests {
    @Test func trueIsConsumedOnlyOnceUntilFalse() {
        var state = EditorFocusRequestState()
        let first = state.consume(requested: true)
        let duplicate = state.consume(requested: true)
        let reset = state.consume(requested: false)
        let second = state.consume(requested: true)
        #expect(first)
        #expect(!duplicate)
        #expect(!reset)
        #expect(second)
    }

    @Test func nativeFocusPreventsBindingEchoFromBecomingARequest() {
        var state = EditorFocusRequestState()
        state.noteNativeFocus()
        let echo = state.consume(requested: true)
        let duplicate = state.consume(requested: true)
        #expect(!echo)
        #expect(!duplicate)
    }

    @Test func dismantlePermanentlyRejectsRequests() {
        var state = EditorFocusRequestState()
        state.dismantle()
        let first = state.consume(requested: true)
        let reset = state.consume(requested: false)
        let second = state.consume(requested: true)
        #expect(!first)
        #expect(!reset)
        #expect(!second)
    }
}
