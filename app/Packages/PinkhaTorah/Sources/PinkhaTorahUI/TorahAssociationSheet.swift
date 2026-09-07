import PinkhaTorahCore
import SwiftUI

public struct TorahAssociationSheet: View {
    private let target: TorahTarget
    private let onMutation: () -> Void
    @State private var workspace: TorahWorkspace?
    @State private var associations: [TorahAssociation] = []
    @State private var presentedKind: TorahAssociationKind?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(databasePath: String, target: TorahTarget, onMutation: @escaping () -> Void = {}) {
        self.target = target
        self.onMutation = onMutation
        _workspace = State(initialValue: try? TorahWorkspace.application(databasePath: databasePath))
    }

    public var body: some View {
        NavigationStack {
            List {
                if associations.isEmpty {
                    ContentUnavailableView(l("No Torah links"), systemImage: "books.vertical")
                } else {
                    ForEach(associations) { association in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(association.labelHe)
                            Text(secondaryLabel(association)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("torahAssociationRow.\(association.id)")
                        .swipeActions {
                            Button(l("Delete"), role: .destructive) { remove(association) }
                                .accessibilityIdentifier("torahDeleteAssociationButton")
                        }
                    }
                }
            }
            .navigationTitle(l("Torah links"))
            .accessibilityIdentifier("torahAssociationSheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l("Done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    TorahAddLinkControl { presentedKind = $0 }
                }
            }
            .task { await reload() }
            .alert(l("Error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(l("OK"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .sheet(item: $presentedKind, onDismiss: { Task { await reload() } }) { kind in
                if let workspace {
                    TorahSearchSheet(workspace: workspace, target: target, kind: kind) {
                        onMutation()
                    }
                }
            }
        }
    }
    private func secondaryLabel(_ value: TorahAssociation) -> String {
        let kind = switch value.kind { case .ref: l("Source"); case .topic: l("Topic"); case .word: l("Word") }
        let detail = value.labelEn.map { " · \($0)" } ?? ""
        return "\(kind) · \(value.providerID)\(detail)"
    }
    private func reload() async {
        guard let workspace else { errorMessage = l("Torah storage is unavailable."); return }
        do { associations = try await workspace.associations(for: target) }
        catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ association: TorahAssociation) {
        Task { do { try await workspace?.remove(associationID: association.id); await reload(); onMutation() }
            catch { errorMessage = error.localizedDescription } }
    }
}

public struct TorahSearchSheet: View {
    let kind: TorahAssociationKind
    let target: TorahTarget
    let onSaved: () -> Void
    @State private var workspace: TorahWorkspace?

    public init(databasePath: String, target: TorahTarget, kind: TorahAssociationKind, onSaved: @escaping () -> Void = {}) {
        self.kind = kind
        self.target = target
        self.onSaved = onSaved
        _workspace = State(initialValue: try? TorahWorkspace.application(databasePath: databasePath))
    }

    init(workspace: TorahWorkspace, target: TorahTarget, kind: TorahAssociationKind, onSaved: @escaping () -> Void) {
        self.kind = kind
        self.target = target
        self.onSaved = onSaved
        _workspace = State(initialValue: workspace)
    }

    public var body: some View {
        if let workspace {
            TorahSearchPicker(kind: kind, target: target, workspace: workspace, onSaved: onSaved)
        } else {
            ContentUnavailableView(l("Torah storage is unavailable."), systemImage: "exclamationmark.triangle")
        }
    }
}

private struct TorahSearchPicker: View {
    let kind: TorahAssociationKind
    let target: TorahTarget
    let workspace: TorahWorkspace
    let onSaved: () -> Void
    @State private var query = ""
    @State private var references: [ReferenceCandidate] = []
    @State private var topics: [TopicCandidate] = []
    @State private var words: [WordCandidate] = []
    @State private var searching = false
    @State private var resolving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if searching { ProgressView().frame(maxWidth: .infinity) }
                switch kind {
                case .ref:
                    ForEach(references) { value in
                        Button(value.label) { saveReference(value) }
                            .disabled(resolving)
                            .accessibilityIdentifier("torahReferenceResult.\(value.id)")
                    }
                case .topic:
                    ForEach(topics) { value in
                        Button { saveTopic(value.id) } label: {
                            VStack(alignment: .leading) { Text(value.labelHe); if let en = value.labelEn { Text(en).font(.caption).foregroundStyle(.secondary) } }
                        }
                        .disabled(resolving)
                        .accessibilityIdentifier("torahTopicResult.\(value.id)")
                    }
                case .word:
                    ForEach(words) { value in
                        Button { saveWord(value) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(value.headword)
                                Text([value.lexicon, value.description].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(resolving)
                        .accessibilityIdentifier("torahWordResult.\(value.id)")
                    }
                }
                if !query.isEmpty && !searching && references.isEmpty && topics.isEmpty && words.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(title)
            .searchable(text: $query, prompt: prompt)
            .task(id: query) { await search() }
            .task { if kind == .topic { try? await workspace.refreshTopicIndexIfNeeded() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l("Cancel")) { dismiss() } }
            }
            .alert(l("Error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(l("OK"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .overlay { if resolving { ProgressView().controlSize(.small) } }
        .accessibilityIdentifier(searchSheetIdentifier)
    }

    private var searchSheetIdentifier: String { "torah\(kind.rawValue.capitalized)SearchSheet" }
    private var title: String { switch kind { case .ref: l("Source"); case .topic: l("Topic"); case .word: l("Word") } }
    private var prompt: String { switch kind { case .ref: l("Search references"); case .topic: l("Search topics"); case .word: l("Search words") } }
    private func search() async {
        references = []; topics = []; words = []; errorMessage = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(275)); try Task.checkCancellation(); searching = true
            defer { searching = false }
            switch kind {
            case .ref: references = try await workspace.suggestReferences(trimmed)
            case .topic: topics = try await workspace.suggestTopics(trimmed)
            case .word: words = try await workspace.suggestWords(trimmed, context: try await workspace.lexicalContext(for: target))
            }
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }
    private func saveReference(_ candidate: ReferenceCandidate) { save { let value = try await workspace.resolveReference(candidate.id); try await workspace.addReference(value, rawInput: query, to: target) } }
    private func saveTopic(_ id: String) { save { let value = try await workspace.resolveTopic(id); try await workspace.addTopic(value, to: target) } }
    private func saveWord(_ value: WordCandidate) { save { try await workspace.addWord(ResolvedWord(candidate: value), to: target) } }
    private func save(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !resolving else { return }
        resolving = true
        Task {
            do {
                try await operation()
                onSaved()
                dismiss()
            } catch {
                resolving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

func l(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
