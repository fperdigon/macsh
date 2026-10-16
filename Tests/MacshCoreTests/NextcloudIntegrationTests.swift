import XCTest
@testable import MacshCore

/// End-to-end check against a real Nextcloud: macsh's WebDAV backend -> real rclone ->
/// real macOS mount -> write a file -> read it back from the Nextcloud server.
/// Skipped unless MACSH_IT_NEXTCLOUD_URL / _USER / _PASS are set (the CI job
/// `nextcloud-integration` starts Nextcloud with scripts/ci/start-nextcloud.sh).
@MainActor
final class NextcloudIntegrationTests: XCTestCase {
    private struct Config { let url: String; let user: String; let pass: String }

    private func config() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["MACSH_IT_NEXTCLOUD_URL"], let user = env["MACSH_IT_NEXTCLOUD_USER"],
              let pass = env["MACSH_IT_NEXTCLOUD_PASS"] else {
            throw XCTSkip("MACSH_IT_NEXTCLOUD_* not set")
        }
        return Config(url: url, user: user, pass: pass)
    }

    private func serverContents(of file: String, _ c: Config) async -> String? {
        var req = URLRequest(url: URL(string: c.url + file)!)
        let token = Data("\(c.user):\(c.pass)".utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func roundTrip(proto: MountProtocol) async throws {
        let c = try config()
        let rclone = try RcloneBinary.resolve()
        let dir = try makeTempDir()
        let manager = SessionManager(
            store: RemoteStore(directory: dir),
            keychain: KeychainService(serviceName: "macsh.it.\(UUID().uuidString)"),
            mounter: Mounter(),
            logsDir: dir.appendingPathComponent("logs"),
            rcloneBinary: rclone
        )
        let name = "macsh-it-\(proto.rawValue)-\(Int.random(in: 1000...9999))"
        let backend = Backend.rclone(BackendDescriptor.webdav.makeConfig(
            values: ["url": c.url, "vendor": "nextcloud", "user": c.user], remotePath: ""))
        let remote = Remote(id: UUID(), name: name, backend: backend, mountProtocol: proto, autoMount: false)
        try manager.add(remote, optionSecrets: ["pass": c.pass])

        addTeardownBlock { @MainActor in
            manager.shutdownAll()
            try? manager.delete(remote.id)
            try? FileManager.default.removeItem(at: dir)
        }

        try await manager.mount(remoteID: remote.id)
        guard case .mounted(let mountpoint) = manager.sessions[0].status else {
            return XCTFail("not mounted: \(manager.sessions[0].status)")
        }

        let fileName = "macsh-\(proto.rawValue)-\(UUID().uuidString).txt"
        let payload = "hello from macsh \(UUID().uuidString)"
        try payload.write(toFile: "\(mountpoint)/\(fileName)", atomically: false, encoding: .utf8)
        XCTAssertEqual(try String(contentsOfFile: "\(mountpoint)/\(fileName)", encoding: .utf8), payload)

        // The write goes through rclone's write-back cache; it must reach the server.
        var seen: String?
        for _ in 0..<30 {
            seen = await serverContents(of: fileName, c)
            if seen == payload { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertEqual(seen, payload, "file written through the mount never reached Nextcloud")

        try await manager.unmount(remoteID: remote.id)
        XCTAssertEqual(manager.sessions[0].status, .idle)
    }

    func testNextcloudNFSRoundTrip() async throws { try await roundTrip(proto: .nfs) }
    func testNextcloudWebDAVRoundTrip() async throws { try await roundTrip(proto: .webdav) }
}
