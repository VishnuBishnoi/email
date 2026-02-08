import Testing
@testable import PrivateMailFeature

@Suite("DraftUseCases")
@MainActor
struct DraftUseCaseTests {

    @Test("SaveDraftUseCase marks as draft and persists")
    func saveDraft() async throws {
        let repo = MockEmailRepository()
        let sut = SaveDraftUseCase(repository: repo)

        let email = Email(
            accountId: "acc",
            threadId: "thread",
            messageId: "<msg>",
            fromAddress: "me@example.com",
            subject: "Draft"
        )
        email.isDraft = false
        email.sendState = SendState.queued.rawValue

        _ = try await sut.execute(email)

        #expect(email.isDraft)
        #expect(email.sendState == SendState.none.rawValue)
        #expect(repo.saveEmailCallCount == 1)
    }

    @Test("DeleteDraftUseCase deletes by id")
    func deleteDraft() async throws {
        let repo = MockEmailRepository()
        let sut = DeleteDraftUseCase(repository: repo)

        let email = Email(
            id: "draft-id",
            accountId: "acc",
            threadId: "thread",
            messageId: "<msg>",
            fromAddress: "me@example.com",
            subject: "Draft"
        )
        repo.emails = [email]

        try await sut.execute(emailId: "draft-id")

        #expect(repo.deleteEmailCallCount == 1)
        #expect(repo.emails.isEmpty)
    }
}
