import Foundation
import Testing
@testable import PinkhaTorahCore

private actor TestCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private func makeSampleDocument(ref: String, section: String = "Genesis 1", segmentsCount: Int = 3) -> TorahTextDocument {
    TorahTextDocument(
        providerID: "sefaria-fixture",
        requestedRef: ref,
        canonicalRef: ref,
        hebrewRef: "בראשית",
        sectionRef: section,
        hebrewSectionRef: "בראשית א",
        segments: (1...segmentsCount).map {
            TorahTextSegment(canonicalRef: "\(ref):\($0)", hebrewRef: "פסוק \($0)", text: "פסוק \($0) של \(ref)", ordinal: $0)
        },
        previousSectionRef: nil,
        nextSectionRef: nil,
        version: TorahTextVersionMetadata(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Test", versionTitleInHebrew: "בדיקה", license: "CC0", direction: "rtl"),
        rawProviderPayload: "{}"
    )
}

@Suite("Torah Inspector Repository Single-Flight and Cache")
struct TorahInspectorRepositoryTests {

    @Test @MainActor func simultaneousRequestsPerformSingleProviderFetchAndReturnSameDocument() async throws {
        let fetchCount = TestCounter()
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                _ = await fetchCount.increment()
                try await Task.sleep(for: .milliseconds(50))
                return makeSampleDocument(ref: ref)
            }
        )

        async let req1 = repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        async let req2 = repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")

        let (doc1, doc2) = try await (req1, req2)

        let finalFetchCount = await fetchCount.value()
        #expect(finalFetchCount == 1)
        #expect(doc1.canonicalRef == "Genesis 1:1")
        #expect(doc2.canonicalRef == "Genesis 1:1")
        #expect(doc1.id == doc2.id)
    }

    @Test @MainActor func completedRequestIsServedFromCacheWithoutNewFetch() async throws {
        let fetchCount = TestCounter()
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                _ = await fetchCount.increment()
                return makeSampleDocument(ref: ref)
            }
        )

        _ = try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        let fetchCountAfterFirstRequest = await fetchCount.value()
        #expect(fetchCountAfterFirstRequest == 1)

        let cached = try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        let fetchCountAfterCachedRequest = await fetchCount.value()
        #expect(fetchCountAfterCachedRequest == 1)
        #expect(cached.canonicalRef == "Genesis 1:1")
    }

    @Test @MainActor func sectionAndCanonicalAliasesAreResolvedFromCache() async throws {
        let fetchCount = TestCounter()
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                _ = await fetchCount.increment()
                return makeSampleDocument(ref: "Genesis 1:1-5", section: "Genesis 1")
            }
        )

        _ = try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        let finalFetchCount = await fetchCount.value()
        #expect(finalFetchCount == 1)

        // Requesting by section ref should hit cache
        let bySection = repo.cachedDocument(for: "Genesis 1", providerID: "sefaria-fixture")
        #expect(bySection != nil)
        #expect(bySection?.canonicalRef == "Genesis 1:1-5")

        // Requesting by canonical ref should hit cache
        let byCanonical = repo.cachedDocument(for: "Genesis 1:1-5", providerID: "sefaria-fixture")
        #expect(byCanonical != nil)
    }

    @Test @MainActor func failedRequestIsRemovedFromInFlightAndRetryPerformsNewRequest() async throws {
        let attempt = TestCounter()
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                let currentAttempt = await attempt.increment()
                if currentAttempt == 1 {
                    throw TorahError.network("Connection error")
                }
                return makeSampleDocument(ref: ref)
            }
        )

        // First attempt fails
        do {
            _ = try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
            Issue.record("Expected failure on first attempt")
        } catch {
            let attemptAfterFailure = await attempt.value()
            #expect(attemptAfterFailure == 1)
        }

        // Retry must perform a fresh request
        let retried = try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        let finalAttempt = await attempt.value()
        #expect(finalAttempt == 2)
        #expect(retried.canonicalRef == "Genesis 1:1")
    }

    @Test @MainActor func cancellationOfOneWaiterDoesNotBecomeAlreadyLoadingError() async throws {
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                try await Task.sleep(for: .milliseconds(80))
                return makeSampleDocument(ref: ref)
            }
        )

        let task1 = Task { @MainActor in
            try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        }
        let task2 = Task { @MainActor in
            try await repo.document(for: "Genesis 1:1", providerID: "sefaria-fixture")
        }

        // Cancel task1 shortly after starting
        task1.cancel()

        do {
            _ = try await task1.value
        } catch {
            #expect(error is CancellationError)
        }

        // task2 should still complete successfully
        let result2 = try await task2.value
        #expect(result2.canonicalRef == "Genesis 1:1")
    }

    @Test @MainActor func cacheRemainsBoundedWithinCapacity() async throws {
        let repo = TorahInspectorRepository(
            documentCapacity: 3,
            textFetcher: { ref, _ in
                makeSampleDocument(ref: ref, section: ref)
            }
        )

        _ = try await repo.document(for: "Doc 1", providerID: "sefaria-fixture")
        _ = try await repo.document(for: "Doc 2", providerID: "sefaria-fixture")
        _ = try await repo.document(for: "Doc 3", providerID: "sefaria-fixture")

        #expect(repo.cachedDocument(for: "Doc 1", providerID: "sefaria-fixture") != nil)
        #expect(repo.cachedDocument(for: "Doc 2", providerID: "sefaria-fixture") != nil)
        #expect(repo.cachedDocument(for: "Doc 3", providerID: "sefaria-fixture") != nil)

        // Adding a 4th document must evict Doc 1 (oldest)
        _ = try await repo.document(for: "Doc 4", providerID: "sefaria-fixture")

        #expect(repo.cachedDocument(for: "Doc 1", providerID: "sefaria-fixture") == nil)
        #expect(repo.cachedDocument(for: "Doc 2", providerID: "sefaria-fixture") != nil)
        #expect(repo.cachedDocument(for: "Doc 3", providerID: "sefaria-fixture") != nil)
        #expect(repo.cachedDocument(for: "Doc 4", providerID: "sefaria-fixture") != nil)
    }

    @Test @MainActor func reversingScrollReusesSessionCache() async throws {
        let fetchCount = TestCounter()
        let repo = TorahInspectorRepository(
            documentCapacity: 10,
            textFetcher: { ref, _ in
                _ = await fetchCount.increment()
                return makeSampleDocument(ref: ref, section: ref)
            }
        )

        // User reads sections 1, 2, 3
        _ = try await repo.document(for: "Section 1", providerID: "sefaria-fixture")
        _ = try await repo.document(for: "Section 2", providerID: "sefaria-fixture")
        _ = try await repo.document(for: "Section 3", providerID: "sefaria-fixture")
        let fetchCountAfterForwardScroll = await fetchCount.value()
        #expect(fetchCountAfterForwardScroll == 3)

        // User scrolls back to section 1: served from session cache without new fetches
        _ = try await repo.document(for: "Section 2", providerID: "sefaria-fixture")
        _ = try await repo.document(for: "Section 1", providerID: "sefaria-fixture")
        let fetchCountAfterReverseScroll = await fetchCount.value()
        #expect(fetchCountAfterReverseScroll == 3)
    }
}
