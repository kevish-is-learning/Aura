//
//  LyricsCache.swift
//  sexophone
//
//  Concurrency-safe bounded in-memory cache and in-flight request deduplicator.
//

import Foundation

/// Thread-safe actor for caching resolved lyrics and deduplicating network requests.
actor LyricsCache {
    private let capacity: Int
    private var cache: [LyricsLookupKey: LyricsResult] = [:]
    private var insertionOrder: [LyricsLookupKey] = []
    private var inFlightTasks: [LyricsLookupKey: Task<LyricsResult, Error>] = [:]

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    /// Retrieve cached lyrics for a given lookup key.
    func get(for key: LyricsLookupKey) -> LyricsResult? {
        cache[key]
    }

    /// Store a resolved lyrics result in the cache with bounded insertion-order eviction.
    func set(_ result: LyricsResult, for key: LyricsLookupKey) {
        if cache[key] == nil {
            insertionOrder.append(key)
            if insertionOrder.count > capacity {
                let oldestKey = insertionOrder.removeFirst()
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[key] = result
    }

    /// Retrieve an existing in-flight network task if available.
    func inFlightTask(for key: LyricsLookupKey) -> Task<LyricsResult, Error>? {
        inFlightTasks[key]
    }

    /// Register a new in-flight task.
    func setInFlightTask(_ task: Task<LyricsResult, Error>, for key: LyricsLookupKey) {
        inFlightTasks[key] = task
    }

    /// Remove a completed or failed in-flight task.
    func removeInFlightTask(for key: LyricsLookupKey) {
        inFlightTasks.removeValue(forKey: key)
    }

    /// Clear all cached entries and tasks.
    func clear() {
        cache.removeAll()
        insertionOrder.removeAll()
        inFlightTasks.removeAll()
    }
}
