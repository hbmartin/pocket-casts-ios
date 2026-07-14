import Testing

/// Serialization umbrella for Swift Testing suites that swap process-wide seams —
/// `KeychainHelper.store`, `DataManager.sharedManager`, `StubFeedURLProtocol.routes`.
/// Top-level suites run in parallel, so two swaps race mid-test (a store swapped to
/// in-memory defeats a failure-injection store; a routes reset drops another suite's
/// stub and the request escapes to the real network). `.serialized` applies
/// recursively, so nesting a suite here (via `extension GlobalSeamSerializedTests`)
/// serializes it against every other nested suite. XCTest classes already run
/// serially and don't need this.
@Suite(.serialized)
enum GlobalSeamSerializedTests {}
