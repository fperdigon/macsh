import Foundation
import XCTest
@testable import MacshCore

/// A stand-in for the rclone binary: a python script that records its arguments and the
/// RCLONE_CONFIG_* environment, answers `obscure`, and (for `serve`) listens on `--addr`.
struct FakeRclone {
    let binary: URL
    let argsFile: URL

    static func make(in dir: URL) throws -> FakeRclone {
        let argsFile = dir.appendingPathComponent("fake-rclone-args.txt")
        let script = """
        #!/usr/bin/env python3
        import os, socket, sys
        args = sys.argv[1:]
        if args and args[0] == "obscure":
            print("OBS-" + args[1])
            sys.exit(0)
        lines = list(args)
        for k in sorted(os.environ):
            if k.startswith("RCLONE_CONFIG_") or k == "MACSH_TEST_ENV":
                lines.append("ENV:%s=%s" % (k, os.environ[k]))
        with open("\(argsFile.path)", "w") as f:
            f.write("\\n".join(lines))
        if "--addr" in args:
            host, port = args[args.index("--addr") + 1].rsplit(":", 1)
            s = socket.socket()
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((host, int(port)))
            s.listen(5)
            while True:
                c, _ = s.accept()
                c.close()
        """
        let url = dir.appendingPathComponent("fake-rclone")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return FakeRclone(binary: url, argsFile: argsFile)
    }

    static func requirePython() throws {
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        if !candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            throw XCTSkip("python3 not available")
        }
    }

    /// Lines the fake wrote (args, then ENV:... lines). Waits for the script to start.
    func recordedLines(timeout: TimeInterval = 10) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: argsFile, encoding: .utf8), !text.isEmpty {
                return text.components(separatedBy: "\n")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return []
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("macsh-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func makeRemote(
    name: String = "test-remote",
    backend: Backend,
    proto: MountProtocol = .webdav,
    autoMount: Bool = false,
    liveUpdates: Bool = true
) -> Remote {
    Remote(id: UUID(), name: name, backend: backend, mountProtocol: proto,
           autoMount: autoMount, liveUpdates: liveUpdates)
}

func sftpBackend(auth: SFTPAuthKind = .password) -> Backend {
    .sftp(SFTPConfig(host: "example.com", port: 22, user: "alice", remotePath: "/data", authKind: auth))
}

func s3Backend(prefix: String = "pre") -> Backend {
    .s3(S3Config(provider: .aws, region: "us-east-1", endpoint: nil, bucket: "bkt", prefix: prefix))
}

func ftpBackend() -> Backend {
    .ftp(FTPConfig(host: "ftp.example.com", port: 21, user: "bob", remotePath: "/pub", tlsMode: .explicit))
}

func webdavBackend(remotePath: String = "docs") -> Backend {
    .rclone(BackendDescriptor.webdav.makeConfig(
        values: ["url": "https://cloud.example.com/remote.php/dav/files/bob/", "vendor": "nextcloud", "user": "bob", "pass": ""],
        remotePath: remotePath))
}
