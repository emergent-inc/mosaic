import Testing
import Foundation

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

// Regression coverage for the mosaic-scope attribution cache used by system.top.
// See https://github.com/emergent-inc/mosaic/issues/5756.
//
// `.serialized` because these tests share the process-global mosaic-top scope
// cache (`MosaicTopProcessSnapshot.cachedMosaicScope` / `pruneMosaicScopeCache`); they
// must not interleave with each other.
@Suite(.serialized)
struct MosaicTopSnapshotScopeCacheTests {
    // ~1s, well within the negative TTL.
    static let nowNanoseconds: UInt64 = 1_000_000_000
    // ~1000s later, beyond any sane negative TTL, so the negative entry expires.
    static let farFutureNanoseconds: UInt64 = 1_000_000_000_000

    // Before the fix, a process with no mosaic scope was a permanent cache miss, so
    // every system.top poll re-ran the 3-sysctl probe for every non-mosaic process
    // on the machine. The negative result must now be cached within the TTL.
    @Test func negativeScopeResultIsCachedWithinTTL() {
        MosaicTopProcessSnapshot.pruneMosaicScopeCache(activeKeys: [])
        let cacheKey = MosaicTopProcessScopeCacheKey(
            pid: 901_001,
            startSeconds: 1_700_000_001,
            startMicroseconds: 11
        )
        var probeCount = 0
        let probe: (Int, MosaicTopProcessScopeCacheKey) -> MosaicTopProcessScopeProbeResult = { _, _ in
            probeCount += 1
            return .resolved(nil)
        }

        let first = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_001, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        let second = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_001, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)

