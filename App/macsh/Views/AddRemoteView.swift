import SwiftUI
import MacshCore

enum AddBackendKind: String, CaseIterable, Identifiable {
    case sftp, s3, ftp, webdav, gdrive, smb
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sftp: return "SFTP / SSH"
        case .s3:   return "S3-compatible"
        case .ftp:  return "FTP / FTPS"
        case .webdav: return BackendDescriptor.webdav.displayName
        case .gdrive: return BackendDescriptor.googleDrive.displayName
        case .smb: return BackendDescriptor.smb.displayName
        }
    }
}

/// Add/Edit window styled to match the Maccy-style Settings: flat
/// background, grouped form rows with right-aligned labels, prominent
/// primary action. Type picker locks in edit mode so secrets and
/// keychain layout don't drift.
struct AddRemoteView: View {
    let manager: SessionManager
    let prefs: UserPreferences
    let editingRemote: Remote?

    @Environment(\.dismiss) private var dismiss
    @State private var kind: AddBackendKind
    @State private var sftp: SFTPFormDraft
    @State private var s3: S3FormDraft
    @State private var ftp: FTPFormDraft
    @State private var webdav: GenericFormDraft
    @State private var gdrive: GenericFormDraft
    @State private var smb: GenericFormDraft
    @State private var authorizer = OAuthAuthorizer()
    @State private var error: String?
    @State private var customizeTuning: Bool
    @State private var tuning: TransferTuning
    @State private var readOnly: Bool
    @State private var bandwidth: String
    @State private var testing = false
    @State private var testResult: ConnectionTestResult?

    init(manager: SessionManager, prefs: UserPreferences, editing: Remote? = nil) {
        self.manager = manager
        self.prefs = prefs
        self.editingRemote = editing

        var sftpDraft = SFTPFormDraft()
        var s3Draft = S3FormDraft()
        var ftpDraft = FTPFormDraft()
        var webdavDraft = GenericFormDraft(descriptor: .webdav)
        webdavDraft.mountProtocol = prefs.defaultProtocol
        var gdriveDraft = GenericFormDraft(descriptor: .googleDrive)
        gdriveDraft.mountProtocol = prefs.defaultProtocol
        var smbDraft = GenericFormDraft(descriptor: .smb)
        smbDraft.mountProtocol = prefs.defaultProtocol
        sftpDraft.mountProtocol = prefs.defaultProtocol
        s3Draft.mountProtocol = prefs.defaultProtocol
        ftpDraft.mountProtocol = prefs.defaultProtocol

        var initialKind: AddBackendKind = .sftp
        if let r = editing {
            switch r.backend {
            case .sftp: initialKind = .sftp; sftpDraft = SFTPFormDraft(editing: r)
                if sftpDraft.authKind == .keyFile, let path = manager.storedKeyFilePath(for: r.id) {
                    sftpDraft.keyFilePath = path
                }
            case .s3:   initialKind = .s3;   s3Draft   = S3FormDraft(editing: r)
            case .ftp:  initialKind = .ftp;  ftpDraft  = FTPFormDraft(editing: r)
            case .rclone(let cfg):
                if let d = BackendDescriptor.descriptor(forType: cfg.type) {
                    if d.type == BackendDescriptor.googleDrive.type {
                        initialKind = .gdrive
                        gdriveDraft = GenericFormDraft(editing: r, descriptor: d)
                    } else if d.type == BackendDescriptor.smb.type {
                        initialKind = .smb
                        smbDraft = GenericFormDraft(editing: r, descriptor: d)
                    } else {
                        initialKind = .webdav
                        webdavDraft = GenericFormDraft(editing: r, descriptor: d)
                    }
                }
            }
        }
        _kind = State(initialValue: initialKind)
        let proto = editing?.mountProtocol ?? prefs.defaultProtocol
        _customizeTuning = State(initialValue: editing?.tuning != nil)
        _tuning = State(initialValue: editing?.tuning ?? .defaults(for: proto))
        _readOnly = State(initialValue: editing?.readOnly ?? false)
        _bandwidth = State(initialValue: editing?.bandwidthLimit ?? "")
        _sftp = State(initialValue: sftpDraft)
        _s3 = State(initialValue: s3Draft)
        _ftp = State(initialValue: ftpDraft)
        _webdav = State(initialValue: webdavDraft)
        _gdrive = State(initialValue: gdriveDraft)
        _smb = State(initialValue: smbDraft)
    }

    private var isEditing: Bool { editingRemote != nil }

