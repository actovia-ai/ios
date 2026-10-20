import Foundation
import Testing

@testable import NetworkingKit

@Suite("PairedComputers")
struct PairedComputersTests {
    private func server(_ fingerprint: String, name: String = "Mac", token: String = "T") -> PairedServer {
        PairedServer(
            hosts: ["10.0.0.2"], port: 63129, fingerprint: fingerprint, name: name, deviceId: "d", token: token)
    }

    @Test("pairing adds a computer and makes it current; the same computer again replaces its entry")
    func upsert() {
        var computers = PairedComputers()
        computers.upsert(server("A", name: "Mac mini"))
        computers.upsert(server("B", name: "MacBook"))
        #expect(computers.servers.map(\.fingerprint) == ["A", "B"])
        #expect(computers.active?.fingerprint == "B")

        computers.upsert(server("A", name: "Mac mini", token: "NEW"))
        #expect(computers.servers.map(\.fingerprint) == ["A", "B"])
        #expect(computers.active?.token == "NEW")
    }

    @Test("select switches only to a paired computer")
    func select() {
        var computers = PairedComputers(servers: [server("A"), server("B")], activeFingerprint: "A")
        let switched = computers.select("B")
        #expect(switched)
        #expect(computers.active?.fingerprint == "B")
        let unknown = computers.select("Z")
        #expect(!unknown)
        #expect(computers.active?.fingerprint == "B")
    }

    @Test("removing the current computer hands over to the next; removing another keeps the current one")
    func remove() {
        var computers = PairedComputers(servers: [server("A"), server("B"), server("C")], activeFingerprint: "B")
        computers.remove("A")
        #expect(computers.active?.fingerprint == "B")
        computers.remove("B")
        #expect(computers.active?.fingerprint == "C")
        computers.remove("C")
        #expect(computers.isEmpty)
        #expect(computers.active == nil)
    }

    @Test("the Keychain item reads as a list, or as the single computer stored before there could be more")
    func decode() throws {
        let list = PairedComputers(servers: [server("A"), server("B")], activeFingerprint: "B")
        #expect(try PairedComputers.decode(JSONEncoder().encode(list)) == list)

        let single = try PairedComputers.decode(JSONEncoder().encode(server("A")))
        #expect(single.servers.map(\.fingerprint) == ["A"])
        #expect(single.active?.fingerprint == "A")

        #expect(throws: (any Error).self) { try PairedComputers.decode(Data("{}".utf8)) }
    }
}
