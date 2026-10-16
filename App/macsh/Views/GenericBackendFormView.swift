import SwiftUI
import MacshCore

/// Form state for any backend declared as a `BackendDescriptor` (WebDAV, ...).
struct GenericFormDraft {
    var descriptor: BackendDescriptor
    var name: String = ""
    var values: [String: String]
    var remotePath: String
    var autoMount: Bool = true
    var liveUpdates: Bool = true
    var mountProtocol: MountProtocol = .webdav
    var existingRemoteID: UUID? = nil

    init(descriptor: BackendDescriptor) {
        self.descriptor = descriptor
        self.values = descriptor.defaultValues
        self.remotePath = descriptor.defaultRemotePath
    }

    init(editing remote: Remote, descriptor: BackendDescriptor) {
        self.init(descriptor: descriptor)
        self.existingRemoteID = remote.id
        self.name = remote.name
        self.autoMount = remote.autoMount
        self.liveUpdates = remote.liveUpdates
        self.mountProtocol = remote.mountProtocol
        if case .rclone(let cfg) = remote.backend {
            for (k, v) in cfg.options { values[k] = v }
            remotePath = cfg.remotePath
        }
    }

    func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name required" }
        return descriptor.validate(values: values, isEditing: existingRemoteID != nil)
    }

    func toRemoteAndSecrets() -> (Remote, [String: String]) {
        let remote = Remote(
            id: existingRemoteID ?? UUID(),
            name: name,
            backend: .rclone(descriptor.makeConfig(
                values: values,
                remotePath: remotePath.trimmingCharacters(in: .whitespaces))),
            mountProtocol: mountProtocol,
            autoMount: autoMount,
            liveUpdates: liveUpdates
        )
        return (remote, descriptor.secretValues(from: values))
    }
}

struct GenericBackendFormView: View {
    @Binding var draft: GenericFormDraft

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0 })
    }

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Name") {
                    TextField("", text: $draft.name, prompt: Text("My \(draft.descriptor.displayName)"))
                        .textFieldStyle(.roundedBorder)
                }
                ForEach(draft.descriptor.fields, id: \.key) { field in
                    LabeledContent(field.label) { fieldControl(field) }
                }
                LabeledContent(draft.descriptor.remotePathLabel) {
                    TextField("", text: $draft.remotePath,
                              prompt: Text(draft.descriptor.remotePathPlaceholder))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Mount") {
                LabeledContent("Protocol") {
                    Picker("", selection: $draft.mountProtocol) {
                        Text("WebDAV").tag(MountProtocol.webdav)
                        Text("NFS").tag(MountProtocol.nfs)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                LabeledContent("Options") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Mount automatically at login", isOn: $draft.autoMount)
                        Toggle("Live updates", isOn: $draft.liveUpdates)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func fieldControl(_ field: BackendField) -> some View {
        switch field.kind {
        case .secret:
            SecureField("", text: binding(field.key),
                        prompt: Text(draft.existingRemoteID != nil ? "Leave blank to keep" : field.placeholder))
                .textFieldStyle(.roundedBorder)
        case .choice(let options):
            Picker("", selection: binding(field.key)) {
                ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .labelsHidden()
        case .text, .url:
            TextField("", text: binding(field.key), prompt: Text(field.placeholder))
                .textFieldStyle(.roundedBorder)
        }
    }
}
