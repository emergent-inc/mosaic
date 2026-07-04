import Foundation
import os

private nonisolated struct MosaicTopProcessSnapshotCacheState {
    var snapshot: MosaicTopProcessSnapshot?
    var includeProcessDetails = false
    var includeMosaicScope = true
}

// libproc snapshots are a short-lived platform bridge shared by the CLI, socket,
// and Task Manager paths; keep the cache here so ownership stays with capture().
private nonisolated let mosaicTopProcessSnapshotCache = OSAllocatedUnfairLock(
    initialState: MosaicTopProcessSnapshotCacheState()
)

nonisolated extension MosaicTopProcessSnapshot {
    static func captureCached(
        includeProcessDetails: Bool = false,
        includeMosaicScope: Bool = true,
        maximumAge: TimeInterval
    ) -> MosaicTopProcessSnapshot {
        let now = Date()
        if let cached = mosaicTopProcessSnapshotCache.withLock({ state -> MosaicTopProcessSnapshot? in
            guard let snapshot = state.snapshot,
                  Self.cachedSnapshotDetailsSatisfy(
                      state.includeProcessDetails,
                      requested: includeProcessDetails
                  ),
                  Self.cachedSnapshotMosaicScopeSatisfies(
                      state.includeMosaicScope,
                      requested: includeMosaicScope
                  ),
                  now.timeIntervalSince(snapshot.sampledAt) <= maximumAge else {
                return nil
            }
            return snapshot
        }) {
            return cached
        }

        let snapshot = capture(
            includeProcessDetails: includeProcessDetails,
            includeMosaicScope: includeMosaicScope
        )
        return mosaicTopProcessSnapshotCache.withLock { state in
            let storeTime = Date()
            if let cached = state.snapshot,
               Self.cachedSnapshotDetailsSatisfy(
                   state.includeProcessDetails,
                   requested: includeProcessDetails
               ),
               Self.cachedSnapshotMosaicScopeSatisfies(
                   state.includeMosaicScope,
                   requested: includeMosaicScope
               ),
               storeTime.timeIntervalSince(cached.sampledAt) <= maximumAge {
                return cached
            }
            state.snapshot = snapshot
            state.includeProcessDetails = includeProcessDetails
            state.includeMosaicScope = includeMosaicScope
            return snapshot
        }
    }

    private static func cachedSnapshotDetailsSatisfy(
        _ cachedIncludesProcessDetails: Bool,
        requested: Bool
    ) -> Bool {
        cachedIncludesProcessDetails || !requested
    }

    private static func cachedSnapshotMosaicScopeSatisfies(
        _ cachedIncludesMosaicScope: Bool,
        requested: Bool
    ) -> Bool {
        cachedIncludesMosaicScope || !requested
    }
}
