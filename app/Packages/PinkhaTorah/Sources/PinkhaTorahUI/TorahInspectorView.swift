import Observation
import PinkhaTorahCore
import SwiftUI

@MainActor @Observable
public final class TorahInspectorModel {
    public private(set) var selection: TorahInspectorSelection
    public private(set) var sections: [TorahTextDocument] = []
    public private(set) var isLoading = false
    public private(set) var loadingPrevious = false
    public private(set) var loadingNext = false
    public private(set) var errorMessage: String?
    @ObservationIgnored private let workspace: TorahWorkspace
    @ObservationIgnored private var cache: [String: TorahTextDocument] = [:]
    @ObservationIgnored private var inFlight = Set<String>()
    @ObservationIgnored private var linksCache: [String: [TorahLinkedSource]] = [:]
    @ObservationIgnored private var topicsCache: [String: [TorahLinkedTopic]] = [:]
    private static let maximumSectionWindow = 7

    public init(workspace: TorahWorkspace, selection: TorahInspectorSelection) {
        self.workspace = workspace; self.selection = selection
    }

    public func open(_ newSelection: TorahInspectorSelection) async {
        selection = newSelection; sections = []; errorMessage = nil; isLoading = true
        defer { isLoading = false }
        do { sections = [try await document(for: newSelection.canonicalRef)] }
        catch is CancellationError {} catch { errorMessage = TorahStrings.message(for: error) }
    }

    public func retry() async { await open(selection) }

    public func links(for reference: String) async throws -> [TorahLinkedSource] {
        if let cached = linksCache[reference] { return cached }
        let values = try await workspace.links(for: reference, providerID: selection.providerID)
        linksCache[reference] = values
        return values
    }

    public func topics(for reference: String) async throws -> [TorahLinkedTopic] {
        if let cached = topicsCache[reference] { return cached }
        let values = try await workspace.topics(for: reference, providerID: selection.providerID)
        topicsCache[reference] = values
        return values
    }

    public func loadPrevious() async {
        guard !loadingPrevious, let reference = sections.first?.previousSectionRef else { return }
        loadingPrevious = true; defer { loadingPrevious = false }
        do {
            let value = try await document(for: reference)
            guard !sections.contains(where: { $0.sectionRef == value.sectionRef }) else { return }
            sections.insert(value, at: 0); trimFromEnd()
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }

    public func loadNext() async {
        guard !loadingNext, let reference = sections.last?.nextSectionRef else { return }
        loadingNext = true; defer { loadingNext = false }
        do {
            let value = try await document(for: reference)
            guard !sections.contains(where: { $0.sectionRef == value.sectionRef }) else { return }
            sections.append(value); trimFromStart()
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }

    private func document(for reference: String) async throws -> TorahTextDocument {
        if let cached = cache[reference] { return cached }
        guard inFlight.insert(reference).inserted else {
            while inFlight.contains(reference) { try await Task.sleep(for: .milliseconds(30)) }
            if let cached = cache[reference] { return cached }
            throw TorahError.network("The source is already loading.")
        }
        defer { inFlight.remove(reference) }
        let value = try await workspace.fetchText(reference: reference, providerID: selection.providerID)
        cache[reference] = value; cache[value.canonicalRef] = value; cache[value.sectionRef] = value
        return value
    }

    private func trimFromEnd() {
        if sections.count > Self.maximumSectionWindow {
            let removed = sections.suffix(sections.count - Self.maximumSectionWindow)
            sections.removeLast(sections.count - Self.maximumSectionWindow)
            removed.forEach(removeFromCache)
        }
    }
    private func trimFromStart() {
        if sections.count > Self.maximumSectionWindow {
            let removed = sections.prefix(sections.count - Self.maximumSectionWindow)
            sections.removeFirst(sections.count - Self.maximumSectionWindow)
            removed.forEach(removeFromCache)
        }
    }
    private func removeFromCache(_ document: TorahTextDocument) {
        cache.removeValue(forKey: document.requestedRef)
        cache.removeValue(forKey: document.canonicalRef)
        cache.removeValue(forKey: document.sectionRef)
    }
}

public struct TorahInspectorView: View {
    private let selection: TorahInspectorSelection
    @State private var model: TorahInspectorModel?
    @State private var path: [TorahTextSegment] = []

    public init(databasePath: String, selection: TorahInspectorSelection) {
        self.selection = selection
        if let workspace = try? TorahWorkspace.application(databasePath: databasePath) {
            _model = State(initialValue: TorahInspectorModel(workspace: workspace, selection: selection))
        }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model { reader(model) }
                else { ContentUnavailableView(l("Torah storage is unavailable."), systemImage: "exclamationmark.triangle") }
            }
            .navigationTitle(l("Source"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TorahTextSegment.self) { segment in
                if let model {
                    TorahSegmentDetailView(segment: segment, model: model) { linkedRef in
                        Task { await model.open(.init(providerID: model.selection.providerID, canonicalRef: linkedRef)); path.removeAll() }
                    }
                }
            }
        }
        .task(id: selection.id) { await model?.open(selection) }
    }

    @ViewBuilder private func reader(_ model: TorahInspectorModel) -> some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView()
        } else if let error = model.errorMessage, model.sections.isEmpty {
            ContentUnavailableView {
                Label(l("No text available"), systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button(l("Retry")) { Task { await model.retry() } }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.loadingPrevious { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.segments) { segment in
                                Button { path.append(segment) } label: {
                                    Text(segment.text)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 5)
                                        .background(model.selection.preferredSegmentRef == segment.canonicalRef ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .environment(\.layoutDirection, section.version.direction == "rtl" ? .rightToLeft : .leftToRight)
                                .onAppear {
                                    if segment.id == model.sections.first?.segments.first?.id { Task { await model.loadPrevious() } }
                                    if segment.id == model.sections.last?.segments.last?.id { Task { await model.loadNext() } }
                                }
                            }
                        } header: {
                            Text(section.hebrewSectionRef ?? section.sectionRef)
                                .font(.headline).foregroundStyle(.secondary)
                        }
                    }
                    if model.loadingNext { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding()
            }
        }
    }

}