        #expect(first == nil)
        #expect(second == nil)
        #expect(probeCount == 1, "non-mosaic process should be probed once per TTL, not on every poll")
    }

    @Test func positiveScopeResultIsCachedAcrossPolls() {
        MosaicTopProcessSnapshot.pruneMosaicScopeCache(activeKeys: [])
        let cacheKey = MosaicTopProcessScopeCacheKey(
            pid: 901_002,
            startSeconds: 1_700_000_002,
            startMicroseconds: 22
        )
        let expected = MosaicTopProcessScope(
            workspaceID: UUID(uuidString: "99999999-9999-9999-9999-999999999999"),
            surfaceID: nil,
            attributionReason: "mosaic-environment"
        )
        var probeCount = 0
        let probe: (Int, MosaicTopProcessScopeCacheKey) -> MosaicTopProcessScopeProbeResult = { _, _ in
            probeCount += 1
            return .resolved(expected)
        }

        // A discovered scope is cached indefinitely, even far past the negative TTL.
        let first = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_002, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        let second = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_002, cacheKey: cacheKey, nowNanoseconds: Self.farFutureNanoseconds, probe: probe)

        #expect(first == expected)
        #expect(second == expected)
        #expect(probeCount == 1)
    }

    // A transient read failure (process exited mid-probe, pid reuse, failed
    // sysctl) must not be cached as a nil, so the next poll retries and can still
    // attribute a live mosaic process.
    @Test func transientProbeFailureIsNotCachedAndRetries() {
        MosaicTopProcessSnapshot.pruneMosaicScopeCache(activeKeys: [])
        let cacheKey = MosaicTopProcessScopeCacheKey(
            pid: 901_003,
            startSeconds: 1_700_000_003,
            startMicroseconds: 33
        )
        let expected = MosaicTopProcessScope(
            workspaceID: nil,
            surfaceID: UUID(uuidString: "abababab-abab-abab-abab-abababababab"),
            attributionReason: "mosaic-environment"
        )
        var probeCount = 0
        let probe: (Int, MosaicTopProcessScopeCacheKey) -> MosaicTopProcessScopeProbeResult = { _, _ in
            probeCount += 1
            // Fail the first two polls, then resolve.
            return probeCount < 3 ? .unavailable : .resolved(expected)
        }

        let first = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_003, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        let second = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_003, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        let third = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_003, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        let fourth = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_003, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)

        #expect(first == nil)
        #expect(second == nil)
        #expect(third == expected)
        #expect(fourth == expected, "resolved scope should now be cached")
        #expect(probeCount == 3, "transient failures retry; the resolved result is cached")
    }

    // The cache key is (pid, process start time), which an `exec` does not change.
    // A process first sampled in its fork-before-exec window, or one that execs
    // into a mosaic-scoped command later, must be re-probed once the negative TTL
    // elapses so it is eventually attributed (https://github.com/emergent-inc/mosaic/issues/5756).
    @Test func negativeScopeIsReprobedAfterTTLExpiry() {
        MosaicTopProcessSnapshot.pruneMosaicScopeCache(activeKeys: [])
        let cacheKey = MosaicTopProcessScopeCacheKey(
            pid: 901_004,
            startSeconds: 1_700_000_004,
            startMicroseconds: 44
        )
        let postExecScope = MosaicTopProcessScope(
            workspaceID: UUID(uuidString: "12121212-1212-1212-1212-121212121212"),
            surfaceID: nil,
            attributionReason: "mosaic-environment"
        )
        var probeCount = 0
        var resolvedScope: MosaicTopProcessScope?
        let probe: (Int, MosaicTopProcessScopeCacheKey) -> MosaicTopProcessScopeProbeResult = { _, _ in
            probeCount += 1
            return .resolved(resolvedScope)
        }

        // Sampled pre-exec: no scope yet, cached negative.
        let preExec = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_004, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        // Polled again within the TTL: served from the negative cache, no re-probe.
        let withinTTL = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_004, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        #expect(preExec == nil)
        #expect(withinTTL == nil)
        #expect(probeCount == 1)

        // Process has since execed into a mosaic-scoped command; after the TTL the
        // negative entry expires and the next poll re-probes and attributes it.
        resolvedScope = postExecScope
        let afterExpiry = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_004, cacheKey: cacheKey, nowNanoseconds: Self.farFutureNanoseconds, probe: probe)
        #expect(afterExpiry == postExecScope)
        #expect(probeCount == 2, "expired negative entry must be re-probed")
    }

    // capture() runs concurrently. A slower sample that probed a process before
    // it execed (resolving nil) must not, on its delayed write, clobber a
    // positive scope that a faster overlapping sample already discovered.
    @Test func negativeProbeDoesNotClobberConcurrentlyDiscoveredPositive() {
        MosaicTopProcessSnapshot.pruneMosaicScopeCache(activeKeys: [])
        let cacheKey = MosaicTopProcessScopeCacheKey(
            pid: 901_005,
            startSeconds: 1_700_000_005,
            startMicroseconds: 55
        )
        let positive = MosaicTopProcessScope(
            workspaceID: UUID(uuidString: "13131313-1313-1313-1313-131313131313"),
            surfaceID: nil,
            attributionReason: "mosaic-environment"
        )
        // This (older) sample resolves nil, but simulates a concurrent capture
        // discovering and caching the positive scope while the probe is in flight.
        let probe: (Int, MosaicTopProcessScopeCacheKey) -> MosaicTopProcessScopeProbeResult = { pid, key in
            _ = MosaicTopProcessSnapshot.cachedMosaicScope(
                for: pid, cacheKey: key, nowNanoseconds: Self.nowNanoseconds) { _, _ in .resolved(positive) }
            return .resolved(nil)
        }

        let result = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_005, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds, probe: probe)
        #expect(result == positive, "stale negative must not clobber a concurrently discovered positive")

        // The positive entry survives for later polls.
        let nextPoll = MosaicTopProcessSnapshot.cachedMosaicScope(
            for: 901_005, cacheKey: cacheKey, nowNanoseconds: Self.nowNanoseconds) { _, _ in .resolved(nil) }
        #expect(nextPoll == positive)
    }
}
