import Testing
import PinkhaRichText

@Suite("Editor focus request state")
struct EditorFocusRequestStateTests {
    @Test func trueIsConsumedOnlyOnceUntilFalse() {
        var state = EditorFocusRequestState()
        #expect(state.consume(requested: true))
        #expect(!state.consume(requested: true))
        #expect(!state.consume(requested: false))
        #expect(state.consume(requested: true))
    }

    @Test func nativeFocusPreventsBindingEchoFromBecomingARequest() {
        var state = EditorFocusRequestState()
        state.noteNativeFocus()
        #expect(!state.consume(requested: true))
        #expect(!state.consume(requested: true))
    }

    @Test func dismantlePermanentlyRejectsRequests() {
        var state = EditorFocusRequestState()
        state.dismantle()
        #expect(!state.consume(requested: true))
        #expect(!state.consume(requested: false))
        #expect(!state.consume(requested: true))
    }
}
