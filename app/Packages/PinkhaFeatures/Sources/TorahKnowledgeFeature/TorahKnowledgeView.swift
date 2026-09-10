import SwiftUI
import PinkhaCore
import PinkhaDesignSystem
import PinkhaTorahCore
import LeafFeature

/// Main Torah Knowledge tab view.
/// A full primary Pinkha screen at the same app-navigation level as Library, Books, Inbox.
/// Shows the user's Pinkha pages organized by their Torah associations.
public struct TorahKnowledgeView: View {
    @Environment(PinkhaStore.self) var store
    @Environment(TabManager.self) var tabManager
    @State private var viewModel: TorahKnowledgeViewModel?
    @State private var selectedSegment: TorahKnowledgeViewModel.Segment = .source
    @State private var pushedLeafId: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    contentView(viewModel: viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("תורה")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $pushedLeafId) { leafId in
                if let api = store.api {
                    LeafView(vm: tabManager.open(leafId: leafId, api: api))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            guard viewModel == nil, let path = store.activeDatabasePath else { return }
            let vm = TorahKnowledgeViewModel(databasePath: path)
            viewModel = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func contentView(viewModel: TorahKnowledgeViewModel) -> some View {
        VStack(spacing: 0) {
            // Segmented picker: מקור | מילה | נושא
            Picker("", selection: $selectedSegment) {
                ForEach(TorahKnowledgeViewModel.Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedSegment {
            case .source:
                sourceSegmentView(viewModel: viewModel)
            case .word:
                associationGroupList(
                    groups: viewModel.wordGroups,
                    kind: .word,
                    viewModel: viewModel
                )
            case .topic:
                associationGroupList(
                    groups: viewModel.topicGroups,
                    kind: .topic,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Source segment (hierarchy browser)

    @ViewBuilder
    private func sourceSegmentView(viewModel: TorahKnowledgeViewModel) -> some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.currentHierarchyNodes.isEmpty {
            ContentUnavailableView(
                "אין מקורות",
                systemImage: "books.vertical",
                description: Text("הוסיפו קישורי תורה לדפים שלכם כדי לראות אותם כאן.")
            )
        } else {
            VStack(spacing: 0) {
                // Breadcrumb bar
                if !viewModel.hierarchyPath.isEmpty {
                    breadcrumbBar(viewModel: viewModel)
                }

                List {
                    ForEach(viewModel.currentHierarchyNodes) { node in
                        hierarchyNodeRow(node: node, viewModel: viewModel)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func breadcrumbBar(viewModel: TorahKnowledgeViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    viewModel.navigateToRoot()
                } label: {
                    Image(systemName: "house")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                ForEach(Array(viewModel.hierarchyPath.enumerated()), id: \.element.id) { index, node in
                    Image(systemName: "chevron.left")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Button {
                        // Navigate to this level by truncating the path
                        viewModel.hierarchyPath = Array(viewModel.hierarchyPath.prefix(index + 1))
                    } label: {
                        Text(node.labelHe)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(index == viewModel.hierarchyPath.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.pinkhaSurfaceElevated)
    }

    @ViewBuilder
    private func hierarchyNodeRow(node: TorahSourceNode, viewModel: TorahKnowledgeViewModel) -> some View {
        if node.children.isEmpty && node.hasDirectLeaves {
            // Terminal node with leaves — tap opens the leaf list
            Button {
                if let key = node.canonicalKey {
                    Task {
                        await viewModel.loadLeafIDs(forKey: key, kind: .ref)
                    }
                }
            } label: {
                hierarchyNodeLabel(node: node, isTerminal: true)
            }
            .sheet(item: Binding(
                get: { viewModel.selectedKey == node.canonicalKey ? node.canonicalKey : nil },
                set: { if $0 == nil { viewModel.selectedKey = nil } }
            )) { _ in
                leafListSheet(viewModel: viewModel, title: node.labelHe)
            }
        } else if !node.children.isEmpty {
            // Branch node — navigate into
            Button {
                viewModel.navigateInto(node)
            } label: {
                hierarchyNodeLabel(node: node, isTerminal: false)
            }
        }
    }

    @ViewBuilder
    private func hierarchyNodeLabel(node: TorahSourceNode, isTerminal: Bool) -> some View {
        HStack {
            Image(systemName: isTerminal ? "doc.text" : "folder")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.labelHe)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let en = node.labelEn, en != node.labelHe {
                    Text(en)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if node.descendantLeafCount > 0 {
                Text("(\(node.descendantLeafCount))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !isTerminal {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Word / Topic segments (flat grouped lists)

    @ViewBuilder
    private func associationGroupList(
        groups: [(canonicalKey: String, labelHe: String, leafCount: Int)],
        kind: TorahAssociationKind,
        viewModel: TorahKnowledgeViewModel
    ) -> some View {
        if groups.isEmpty {
            ContentUnavailableView(
                kind == .word ? "אין מילים" : "אין נושאים",
                systemImage: kind == .word ? "textformat.abc" : "tag",
                description: Text("הוסיפו קישורי תורה לדפים שלכם כדי לראות אותם כאן.")
            )
        } else {
            List {
                ForEach(groups, id: \.canonicalKey) { group in
                    Button {
                        Task {
                            await viewModel.loadLeafIDs(forKey: group.canonicalKey, kind: kind)
                        }
                    } label: {
                        HStack {
                            Text(group.labelHe)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("(\(group.leafCount))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .sheet(item: Binding(
                        get: { viewModel.selectedKey == group.canonicalKey ? group.canonicalKey : nil },
                        set: { if $0 == nil { viewModel.selectedKey = nil } }
                    )) { _ in
                        leafListSheet(viewModel: viewModel, title: group.labelHe)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Leaf list sheet

    @ViewBuilder
    private func leafListSheet(viewModel: TorahKnowledgeViewModel, title: String) -> some View {
        NavigationStack {
            List {
                ForEach(viewModel.selectedLeafIDs, id: \.self) { leafId in
                    Button {
                        viewModel.selectedKey = nil
                        pushedLeafId = leafId
                    } label: {
                        leafRow(leafId: leafId)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגור") {
                        viewModel.selectedKey = nil
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder
    private func leafRow(leafId: String) -> some View {
        let title = resolveLeafTitle(leafId: leafId)
        HStack {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Image(systemName: "chevron.left")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .contentShape(Rectangle())
    }

    private func resolveLeafTitle(leafId: String) -> String {
        guard let api = store.api,
              let doc = try? api.getLeaf(id: leafId) else {
            return leafId
        }
        let title = doc.title.map(\.content).joined()
        return title.isEmpty ? "ללא כותרת" : title
    }
}

// MARK: - String + Identifiable for sheet binding

extension String: @retroactive Identifiable {
    public var id: String { self }
}
