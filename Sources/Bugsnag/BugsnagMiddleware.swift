import Vapor
import HTTP

public final class BugsnagMiddleware: Middleware {

    let drop: Droplet
    let configuration: ConfigurationType
    let connectionManager: ConnectionManagerType

    public init(drop: Droplet) throws {
        self.drop = drop
        self.configuration = try Configuration(drop: drop)
        self.connectionManager = ConnectionMananger(drop: drop, config: configuration)
    }

    internal init(connectionManager: ConnectionManagerType) {
        self.drop = connectionManager.drop
        self.configuration = connectionManager.config
        self.connectionManager = connectionManager
    }


    // MARK: - Middleware

    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        do {
            return try next.respond(to: request)
        } catch let error as AbortError {
            if error.metadata?["report"]?.bool ?? true {
                try report(status: error.status, message: error.message, metadata: error.metadata, request: request)
            }
            throw error
        } catch {
            try report(status: .internalServerError, message: Status.internalServerError.reasonPhrase, metadata: nil, request: request)
            throw error
        }
    }


    // MARK: - Private

    private func report(status: Status, message: String, metadata: Node?, request: Request) throws {
        _ = try connectionManager.post(status: status, message: message, metadata: metadata, request: request)
    }
}
