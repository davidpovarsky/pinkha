import Observation
import PinkhaTorahCore
import SwiftUI

@MainActor @Observable
public final class TorahInspectorModel {
    public private(set) var selection: TorahInspectorSelection
    public let repository: TorahInspectorRepository

    public init(workspace: TorahWorkspace, selection: TorahInspectorSelection) {
        self.selection = selection
        self.repository = TorahInspectorRepository(workspace: workspace)
    }

    public init(repository: TorahInspectorRepository, selection: TorahInspectorSelection) {
        self.selection = selection
        self.repository = repository
    }
}

public struct TorahInspectorView: View {
    private let selection: TorahInspectorSelection
    private let onClose: () -> Void
    private let onInsertSegment: (TorahSourceTransfer) -> Void
    @State private var repository: TorahInspectorRepository?

    public init(
        databasePath: String,
        selection: TorahInspectorSelection,
        onClose: @escaping () -> Void = {},
        onInsertSegment: @escaping (TorahSourceTransfer) -> Void = { _ in }
    ) {
        self.selection = selection
        self.onClose = onClose
        self.onInsertSegment = onInsertSegment
        if let workspace = try? TorahWorkspace.application(databasePath: databasePath) {
            _repository = State(initialValue: TorahInspectorRepository(workspace: workspace))
        }
    }

    public var body: some View {
        NavigationStack {
            if let repository {
                TorahSourceReaderView(
                    selection: selection,
                    repository: repository,
                    onInsertSegment: onInsertSegment,
                    onClose: onClose
                )
                .navigationDestination(for: TorahInspectorRoute.self) { route in
                    switch route {
                    case .segment(let segment):
                        TorahSegmentDetailView(
                            segment: segment,
                            providerID: selection.providerID,
                            repository: repository,
                            onInsertSegment: onInsertSegment,
                            onClose: onClose
                        )
                    case .source(let nextSelection):
                        TorahSourceReaderView(
                            selection: nextSelection,
                            repository: repository,
                            onInsertSegment: onInsertSegment,
                            onClose: onClose
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    TorahStrings.storageUnavailable,
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }
}

public struct TorahSourceQuoteView: View {
    private let association: TorahAssociation
    private let text: String
    private let onOpen: (TorahInspectorSelection) -> Void

    public init(association: TorahAssociation, text: String, onOpen: @escaping (TorahInspectorSelection) -> Void) {
        self.association = association
        self.text = text
        self.onOpen = onOpen
    }

    public var body: some View {
        Button {
            onOpen(.init(
                providerID: association.providerID,
                canonicalRef: association.canonicalKey,
                preferredSegmentRef: association.canonicalKey
            ))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(association.labelHe).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: TorahKindAppearance.symbol(for: .ref))
                        .foregroundStyle(TorahKindAppearance.color(for: .ref))
                }
                .font(.caption.weight(.semibold))

                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityLabel("\(association.labelHe), \(TorahStrings.text("Open in Inspector"))")
    }
}
