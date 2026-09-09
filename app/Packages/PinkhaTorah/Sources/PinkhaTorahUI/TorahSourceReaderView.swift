import SwiftUI
import Observation
import PinkhaTorahCore

public struct TorahSegmentPreviewCard: View {
    public let segment: TorahTextSegment
    public let section: TorahTextDocument

    public init(segment: TorahTextSegment, section: TorahTextDocument) {
        self.segment = segment
        self.section = section
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(segment.hebrewRef ?? segment.canonicalRef)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(segment.text)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .environment(\.layoutDirection, section.version.direction == "rtl" ? .rightToLeft : .leftToRight)
    }
}

public struct TorahDragPreview: View {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 240, alignment: .leading)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct ScrollOffsetInfo: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
}

public struct TorahSourceReaderView: View {
    public let selection: TorahInspectorSelection
    public let repository: TorahInspectorRepository
    public let onInsertSegment: (TorahSourceTransfer) -> Void
    public let onClose: () -> Void

    @State private var sections: [TorahTextDocument] = []
    @State private var isLoading = false
    @State private var loadingPrevious = false
    @State private var loadingNext = false
    @State private var errorMessage: String?
    @State private var stateMachine = TorahReaderScrollStateMachine()

    private static let maximumSectionWindow = 7

    public init(
        selection: TorahInspectorSelection,
        repository: TorahInspectorRepository,
        onInsertSegment: @escaping (TorahSourceTransfer) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.selection = selection
        self.repository = repository
        self.onInsertSegment = onInsertSegment
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if isLoading && sections.isEmpty {
                ProgressView()
            } else if let error = errorMessage, sections.isEmpty {
                ContentUnavailableView {
                    Label(TorahStrings.text("No text available"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button(TorahStrings.retry) {
                        Task { await initialLoad() }
                    }
                }
            } else {
                readerContent
            }
        }
        .navigationTitle(displayTitle)
        .torahInlineNavigationTitle()
        .toolbar {
            ToolbarItem {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(TorahStrings.close)
            }
        }
        .task(id: selection.id) {
            await initialLoad()
        }
    }

    private var displayTitle: String {
        sections.first?.hebrewSectionRef ?? sections.first?.sectionRef ?? selection.canonicalRef
    }

    @ViewBuilder
    private var readerContent: some View {
        ScrollViewReader { proxy in
            if #available(macOS 15.0, *) {
                readerScrollView
                    .onScrollGeometryChange(for: ScrollOffsetInfo.self) { geometry in
                        ScrollOffsetInfo(
                            offsetY: geometry.contentOffset.y,
                            contentHeight: geometry.contentSize.height,
                            containerHeight: geometry.containerSize.height
                        )
                    } action: { _, newValue in
                        handleScrollChange(newValue, proxy: proxy)
                    }
            } else {
                readerScrollView
            }
        }
    }

    private var readerScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if loadingPrevious {
                    ProgressView().frame(maxWidth: .infinity)
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.segments) { segment in
                            segmentRow(segment, in: section)
                                .id(segment.id)
                        }
                    } header: {
                        Text(section.hebrewSectionRef ?? section.sectionRef)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                if loadingNext {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func segmentRow(_ segment: TorahTextSegment, in section: TorahTextDocument) -> some View {
        let isPreferred = selection.preferredSegmentRef == segment.canonicalRef
        let transfer = TorahSourceTransfer(segment: segment, document: section)

        NavigationLink(value: TorahInspectorRoute.segment(segment)) {
            Text(segment.text)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .padding(.horizontal, 5)
                .background(
                    isPreferred ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, section.version.direction == "rtl" ? .rightToLeft : .leftToRight)
        .contextMenu {
            Button {
                onInsertSegment(transfer)
            } label: {
                Label(TorahStrings.insertIntoDocument, systemImage: "arrow.down.doc")
            }
            Button {
                TorahPlatformClipboard.copy(segment.text)
            } label: {
                Label(TorahStrings.copy, systemImage: "doc.on.doc")
            }
            NavigationLink(value: TorahInspectorRoute.segment(segment)) {
                Label(TorahStrings.viewDetails, systemImage: "info.circle")
            }
        } preview: {
            TorahSegmentPreviewCard(segment: segment, section: section)
        }
        .draggable(transfer) {
            TorahDragPreview(title: segment.hebrewRef ?? segment.canonicalRef, text: segment.text)
        }
        .onDrag {
            transfer.itemProvider
        }
    }

    private func handleScrollChange(_ info: ScrollOffsetInfo, proxy: ScrollViewProxy) {
        let hasPrevious = sections.first?.previousSectionRef != nil
        let hasNext = sections.last?.nextSectionRef != nil

        let decision = stateMachine.onScrollOffsetChanged(
            offsetY: info.offsetY,
            contentHeight: info.contentHeight,
            containerHeight: info.containerHeight,
            hasPrevious: hasPrevious,
            hasNext: hasNext
        )

        if decision.shouldLoadPrevious {
            Task { await loadPrevious(proxy: proxy) }
        }
        if decision.shouldLoadNext {
            Task { await loadNext() }
        }
    }

    private func initialLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let doc = try await repository.document(for: selection.canonicalRef, providerID: selection.providerID)
            sections = [doc]

            let isUnderfilled = doc.segments.count <= 2
            let decision = stateMachine.onInitialLoadComplete(
                hasPrevious: doc.previousSectionRef != nil,
                hasNext: doc.nextSectionRef != nil,
                isUnderfilled: isUnderfilled
            )

            if decision.shouldLoadNext {
                await loadNext()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = TorahStrings.message(for: error)
        }
    }

    private func loadPrevious(proxy: ScrollViewProxy) async {
        guard !loadingPrevious, let reference = sections.first?.previousSectionRef else { return }
        loadingPrevious = true
        defer { loadingPrevious = false }

        let anchorSegmentId = sections.first?.segments.first?.id

        do {
            let doc = try await repository.document(for: reference, providerID: selection.providerID)
            guard !sections.contains(where: { $0.sectionRef == doc.sectionRef }) else {
                stateMachine.onPreviousLoadCompleted()
                stateMachine.onAnchorRestorationCompleted()
                return
            }

            sections.insert(doc, at: 0)
            trimFromEnd()
            stateMachine.onPreviousLoadCompleted()

            // Restore scroll anchor immediately without animation
            if let anchorSegmentId {
                proxy.scrollTo(anchorSegmentId, anchor: .top)
            }
            stateMachine.onAnchorRestorationCompleted()
        } catch is CancellationError {
            stateMachine.onPreviousLoadFailed()
        } catch {
            stateMachine.onPreviousLoadFailed()
        }
    }

    private func loadNext() async {
        guard !loadingNext, let reference = sections.last?.nextSectionRef else { return }
        loadingNext = true
        defer { loadingNext = false }

        do {
            let doc = try await repository.document(for: reference, providerID: selection.providerID)
            guard !sections.contains(where: { $0.sectionRef == doc.sectionRef }) else {
                stateMachine.onNextLoadCompleted()
                return
            }

            sections.append(doc)
            trimFromStart()
            stateMachine.onNextLoadCompleted()
        } catch is CancellationError {
            stateMachine.onNextLoadFailed()
        } catch {
            stateMachine.onNextLoadFailed()
        }
    }

    private func trimFromEnd() {
        if sections.count > Self.maximumSectionWindow {
            sections.removeLast(sections.count - Self.maximumSectionWindow)
        }
    }

    private func trimFromStart() {
        if sections.count > Self.maximumSectionWindow {
            sections.removeFirst(sections.count - Self.maximumSectionWindow)
        }
    }
}