private struct TorahSegmentDetailView: View {
    let segment: TorahTextSegment
    let model: TorahInspectorModel
    let onNavigate: (String) -> Void
    @State private var links: [TorahLinkedSource] = []
    @State private var topics: [TorahLinkedTopic] = []
    @State private var linksError: String?
    @State private var topicsError: String?
    @State private var loadingLinks = true
    @State private var loadingTopics = true

    var body: some View {
        List {
            Section {
                Text(segment.text).environment(\.layoutDirection, .rightToLeft)
            } header: { Text(segment.hebrewRef ?? segment.canonicalRef) }
            relationshipSection(title: l("Commentary"), values: links.filter { $0.category == "Commentary" })
            relationshipSection(title: l("Linked sources"), values: links.filter { $0.category != "Commentary" })
            Section(l("Topics")) {
                if loadingTopics { ProgressView() }
                else if let topicsError { retryRow(topicsError) { loadTopics() } }
                else if topics.isEmpty { Text(l("No results")).foregroundStyle(.secondary) }
                else { ForEach(topics) { topic in HStack { Image(systemName: TorahKindAppearance.symbol(for: .topic)).foregroundStyle(TorahKindAppearance.color(for: .topic)); Text(topic.titleHe ?? topic.titleEn ?? topic.slug) } } }
            }
        }
        .navigationTitle(segment.hebrewRef ?? segment.canonicalRef)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLinks(); loadTopics() }
    }

    @ViewBuilder private func relationshipSection(title: String, values: [TorahLinkedSource]) -> some View {
        Section(title) {
            if loadingLinks { ProgressView() }
            else if let linksError { retryRow(linksError) { loadLinks() } }
            else if values.isEmpty { Text(l("No results")).foregroundStyle(.secondary) }
            else {
                ForEach(values) { value in
                    Button { onNavigate(value.sourceRef) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: TorahKindAppearance.symbol(for: .ref)).foregroundStyle(TorahKindAppearance.color(for: .ref))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.sourceHebrewRef ?? value.sourceRef)
                                Text(value.category).font(.caption).foregroundStyle(.secondary)
                                if let text = value.hebrewText { Text(text).font(.caption).lineLimit(3).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func retryRow(_ message: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) { Text(message).font(.caption); Button(l("Retry"), action: action) }
    }
    private func loadLinks() {
        loadingLinks = true; linksError = nil
        Task { do { links = try await model.links(for: segment.canonicalRef); loadingLinks = false }
            catch is CancellationError {} catch { linksError = error.localizedDescription; loadingLinks = false } }
    }
    private func loadTopics() {
        loadingTopics = true; topicsError = nil
        Task { do { topics = try await model.topics(for: segment.canonicalRef); loadingTopics = false }
            catch is CancellationError {} catch { topicsError = error.localizedDescription; loadingTopics = false } }
    }
}

public struct TorahSourceQuoteView: View {
    private let association: TorahAssociation
    private let text: String
    private let onOpen: (TorahInspectorSelection) -> Void
    public init(association: TorahAssociation, text: String, onOpen: @escaping (TorahInspectorSelection) -> Void) {
        self.association = association; self.text = text; self.onOpen = onOpen
    }
    public var body: some View {
        Button {
            onOpen(.init(providerID: association.providerID, canonicalRef: association.canonicalKey, preferredSegmentRef: association.canonicalKey))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(association.labelHe).foregroundStyle(.primary) } icon: {
                    Image(systemName: TorahKindAppearance.symbol(for: .ref)).foregroundStyle(TorahKindAppearance.color(for: .ref))
                }
                .font(.caption.weight(.semibold))
                Text(text).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityLabel("\(association.labelHe), \(l("Open in Inspector"))")
    }
}
