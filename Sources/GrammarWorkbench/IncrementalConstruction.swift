import Foundation

public enum GrammarConstructionReuse: String, Codable, Sendable {
    case none
    case cacheHit
    case coalesced
}

public struct GrammarConstructionPerformance: Hashable, Codable, Sendable {
    public let frontEndMilliseconds: Double
    public let constructionMilliseconds: Double
    public let totalMilliseconds: Double
    public let reuse: GrammarConstructionReuse
    public let stateCount: Int
    public let itemCount: Int
    public let tableEntryCount: Int
}

public struct GrammarCompilerCacheStatistics: Hashable, Codable, Sendable {
    public let capacity: Int
    public let entries: Int
    public let inFlightRequests: Int
    public let hits: Int
    public let misses: Int
    public let coalescedRequests: Int
    public let evictions: Int
}

/// An actor-backed compiler for interactive and server-style clients. Equal
/// requests share in-flight work and reuse a bounded LRU of immutable results.
public actor GrammarWorkbenchIncrementalCompiler {
    private let capacity: Int
    private var cache: [GrammarCompilationRequest: GrammarCompilation] = [:]
    private var recency: [GrammarCompilationRequest] = []
    private var inFlight: [GrammarCompilationRequest: Task<GrammarCompilation, Never>] = [:]
    private var hits = 0
    private var misses = 0
    private var coalescedRequests = 0
    private var evictions = 0

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    public func compile(_ request: GrammarCompilationRequest) async -> GrammarCompilation {
        let deliveryStart = ContinuousClock.now
        if let cached = cache[request] {
            hits += 1
            touch(request)
            return cached.withReuse(.cacheHit, delivery: elapsedMilliseconds(since: deliveryStart))
        }
        if let task = inFlight[request] {
            coalescedRequests += 1
            let result = await task.value
            return result.withReuse(.coalesced, delivery: elapsedMilliseconds(since: deliveryStart))
        }

        misses += 1
        let task = Task.detached(priority: .userInitiated) {
            GrammarWorkbenchAPI.compile(request)
        }
        inFlight[request] = task
        let result = await task.value
        inFlight[request] = nil
        insert(result, for: request)
        return result
    }

    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
    }

    public func statistics() -> GrammarCompilerCacheStatistics {
        .init(
            capacity: capacity, entries: cache.count, inFlightRequests: inFlight.count,
            hits: hits, misses: misses, coalescedRequests: coalescedRequests,
            evictions: evictions
        )
    }

    private func insert(_ compilation: GrammarCompilation, for request: GrammarCompilationRequest) {
        cache[request] = compilation
        touch(request)
        while recency.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
            evictions += 1
        }
    }

    private func touch(_ request: GrammarCompilationRequest) {
        recency.removeAll { $0 == request }
        recency.append(request)
    }
}

func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
    let components = start.duration(to: .now).components
    return Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
}

