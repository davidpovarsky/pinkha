import Testing
import UIKit
import PinkhaFFI
@testable import PinkhaRichText

@MainActor
@Suite("Block return semantics")
struct BlockReturnSemanticsTests {
    @Test func returnAndShiftReturnStayInsideTheBlock() {
        var spans = [InlineTextFfi(content: "אב", styles: [])]
        var focused = true
        var newBlockCalls = 0
        let editor = RichTextEditor(
            spans: .init(get: { spans }, set: { spans = $0 }),
            isFocused: .init(get: { focused }, set: { focused = $0 }),
            onSaveSpans: { spans = $0 },
            onNewBlock: { _ in newBlockCalls += 1 }
        )
        let coordinator = RichTextEditorCoordinator(parent: editor)
        let textView = ExpandingTextView()
        textView.attributedText = spansToAttributed(spans, police: editor.baseFont)

        #expect(coordinator.textView(textView, shouldChangeTextIn: NSRange(location: 1, length: 0), replacementText: "\n") == false)
        #expect(textView.text == "א\u{2029}ב")
        #expect(newBlockCalls == 0)

        coordinator.shiftEnterTyped = true
        #expect(coordinator.textView(textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementText: "\n") == false)
        #expect(textView.text == "א\u{2029}\u{2028}ב")
        #expect(newBlockCalls == 0)
    }
}
