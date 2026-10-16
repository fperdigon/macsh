import XCTest
@testable import MacshCore

/// Real servers started by scripts/ci/start-backends.sh: an sshd (password + key auth),
/// an FTP server and an S3 server. Skipped when the MACSH_IT_* variables are absent.
@MainActor
final class BackendIntegrationTests: XCTestCase {
    private let sftpKeys = ["MACSH_IT_SFTP_PORT", "MACSH_IT_SFTP_USER", "MACSH_IT_SFTP_PASS",
                            "MACSH_IT_SFTP_KEY", "MACSH_IT_SFTP_AUTHKEYS", "MACSH_IT_SFTP_DIR"]

    private func sftpEnv() throws -> (port: Int, user: String, pass: String, key: String, authKeys: String, dir: String) {
        let e = try IntegrationEnv.require(sftpKeys[0], sftpKeys[1], sftpKeys[2], sftpKeys[3], sftpKeys[4], sftpKeys[5])
        return (Int(e[sftpKeys[0]]!)!, e[sftpKeys[1]]!, e[sftpKeys[2]]!, e[sftpKeys[3]]!, e[sftpKeys[4]]!, e[sftpKeys[5]]!)
    }

    private func sftpBackend(_ s: (port: Int, user: String, pass: String, key: String, authKeys: String, dir: String),
                             auth: SFTPAuthKind) -> Backend {
        .sftp(SFTPConfig(host: "127.0.0.1", port: s.port, user: s.user, remotePath: s.dir, authKind: auth))
    }

    // MARK: SFTP

    func testSFTPPasswordNFS() async throws {
        let s = try sftpEnv()
        try await IntegrationHarness.roundTrip(
            self, backend: sftpBackend(s, auth: .password),
            secrets: .init(sftp: SFTPSecrets(password: s.pass, privateKeyPath: nil, keyPassphrase: nil)),
            proto: .nfs, label: "sftp-pw-nfs", serverSide: IntegrationHarness.readLocal(s.dir))
    }

    func testSFTPPasswordWebDAV() async throws {
        let s = try sftpEnv()
        try await IntegrationHarness.roundTrip(
            self, backend: sftpBackend(s, auth: .password),
            secrets: .init(sftp: SFTPSecrets(password: s.pass, privateKeyPath: nil, keyPassphrase: nil)),
            proto: .webdav, label: "sftp-pw-dav", serverSide: IntegrationHarness.readLocal(s.dir))
    }

    func testSFTPKeyFile() async throws {
        let s = try sftpEnv()
        try await IntegrationHarness.roundTrip(
            self, backend: sftpBackend(s, auth: .keyFile),
            secrets: .init(sftp: SFTPSecrets(password: nil, privateKeyPath: s.key, keyPassphrase: nil)),
            proto: .nfs, label: "sftp-key", serverSide: IntegrationHarness.readLocal(s.dir))
    }

    /// App-generated key: macsh creates the pair, the server is told the public half,
    /// and the PEM comes back out of the Keychain at mount time.
    func testSFTPGeneratedKey() async throws {
        let s = try sftpEnv()
        let pair = try SSHKeygen.generateEd25519()
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: s.authKeys))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((pair.publicKeyOpenSSH + "\n").utf8))
        try handle.close()
        try await IntegrationHarness.roundTrip(
            self, backend: sftpBackend(s, auth: .generatedKey),
            secrets: .init(sftp: SFTPSecrets(password: nil, privateKeyPath: pair.privateKeyPEM, keyPassphrase: nil)),
            proto: .webdav, label: "sftp-gen", serverSide: IntegrationHarness.readLocal(s.dir))
    }

    // MARK: FTP

    private func ftp(_ proto: MountProtocol) async throws {
        let e = try IntegrationEnv.require("MACSH_IT_FTP_PORT", "MACSH_IT_FTP_USER", "MACSH_IT_FTP_PASS", "MACSH_IT_FTP_DIR")
        let backend = Backend.ftp(FTPConfig(host: "127.0.0.1", port: Int(e["MACSH_IT_FTP_PORT"]!)!,
                                            user: e["MACSH_IT_FTP_USER"]!, remotePath: "/", tlsMode: .off))
        try await IntegrationHarness.roundTrip(
            self, backend: backend, secrets: .init(ftp: FTPSecrets(password: e["MACSH_IT_FTP_PASS"]!)),
            proto: proto, label: "ftp-\(proto.rawValue)",
            serverSide: IntegrationHarness.readLocal(e["MACSH_IT_FTP_DIR"]!))
    }

    func testFTPNFS() async throws { try await ftp(.nfs) }
    func testFTPWebDAV() async throws { try await ftp(.webdav) }

    // MARK: S3

    private func s3(_ proto: MountProtocol) async throws {
        let e = try IntegrationEnv.require("MACSH_IT_S3_ENDPOINT", "MACSH_IT_S3_ACCESS", "MACSH_IT_S3_SECRET",
                                           "MACSH_IT_S3_BUCKET", "MACSH_IT_S3_DIR")
        let bucket = e["MACSH_IT_S3_BUCKET"]!
        let backend = Backend.s3(S3Config(provider: .other, region: "us-east-1", endpoint: e["MACSH_IT_S3_ENDPOINT"]!,
                                          bucket: bucket, prefix: ""))
        try await IntegrationHarness.roundTrip(
            self, backend: backend,
            secrets: .init(s3: S3Secrets(accessKeyID: e["MACSH_IT_S3_ACCESS"]!, secretAccessKey: e["MACSH_IT_S3_SECRET"]!)),
            proto: proto, label: "s3-\(proto.rawValue)",
            serverSide: IntegrationHarness.readLocal("\(e["MACSH_IT_S3_DIR"]!)/\(bucket)"))
    }

    func testS3NFS() async throws { try await s3(.nfs) }
    func testS3WebDAV() async throws { try await s3(.webdav) }
}
