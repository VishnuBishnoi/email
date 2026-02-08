import Foundation

@MainActor
public protocol DeleteDraftUseCaseProtocol {
    func execute(emailId: String) async throws
}

@MainActor
public final class DeleteDraftUseCase: DeleteDraftUseCaseProtocol {
    private let repository: EmailRepositoryProtocol

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    public func execute(emailId: String) async throws {
        try await repository.deleteEmail(id: emailId)
    }
}
