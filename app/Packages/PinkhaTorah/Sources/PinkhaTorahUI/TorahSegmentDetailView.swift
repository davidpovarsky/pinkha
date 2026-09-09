import SwiftUI
import PinkhaTorahCore

public struct TorahSegmentDetailView: View {
    public let segment: TorahTextSegment
    public let providerID: String
    public let repository: TorahInspectorRepository
    public let onInsertSegment: (TorahSourceTransfer) -> Void
    public let onClose: () -> Void

    @State private var links: [TorahLinkedSource] = []
    @State private var topics: [TorahLinkedTopic] = []
    @State private var linksError: String?
    @State private var topicsError: String?
    @State private var loadingLinks = true
    @State private var loadingTopics = true

    public init(
        segment: TorahTextSegment,
        providerID: String,
        repository: TorahInspectorRepository,
        onInsertSegment: @escaping (TorahSourceTransfer) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.segment = segment
        self.providerID = providerID
        self.repository = repository
        self.onInsertSegment = onInsertSegment
        self.onClose = onClose
    }

    private var transferPayload: TorahSourceTransfer {
        TorahSourceTransfer(
            providerID: providerID,
            canonicalRef: segment.canonicalRef,
            hebrewRef: segment.hebrewRef,
            text: segment.text
        )
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(segment.text)
                        .font(.body)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Button {
                            onInsertSegment(transferPayload)
                        } label: {
                            Label(TorahStrings.insertIntoDocument, systemImage: "arrow.down.doc")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            TorahPlatformClipboard.copy(segment.text)
                        } label: {
                            Label(TorahStrings.copy, systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text(segment.hebrewRef ?? segment.canonicalRef)
                    .font(.headline)
            }

            relationshipSection(
                title: TorahStrings.text("Commentary"),
                values: links.filter { $0.category == "Commentary" }
            )

            relationshipSection(
                title: TorahStrings.text("Linked sources"),
                values: links.filter { $0.category != "Commentary" }
            )

            Section(TorahStrings.text("Topics")) {
                if loadingTopics {
                    ProgressView()
                } else if let topicsError {
                    retryRow(topicsError) { loadTopics() }
                } else if topics.isEmpty {
                    Text(TorahStrings.text("No results")).foregroundStyle(.secondary)
                } else {
                    ForEach(topics) { topic in
                        HStack {
                            Image(systemName: TorahKindAppearance.symbol(for: .topic))
                                .foregroundStyle(TorahKindAppearance.color(for: .topic))
                            Text(topic.titleHe ?? topic.titleEn ?? topic.slug)
                        }
                    }
                }
            }
        }
        .navigationTitle(segment.hebrewRef ?? segment.canonicalRef)
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
        .task {
            loadLinks()
            loadTopics()
        }
    }

    @ViewBuilder
    private func relationshipSection(title: String, values: [TorahLinkedSource]) -> some View {
        Section(title) {
            if loadingLinks {
                ProgressView()
            } else if let linksError {
                retryRow(linksError) { loadLinks() }
            } else if values.isEmpty {
                Text(TorahStrings.text("No results")).foregroundStyle(.secondary)
            } else {
                ForEach(values) { value in
                    let selection = TorahInspectorSelection(
                        providerID: providerID,
                        canonicalRef: value.sourceRef
                    )
                    NavigationLink(value: TorahInspectorRoute.source(selection)) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: TorahKindAppearance.symbol(for: .ref))
                                .foregroundStyle(TorahKindAppearance.color(for: .ref))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.sourceHebrewRef ?? value.sourceRef)
                                    .font(.body)
                                Text(value.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let text = value.hebrewText {
                                    Text(text)
                                        .font(.caption)
                                        .lineLimit(3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func retryRow(_ message: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button(TorahStrings.retry, action: action)
        }
    }

    private func loadLinks() {
        loadingLinks = true
        linksError = nil
        Task {
            do {
                links = try await repository.links(for: segment.canonicalRef, providerID: providerID)
                loadingLinks = false
            } catch is CancellationError {
            } catch {
                linksError = TorahStrings.couldNotLoadRelatedSources
                loadingLinks = false
            }
        }
    }

    private func loadTopics() {
        loadingTopics = true
        topicsError = nil
        Task {
            do {
                topics = try await repository.topics(for: segment.canonicalRef, providerID: providerID)
                loadingTopics = false
            } catch is CancellationError {
            } catch {
                topicsError = TorahStrings.couldNotLoadRelatedSources
                loadingTopics = false
            }
        }
    }
}
