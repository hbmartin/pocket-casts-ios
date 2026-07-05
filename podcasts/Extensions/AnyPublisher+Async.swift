import Combine
import PocketCastsUtils

extension AnyPublisher where Failure == Never {
    func awaitFirstValue(in set: inout Set<AnyCancellable>) async -> Output {
        // The first value is delivered once and handed over wholesale
        let boxed: PocketCastsUtils.UncheckedSendable<Output> = await withCheckedContinuation { continuation in
            self
                .first()
                .sink { value in
                    continuation.resume(returning: PocketCastsUtils.UncheckedSendable(value))
                }
                .store(in: &set)
        }
        return boxed.value
    }
}

extension AnyPublisher {
    func awaitFirstValue(in set: inout Set<AnyCancellable>) async throws -> Output {
        let boxed: PocketCastsUtils.UncheckedSendable<Output> = try await withCheckedThrowingContinuation { continuation in
            self
                .first()
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .finished:
                        ()
                    }
                }, receiveValue: { value in
                    continuation.resume(returning: PocketCastsUtils.UncheckedSendable(value))
                })
                .store(in: &set)
        }
        return boxed.value
    }
}
