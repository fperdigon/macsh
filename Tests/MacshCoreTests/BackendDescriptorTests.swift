import XCTest
@testable import MacshCore

final class BackendDescriptorTests: XCTestCase {
    private let d = BackendDescriptor.webdav
    private let valid = ["url": "https://cloud.example.com/remote.php/dav/files/bob/",
                         "vendor": "nextcloud", "user": "bob", "pass": "secret"]

    func testRegistryFindsWebDAVByType() {
        XCTAssertEqual(BackendDescriptor.descriptor(forType: "webdav"), .webdav)
        XCTAssertNil(BackendDescriptor.descriptor(forType: "nope"))
        XCTAssertTrue(BackendDescriptor.all.contains(.webdav))
    }

    func testDefaultValuesComeFromFields() {
        XCTAssertEqual(d.defaultValues["vendor"], "nextcloud")
        XCTAssertEqual(d.defaultValues["url"], "")
    }

    func testValidInputPasses() {
        XCTAssertNil(d.validate(values: valid, isEditing: false))
    }

    func testRequiredFieldsReported() {
        var v = valid; v["user"] = "  "
        XCTAssertEqual(d.validate(values: v, isEditing: false), "User required")
        v = valid; v["url"] = ""
        XCTAssertEqual(d.validate(values: v, isEditing: false), "URL required")
        v = valid; v["pass"] = ""
        XCTAssertEqual(d.validate(values: v, isEditing: false), "Password required")
    }

    func testBlankSecretAllowedOnlyWhenEditing() {
        var v = valid; v["pass"] = ""
        XCTAssertNil(d.validate(values: v, isEditing: true))
        v["user"] = ""
        XCTAssertEqual(d.validate(values: v, isEditing: true), "User required")
    }

    func testURLMustBeHTTP() {
        for bad in ["cloud.example.com", "ftp://cloud.example.com/x", "https://", "not a url"] {
            var v = valid; v["url"] = bad
            XCTAssertEqual(d.validate(values: v, isEditing: false),
                           "URL must be an http:// or https:// URL", bad)
        }
        var v = valid; v["url"] = "http://192.168.1.5:8080/dav"
        XCTAssertNil(d.validate(values: v, isEditing: false))
    }

    func testChoiceMustBeOneOfAllowed() {
        var v = valid; v["vendor"] = "dropbox"
        XCTAssertEqual(d.validate(values: v, isEditing: false),
                       "Server must be one of: nextcloud, owncloud, other")
    }

    func testMakeConfigSplitsSecretsFromOptions() {
        let cfg = d.makeConfig(values: valid, remotePath: "docs")
        XCTAssertEqual(cfg.type, "webdav")
        XCTAssertEqual(cfg.options, ["url": valid["url"]!, "vendor": "nextcloud", "user": "bob"])
        XCTAssertNil(cfg.options["pass"], "secret must never be a plain option")
        XCTAssertEqual(cfg.secretOptions, [RcloneSecretOption(name: "pass", obscure: true)])
        XCTAssertEqual(cfg.remotePath, "docs")
    }

    func testMakeConfigDropsEmptyAndTrims() {
        var v = valid; v["vendor"] = ""; v["user"] = " bob "
        let cfg = d.makeConfig(values: v, remotePath: "")
        XCTAssertNil(cfg.options["vendor"])
        XCTAssertEqual(cfg.options["user"], "bob")
    }

    func testSecretValuesOnlyIncludeSecretFields() {
        XCTAssertEqual(d.secretValues(from: valid), ["pass": "secret"])
        XCTAssertEqual(d.secretValues(from: [:]), ["pass": ""])
    }

    func testBackendRoundTripsThroughJSONAndRemote() throws {
        let remote = makeRemote(backend: webdavBackend())
        let data = try JSONEncoder().encode(remote)
        XCTAssertEqual(try JSONDecoder().decode(Remote.self, from: data), remote)
    }

