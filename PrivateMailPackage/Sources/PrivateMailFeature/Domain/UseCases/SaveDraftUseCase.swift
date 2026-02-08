import Foundation

@MainActor
public protocol SaveDraftUseCaseProtocol {
    @discardableResult
    func execute(_ email: Email) async throws -> Email
}

@MainActor
public final class SaveDraftUseCase: SaveDraftUseCaseProtocol {
    private let repository: EmailRepositoryProtocol

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    @discardableResult
    public func execute(_ email: Email) async throws -> Email {
        email.isDraft = true
        email.sendState = SendState.none.rawValue
        try await repository.saveEmail(email)
        return email
    }
}
