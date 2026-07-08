import MosaicCollaboration
import Testing

@Suite struct CollaborationInboxOrderingTests {
    private func input(_ session: String, _ createdAt: String) -> CollaborationInboxOrderingInput {
        CollaborationInboxOrderingInput(session: session, createdAt: createdAt)
    }

    @Test func ordersNewestFirst() {
        let ordered = CollaborationInboxOrdering.orderNewestFirst([
            input("older", "2026-01-01T00:00:00Z"),
            input("newest", "2026-03-01T00:00:00Z"),
            input("middle", "2026-02-01T00:00:00Z"),
        ])
        #expect(ordered.map(\.session) == ["newest", "middle", "older"])
    }

    @Test func parsesFractionalSecondsTimestamps() {
        let ordered = CollaborationInboxOrdering.orderNewestFirst([
            input("plain", "2026-01-01T00:00:00Z"),
            input("fractional", "2026-01-01T00:00:00.500Z"),
        ])
        #expect(ordered.map(\.session) == ["fractional", "plain"])
    }

    @Test func unparseableTimestampsSortLastPreservingOrder() {
        let ordered = CollaborationInboxOrdering.orderNewestFirst([
            input("bad-a", "not-a-date"),
            input("good", "2026-01-01T00:00:00Z"),
            input("bad-b", ""),
        ])
        #expect(ordered.map(\.session) == ["good", "bad-a", "bad-b"])
    }

    @Test func identicalTimestampsKeepOriginalOrder() {
        let ordered = CollaborationInboxOrdering.orderNewestFirst([
            input("first", "2026-01-01T00:00:00Z"),
            input("second", "2026-01-01T00:00:00Z"),
            input("third", "2026-01-01T00:00:00Z"),
        ])
        #expect(ordered.map(\.session) == ["first", "second", "third"])
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(CollaborationInboxOrdering.orderNewestFirst([]).isEmpty)
    }
}
