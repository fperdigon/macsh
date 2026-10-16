import Foundation

/// One input of a generic backend form.
public struct BackendField: Equatable {
    public enum Kind: Equatable {
        case text
        case url            // must be http:// or https://
        case secret         // stored in the Keychain, never in the config file
        case choice([String])
    }

    /// rclone option name (also the Keychain item name for secrets).
    public let key: String
    public let label: String
    public let kind: Kind
    public let required: Bool
    public let defaultValue: String
    public let placeholder: String
    /// Secrets only: value must be passed to rclone obscured.
    public let obscure: Bool

    public init(
        key: String, label: String, kind: Kind = .text, required: Bool = false,
        defaultValue: String = "", placeholder: String = "", obscure: Bool = false
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.obscure = obscure
    }

    public var isSecret: Bool { kind == .secret }
}

/// Declares an rclone backend: which fields the form shows and which of them are
/// secrets. Drives validation, `RcloneBackendConfig` creation and the generic form.
public struct BackendDescriptor: Equatable {
    /// rclone backend type, e.g. "webdav".
    public let type: String
    public let displayName: String
    public let fields: [BackendField]
    public let remotePathLabel: String
    public let remotePathPlaceholder: String
    public let defaultRemotePath: String

    public init(
        type: String, displayName: String, fields: [BackendField],
        remotePathLabel: String = "Path", remotePathPlaceholder: String = "", defaultRemotePath: String = ""
    ) {
        self.type = type
        self.displayName = displayName
        self.fields = fields
        self.remotePathLabel = remotePathLabel
        self.remotePathPlaceholder = remotePathPlaceholder
        self.defaultRemotePath = defaultRemotePath
    }

    /// Initial form values: every field's default.
    public var defaultValues: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.defaultValue) })
    }

    /// Returns a message for the first problem, or nil when `values` are acceptable.
    /// While editing, blank secrets mean "keep the stored one" and are not required.
    public func validate(values: [String: String], isEditing: Bool) -> String? {
        for f in fields {
            let v = (values[f.key] ?? "").trimmingCharacters(in: .whitespaces)
            if v.isEmpty {
                if f.required && !(f.isSecret && isEditing) { return "\(f.label) required" }
                continue
            }
            switch f.kind {
            case .url:
                guard let u = URL(string: v), let scheme = u.scheme?.lowercased(),
                      scheme == "http" || scheme == "https", let host = u.host, !host.isEmpty else {
                    return "\(f.label) must be an http:// or https:// URL"
                }
            case .choice(let allowed):
                if !allowed.contains(v) { return "\(f.label) must be one of: \(allowed.joined(separator: ", "))" }
            case .text, .secret:
                break
            }
        }
        return nil
    }

    /// Splits form values into plain options and secret option names. Empty plain
    /// values are dropped so rclone uses its own default.
    public func makeConfig(values: [String: String], remotePath: String) -> RcloneBackendConfig {
        var options: [String: String] = [:]
        var secrets: [RcloneSecretOption] = []
        for f in fields {
            if f.isSecret {
                secrets.append(RcloneSecretOption(name: f.key, obscure: f.obscure))
            } else if let v = values[f.key]?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                options[f.key] = v
            }
        }
        return RcloneBackendConfig(type: type, options: options, secretOptions: secrets, remotePath: remotePath)
    }

    /// Secret values from the form, keyed by option name (blank ones included).
    public func secretValues(from values: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for f in fields where f.isSecret { out[f.key] = values[f.key] ?? "" }
        return out
    }

    // MARK: - Registry

    /// WebDAV, Nextcloud and ownCloud. Nextcloud users should use an app password.
    public static let webdav = BackendDescriptor(
        type: "webdav",
        displayName: "WebDAV / Nextcloud",
        fields: [
            BackendField(key: "url", label: "URL", kind: .url, required: true,
                         placeholder: "https://cloud.example.com/remote.php/dav/files/USER/"),
            BackendField(key: "vendor", label: "Server", kind: .choice(["nextcloud", "owncloud", "other"]),
                         defaultValue: "nextcloud"),
            BackendField(key: "user", label: "User", required: true, placeholder: "user"),
            BackendField(key: "pass", label: "Password", kind: .secret, required: true,
                         placeholder: "app password", obscure: true),
        ],
        remotePathLabel: "Folder",
        remotePathPlaceholder: "leave empty for the root"
    )

    public static let all: [BackendDescriptor] = [.webdav]

    public static func descriptor(forType type: String) -> BackendDescriptor? {
        all.first { $0.type == type }
    }
}
