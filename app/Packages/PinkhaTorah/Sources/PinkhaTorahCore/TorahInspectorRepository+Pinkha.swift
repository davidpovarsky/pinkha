import TorahInspectorCore

public extension TorahInspectorRepository {
    convenience init(
        workspace: TorahWorkspace,
        documentCapacity: Int = 30,
        relationshipCapacity: Int = 50
    ) {
        self.init(
            documentCapacity: documentCapacity,
            relationshipCapacity: relationshipCapacity,
            textFetcher: { reference, providerID in
                try await workspace.fetchText(reference: reference, providerID: providerID)
            },
            linksFetcher: { reference, providerID in
                try await workspace.links(for: reference, providerID: providerID)
            },
            topicsFetcher: { reference, providerID in
                try await workspace.topics(for: reference, providerID: providerID)
            }
        )
    }
}
