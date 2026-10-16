import XCTest
@testable import MacshCore

/// Real Nextcloud (started by scripts/ci/start-nextcloud.sh) through the WebDAV backend.
@MainActor
final class NextcloudIntegrationTests: XCTestCase {
    private func run(_ proto: MountProtocol) async throws {
        let e = try IntegrationEnv.require("MACSH_IT_NEXTCLOUD_URL", "MACSH_IT_NEXTCLOUD_USER", "MACSH_IT_NEXTCLOUD_PASS")
        let (url, user, pass) = (e["MACSH_IT_NEXTCLOUD_URL"]!, e["MACSH_IT_NEXTCLOUD_USER"]!, e["MACSH_IT_NEXTCLOUD_PASS"]!)
        let backend = Backend.rclone(BackendDescriptor.webdav.makeConfig(
            values: ["url": url, "vendor": "nextcloud", "user": user], remotePath: ""))
        try await IntegrationHarness.roundTrip(
            self, backend: backend, secrets: .init(options: ["pass": pass]), proto: proto,
            label: "nextcloud-\(proto.rawValue)"
        ) { file in
            var req = URLRequest(url: URL(string: url + file)!)
            let token = Data("\(user):\(pass)".utf8).base64EncodedString()
            req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    func testNextcloudNFSRoundTrip() async throws { try await run(.nfs) }
    func testNextcloudWebDAVRoundTrip() async throws { try await run(.webdav) }
}