    func testExistingBackendsStillDecodeFromLegacyJSON() throws {
        let remote = makeRemote(backend: ftpBackend())
        let data = try JSONEncoder().encode([remote])
        XCTAssertEqual(try JSONDecoder().decode([Remote].self, from: data), [remote])
    }

    func testSecretKindOptionIsDistinctFromBuiltIns() {
        XCTAssertEqual(SecretKind.option("pass").rawValue, "option.pass")
        XCTAssertNotEqual(SecretKind.option("password"), SecretKind.password)
        XCTAssertEqual(SecretKind.password.rawValue, "password", "existing Keychain items must keep resolving")
    }
}

final class GoogleDriveDescriptorTests: XCTestCase {
    private let d = BackendDescriptor.googleDrive
    private let token = #"{"access_token":"AT","refresh_token":"RT"}"#

    func testRegistryAndOAuthSpec() {
        XCTAssertEqual(BackendDescriptor.descriptor(forType: "drive"), .googleDrive)
        XCTAssertEqual(d.oauth?.backend, "drive")
        XCTAssertEqual(d.oauth?.scopeKey, "scope")
        XCTAssertNil(BackendDescriptor.webdav.oauth)
    }

    func testSignInRequiredUnlessEditing() {
        XCTAssertEqual(d.validate(values: d.defaultValues, isEditing: false), "Account required")
        XCTAssertNil(d.validate(values: d.defaultValues, isEditing: true), "saved sign-in is kept")
        var v = d.defaultValues; v["token"] = token
        XCTAssertNil(d.validate(values: v, isEditing: false))
    }

    func testScopeMustBeAllowed() {
        var v = d.defaultValues; v["token"] = token; v["scope"] = "everything"
        XCTAssertNotNil(d.validate(values: v, isEditing: false))
    }

    func testConfigKeepsTokenAndClientSecretOutOfOptions() {
        var v = d.defaultValues
        v["token"] = token; v["client_id"] = "cid"; v["client_secret"] = "cs"; v["team_drive"] = "TD"
        let cfg = d.makeConfig(values: v, remotePath: "Docs")
        XCTAssertEqual(cfg.type, "drive")
        XCTAssertEqual(cfg.options, ["scope": "drive", "client_id": "cid", "team_drive": "TD"])
        XCTAssertEqual(cfg.secretOptions, [
            RcloneSecretOption(name: "token", obscure: false, required: true, refreshable: true),
            RcloneSecretOption(name: "client_secret", obscure: false, required: false, refreshable: false),
        ])
        XCTAssertEqual(d.secretValues(from: v), ["token": token, "client_secret": "cs"])
    }

    func testSecretOptionDecodesFromOlderJSON() throws {
        let old = Data(#"{"name":"pass","obscure":true}"#.utf8)
        let opt = try JSONDecoder().decode(RcloneSecretOption.self, from: old)
        XCTAssertEqual(opt, RcloneSecretOption(name: "pass", obscure: true, required: true, refreshable: false))
        let round = try JSONDecoder().decode(
            RcloneSecretOption.self,
            from: JSONEncoder().encode(RcloneSecretOption(name: "t", obscure: false, required: false, refreshable: true)))
        XCTAssertEqual(round.refreshable, true)
        XCTAssertEqual(round.required, false)
    }

    func testBuilderRequiresTokenButNotClientSecret() throws {
        let r = makeRemote(backend: driveBackend(clientID: "cid"))
        XCTAssertThrowsError(try RcloneConfigBuilder.build(remote: r, secrets: BackendSecrets())) {
            XCTAssertEqual($0 as? RcloneConfigError, .missingSecret("token"))
        }
        let cfg = try RcloneConfigBuilder.build(remote: r, secrets: BackendSecrets(options: ["token": "T"]))
        XCTAssertEqual(cfg, "[r]\ntype = drive\nclient_id = cid\nscope = drive\n")
        XCTAssertFalse(cfg.contains("token"))
    }
}
