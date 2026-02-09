import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("DownloadAttachmentUseCase")
@MainActor
struct DownloadAttachmentUseCaseTests {

    private static func makeSUT() -> (DownloadAttachmentUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = DownloadAttachmentUseCase(repository: repo)
        return (useCase, repo)
    }

    // MARK: - securityWarning

    @Test("securityWarning returns warning for .exe files")
    func securityWarningExe() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "malware.exe")
        #expect(warning == "This file is a Windows executable.")
    }

    @Test("securityWarning returns warning for .zip files")
    func securityWarningZip() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "archive.zip")
        #expect(warning == "This archive may contain executable files.")
    }

    @Test("securityWarning returns warning for .sh files")
    func securityWarningSh() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "install.sh")
        #expect(warning == "This file can run code on your Mac.")
    }

    @Test("securityWarning returns nil for safe file types")
    func securityWarningNilForSafe() {
        let (sut, _) = Self.makeSUT()
        #expect(sut.securityWarning(for: "document.pdf") == nil)
        #expect(sut.securityWarning(for: "photo.jpg") == nil)
        #expect(sut.securityWarning(for: "readme.txt") == nil)
    }

    @Test("securityWarning handles .tar.gz compound extension")
    func securityWarningTarGz() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "backup.tar.gz")
        #expect(warning == "This archive may contain executable files.")
    }

    // MARK: - requiresCellularWarning

    @Test("requiresCellularWarning returns true for >= 25MB")
    func cellularWarningTrue() {
        let (sut, _) = Self.makeSUT()
        let threshold = 25 * 1024 * 1024
        #expect(sut.requiresCellularWarning(sizeBytes: threshold) == true)
        #expect(sut.requiresCellularWarning(sizeBytes: threshold + 1) == true)
    }

    @Test("requiresCellularWarning returns false for < 25MB")
    func cellularWarningFalse() {
        let (sut, _) = Self.makeSUT()
        let threshold = 25 * 1024 * 1024
        #expect(sut.requiresCellularWarning(sizeBytes: threshold - 1) == false)
        #expect(sut.requiresCellularWarning(sizeBytes: 0) == false)
        #expect(sut.requiresCellularWarning(sizeBytes: 1024) == false)
    }
}
