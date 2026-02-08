import Testing
@testable import PrivateMailFeature

@Suite("Participant Model Tests")
struct ParticipantTests {

    @Test("Decode valid JSON with name and email")
    func decodeValidJSON() {
        let json = """
        [{"name":"John Doe","email":"john@example.com"},{"name":"Sarah","email":"sarah@example.com"}]
        """
        let participants = Participant.decode(from: json)
        #expect(participants.count == 2)
        #expect(participants[0].name == "John Doe")
        #expect(participants[0].email == "john@example.com")
        #expect(participants[1].name == "Sarah")
        #expect(participants[1].email == "sarah@example.com")
    }

    @Test("Decode JSON with null name")
    func decodeNullName() {
        let json = """
        [{"name":null,"email":"anon@example.com"}]
        """
        let participants = Participant.decode(from: json)
        #expect(participants.count == 1)
        #expect(participants[0].name == nil)
        #expect(participants[0].email == "anon@example.com")
    }

    @Test("Decode nil input returns empty array")
    func decodeNilInput() {
        let participants = Participant.decode(from: nil)
        #expect(participants.isEmpty)
    }

    @Test("Decode empty string returns empty array")
    func decodeEmptyString() {
        let participants = Participant.decode(from: "")
        #expect(participants.isEmpty)
    }

    @Test("Decode malformed JSON returns empty array")
    func decodeMalformedJSON() {
        let participants = Participant.decode(from: "not valid json{}")
        #expect(participants.isEmpty)
    }

    @Test("Decode empty array JSON returns empty array")
    func decodeEmptyArrayJSON() {
        let participants = Participant.decode(from: "[]")
        #expect(participants.isEmpty)
    }

    @Test("Encode and decode round-trip")
    func encodeDecodeRoundTrip() {
        let original = [
            Participant(name: "Alice", email: "alice@test.com"),
            Participant(name: nil, email: "bob@test.com")
        ]
        let encoded = Participant.encode(original)
        let decoded = Participant.decode(from: encoded)
        #expect(decoded == original)
    }

    @Test("Display name returns name when available")
    func displayNameWithName() {
        let p = Participant(name: "John Doe", email: "john@example.com")
        #expect(p.displayName == "John Doe")
    }

    @Test("Display name returns email prefix when name is nil")
    func displayNameWithNilName() {
        let p = Participant(name: nil, email: "john@example.com")
        #expect(p.displayName == "john")
    }

    @Test("Display name returns email prefix when name is empty")
    func displayNameWithEmptyName() {
        let p = Participant(name: "", email: "sarah@test.com")
        #expect(p.displayName == "sarah")
    }

    @Test("Multi-participant decode preserves order")
    func multiParticipantOrder() {
        let json = """
        [{"name":"First","email":"first@test.com"},{"name":"Second","email":"second@test.com"},{"name":"Third","email":"third@test.com"}]
        """
        let participants = Participant.decode(from: json)
        #expect(participants.count == 3)
        #expect(participants[0].name == "First")
        #expect(participants[2].name == "Third")
    }

    @Test("Display name for email without @ returns full email")
    func displayNameNoAtSymbol() {
        let p = Participant(name: nil, email: "localhost")
        #expect(p.displayName == "localhost")
    }

    @Test("Encode empty array returns '[]'")
    func encodeEmptyArray() {
        let result = Participant.encode([])
        #expect(result == "[]")
    }
}