    private var currentProtocol: MountProtocol {
        switch kind {
        case .sftp: return sftp.mountProtocol
        case .s3:   return s3.mountProtocol
        case .ftp:  return ftp.mountProtocol
        case .webdav: return webdav.mountProtocol
        case .gdrive: return gdrive.mountProtocol
        case .smb: return smb.mountProtocol
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    form
                    TuningSection(customize: $customizeTuning, tuning: $tuning, mountProtocol: currentProtocol)
                    MountOptionsSection(readOnly: $readOnly, bandwidth: $bandwidth)
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isEditing ? "Edit remote" : "Add remote")
                .font(.title3.weight(.semibold))
            Spacer()
            Picker("", selection: $kind) {
                ForEach(AddBackendKind.allCases) { k in Text(k.label).tag(k) }
            }
            .labelsHidden()
            .frame(width: 200)
            .disabled(isEditing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var form: some View {
        switch kind {
        case .sftp: SFTPFormView(draft: $sftp)
        case .s3:   S3FormView(draft: $s3)
        case .ftp:  FTPFormView(draft: $ftp)
        case .webdav: GenericBackendFormView(draft: $webdav, prefs: prefs, authorizer: authorizer)
        case .gdrive: GenericBackendFormView(draft: $gdrive, prefs: prefs, authorizer: authorizer)
        case .smb: GenericBackendFormView(draft: $smb, prefs: prefs, authorizer: authorizer)
        }
    }

    private var footer: some View {
        HStack {
            if testing {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.callout).foregroundStyle(.secondary)
            } else if let testResult {
                Label(testResult.message, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(testResult.ok ? .green : .red)
                    .lineLimit(3)
            } else if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Test connection") { testConnection() }
                .disabled(testing)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save changes" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// The form's current values as a remote plus its (unsaved) secrets, or nil after
    /// showing the first validation problem.
    private func currentRemote() -> (Remote, SessionManager.DraftSecrets)? {
        if customizeTuning, let v = tuning.validate() { error = v; return nil }
        if let v = MountOptions.validateBandwidth(bandwidth) { error = v; return nil }
        var remote: Remote
        var draft = SessionManager.DraftSecrets()
        switch kind {
        case .sftp:
            if let v = sftp.validate() { error = v; return nil }
            let (r, secrets) = sftp.toRemoteAndSecrets()
            remote = r; draft.sftp = secrets
        case .s3:
            if let v = s3.validate() { error = v; return nil }
            let (r, secrets) = s3.toRemoteAndSecrets()
            remote = r; draft.s3 = secrets
        case .ftp:
            if let v = ftp.validate() { error = v; return nil }
            let (r, secrets) = ftp.toRemoteAndSecrets()
            remote = r; draft.ftp = secrets
        case .webdav:
            if let v = webdav.validate() { error = v; return nil }
            let (r, secrets) = webdav.toRemoteAndSecrets()
            remote = r; draft.options = secrets
        case .gdrive:
            if let v = gdrive.validate() { error = v; return nil }
            let (r, secrets) = gdrive.toRemoteAndSecrets()
            remote = r; draft.options = secrets
        case .smb:
            if let v = smb.validate() { error = v; return nil }
            let (r, secrets) = smb.toRemoteAndSecrets()
            remote = r; draft.options = secrets
        }
        remote.tuning = customizeTuning ? tuning : nil
        remote.readOnly = readOnly
        let bw = bandwidth.trimmingCharacters(in: .whitespaces)
        remote.bandwidthLimit = bw.isEmpty ? nil : bw
        error = nil
        return (remote, draft)
    }

    private func testConnection() {
        testResult = nil
        guard let (remote, draft) = currentRemote() else { return }
        testing = true
        Task { @MainActor in
            testResult = await manager.testConnection(remote, draft: draft)
            testing = false
        }
    }

    private func save() {
        testResult = nil
        guard let (remote, draft) = currentRemote() else { return }
        do {
            switch kind {
            case .sftp:
                if isEditing { try manager.update(remote, sftpSecrets: draft.sftp) }
                else { try manager.add(remote, sftpSecrets: draft.sftp) }
            case .s3:
                if isEditing { try manager.update(remote, s3Secrets: draft.s3) }
                else { try manager.add(remote, s3Secrets: draft.s3) }
            case .ftp:
                if isEditing { try manager.update(remote, ftpSecrets: draft.ftp) }
                else { try manager.add(remote, ftpSecrets: draft.ftp) }
            case .webdav, .gdrive, .smb:
                if isEditing { try manager.update(remote, optionSecrets: draft.options) }
                else { try manager.add(remote, optionSecrets: draft.options) }
            }
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
