import Foundation

/// A secret rclone option of a generic backend. The value lives in the Keychain and
/// reaches rclone through `RCLONE_CONFIG_R_<NAME>`; the on-disk config never has it.
public struct RcloneSecretOption: Codable, Equatable {
    public var name: String
    /// rclone expects the value in its obscured form (`rclone obscure`), like passwords.
    public var obscure: Bool

    public init(name: String, obscure: Bool) {
        self.name = name
        self.obscure = obscure
    }
}

/// Generic rclone backend: a backend `type`, its plain options and the names of its
/// secret options. New backends are declared as data (`BackendDescriptor`) rather than
/// by adding another case and `switch` arms throughout the app.
public struct RcloneBackendConfig: Codable, Equatable {
    /// rclone backend type, e.g. "webdav".
    public var type: String
    /// Non-secret options written to the temporary rclone config.
    public var options: [String: String]
    public var secretOptions: [RcloneSecretOption]
    /// Path inside the remote handed to `rclone serve` (`r:<remotePath>`). May be empty.
    public var remotePath: String

    public init(type: String, options: [String: String], secretOptions: [RcloneSecretOption], remotePath: String) {
        self.type = type
        self.options = options
        self.secretOptions = secretOptions
        self.remotePath = remotePath
    }
}
