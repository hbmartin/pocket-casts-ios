import UIKit
import SwiftUI
import PocketCastsUtils

/// An Activity Provider used for the share sheet
///
/// Given stories assets are generated in the main thread
/// and when the user taps "Share" we use this provider to
/// avoid blocking the main thread and the share sheet
/// having a delay when appearing.
public class StoryShareableProvider: UIActivityItemProvider, @unchecked Sendable {
    private static let sharedLock = NSLock()
    // nonisolated(unsafe): guarded by `sharedLock`.
    nonisolated(unsafe) private static var sharedStorage = StoryShareableProvider()

    public static var shared: StoryShareableProvider {
        sharedLock.lock()
        defer { sharedLock.unlock() }

        return sharedStorage
    }

    private let lock = NSLock()
    private var generatedItemStorage: Any?
    private var viewStorage: AnyView?

    public var generatedItem: Any? {
        get {
            lock.lock()
            defer { lock.unlock() }

            return generatedItemStorage
        }
        set {
            lock.lock()
            generatedItemStorage = newValue
            lock.unlock()
        }
    }

    public var view: AnyView? {
        get {
            lock.lock()
            defer { lock.unlock() }

            return viewStorage
        }
        set {
            lock.lock()
            viewStorage = newValue
            lock.unlock()
        }
    }

    public static func new(_ view: AnyView) -> StoryShareableProvider {
        let provider = StoryShareableProvider()
        provider.view = view

        sharedLock.lock()
        sharedStorage = provider
        sharedLock.unlock()

        return provider
    }

    public init() {
        super.init(placeholderItem: UIImage())
    }

    override public var item: Any {
        generatedItem ?? UIImage()
    }

    // This method is called when the share sheet appeared
    // So we can go ahead and snapshot the view
    @MainActor
    public func snapshot(viewModifier: (AnyView) -> some View) {
        guard let view else {
            return
        }

        let snapshot = AnyView(view)
        .modify(viewModifier)
        .environment(\.renderForSharing, true)
        .frame(width: 450, height: 800)
        .ignoresSafeArea()
        .snapshotUIKit()

        generatedItem = snapshot
        self.view = nil
    }
}

extension EnvironmentValues {
    public var renderForSharing: Bool {
        get { self[RenderSharingKey.self] }
        set { self[RenderSharingKey.self] = newValue }
    }

    private struct RenderSharingKey: EnvironmentKey {
        static let defaultValue: Bool = false
    }
}
