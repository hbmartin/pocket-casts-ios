public protocol ErrorLogger: Sendable {
    func log(error: Error, context: [String: String]?)
}
