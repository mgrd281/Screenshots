// Talks to the App Store Connect API, so the store editions need no Xcode
// account: it lists and creates certificates (scripts/mac-store-signing.sh,
// scripts/iphone-signing.sh), registers the bundle ID, makes the App Store
// provisioning profiles and finds the app's Apple ID (scripts/app-store.sh,
// scripts/iphone-store.sh). Only Foundation and CryptoKit.
//
// It reads the API key from the environment: ASC_KEY_ID, ASC_ISSUER_ID and
// ASC_KEY, the text of the .p8 file.
//
// Usage:
//   swift scripts/asc.swift check
//   swift scripts/asc.swift certificates <folder>
//   swift scripts/asc.swift create-certificate <type> <csr file> <out.cer>
//   swift scripts/asc.swift bundle-id <identifier> <name>
//   swift scripts/asc.swift profile <bundle ID resource id> <certificate id> <name> <out.provisionprofile> [type]
//     (type: MAC_APP_STORE, the default, or IOS_APP_STORE)
//   swift scripts/asc.swift app <bundle identifier>
import CryptoKit
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("asc: \(message)\n".utf8))
    exit(code)
}

/// The API key, read from the environment each time it is needed.
func apiKey() -> (id: String, issuer: String, pem: String) {
    let environment = ProcessInfo.processInfo.environment
    func value(_ name: String) -> String {
        // Pasted secrets sometimes gain carriage returns or spaces.
        let text = (environment[name] ?? "").replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { fail("\(name) is not set") }
        return text
    }
    return (value("ASC_KEY_ID"), value("ASC_ISSUER_ID"), value("ASC_KEY"))
}

// MARK: Token

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A token lasts 20 minutes at most, so each request signs a fresh one.
func token() -> String {
    let api = apiKey()
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: api.pem) else {
        fail("ASC_KEY is not the text of an App Store Connect .p8 key")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header = try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": api.id, "typ": "JWT"])
    let claims = try! JSONSerialization.data(withJSONObject: [
        "iss": api.issuer, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1",
    ] as [String: Any])
    let input = base64URL(header) + "." + base64URL(claims)
    guard let signature = try? key.signature(for: Data(input.utf8)) else { fail("could not sign the token") }
    return input + "." + base64URL(signature.rawRepresentation)
}

// MARK: Requests

typealias JSON = [String: Any]

func call(_ method: String, _ path: String, query: [String: String] = [:], body: JSON? = nil) async -> (Int, JSON) {
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
    if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")
    if let body {
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        return (status, json)
    } catch {
        fail("\(method) \(path): \(error.localizedDescription)")
    }
}

/// The errors Apple sends back, in a line or two.
func describe(_ json: JSON) -> String {
    let errors = json["errors"] as? [JSON] ?? []
    return errors.map { "\($0["title"] ?? "") \($0["detail"] ?? "")" }.joined(separator: "; ")
}

func expect(_ status: Int, _ json: JSON, _ what: String, _ ok: Set<Int> = [200, 201]) {
    guard ok.contains(status) else {
        // 403: the key's role is not allowed to do this. The workflows
        // treat that apart, so it has a code of its own.
        fail("\(what) failed (\(status)): \(describe(json))", code: status == 403 ? 2 : 1)
    }
}

func items(_ json: JSON) -> [JSON] { json["data"] as? [JSON] ?? [] }
func attributes(_ item: JSON) -> JSON { item["attributes"] as? JSON ?? [:] }

func write(base64 text: String?, to path: String) {
    guard let text, let data = Data(base64Encoded: text) else { fail("no content to write to \(path)") }
    FileManager.default.createFile(atPath: path, contents: data)
}

// MARK: Commands

let arguments = Array(CommandLine.arguments.dropFirst())
_ = apiKey()

switch arguments.first ?? "" {
case "check":
    let (status, json) = await call("GET", "/v1/certificates", query: ["limit": "1"])
    expect(status, json, "Reading certificates")
    print("The App Store Connect key works.")

case "certificates" where arguments.count == 2:
    // Every certificate of the team, one file each, named <id>.cer, with a
    // line per certificate: id, type, expiry and name.
    let folder = arguments[1]
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let (status, json) = await call("GET", "/v1/certificates", query: ["limit": "200"])
    expect(status, json, "Listing certificates")
    for item in items(json) {
        guard let id = item["id"] as? String else { continue }
        let a = attributes(item)
        write(base64: a["certificateContent"] as? String, to: "\(folder)/\(id).cer")
        print(id, a["certificateType"] as? String ?? "?", a["expirationDate"] as? String ?? "?", a["name"] as? String ?? "")
    }

case "create-certificate" where arguments.count == 4:
    guard let csr = try? String(contentsOfFile: arguments[2], encoding: .utf8) else { fail("cannot read \(arguments[2])") }
    let body: JSON = ["data": ["type": "certificates",
                               "attributes": ["certificateType": arguments[1], "csrContent": csr]]]
    let (status, json) = await call("POST", "/v1/certificates", body: body)
    expect(status, json, "Creating a \(arguments[1]) certificate")
    let item = json["data"] as? JSON ?? [:]
    write(base64: attributes(item)["certificateContent"] as? String, to: arguments[3])
    print(item["id"] as? String ?? "")

case "bundle-id" where arguments.count == 3:
    // Registered once, as a Mac app; prints its resource id.
    let identifier = arguments[1]
    let (status, json) = await call("GET", "/v1/bundleIds", query: ["filter[identifier]": identifier, "limit": "200"])
    expect(status, json, "Looking up the bundle ID")
    if let found = items(json).first(where: { attributes($0)["identifier"] as? String == identifier }),
       let id = found["id"] as? String {
        print(id)
    } else {
        let body: JSON = ["data": ["type": "bundleIds",
                                   "attributes": ["identifier": identifier, "name": arguments[2], "platform": "MAC_OS"]]]
        let (status, json) = await call("POST", "/v1/bundleIds", body: body)
        expect(status, json, "Registering the bundle ID")
        print((json["data"] as? JSON)?["id"] as? String ?? "")
    }

case "profile" where arguments.count == 5 || arguments.count == 6:
    // The App Store profile for one certificate, on the Mac or the iPhone,
    // made once and then downloaded again while it is still active.
    let (bundleID, certificateID, name, out) = (arguments[1], arguments[2], arguments[3], arguments[4])
    let type = arguments.count == 6 ? arguments[5] : "MAC_APP_STORE"
    let (status, json) = await call("GET", "/v1/profiles",
                                    query: ["filter[name]": name, "filter[profileType]": type, "limit": "200"])
    expect(status, json, "Looking up the profile")
    let named = items(json).filter { attributes($0)["name"] as? String == name }
    if let found = named.first(where: { attributes($0)["profileState"] as? String == "ACTIVE" }) {
        write(base64: attributes(found)["profileContent"] as? String, to: out)
    } else {
        // One Apple made invalid, as it does when the app gains a capability
        // like iCloud, goes first, so the new one can take its name.
        for stale in named {
            guard let id = stale["id"] as? String else { continue }
            let (status, json) = await call("DELETE", "/v1/profiles/\(id)")
            expect(status, json, "Removing the invalid profile", [204])
        }
        let body: JSON = ["data": [
            "type": "profiles",
            "attributes": ["name": name, "profileType": type],
            "relationships": [
                "bundleId": ["data": ["type": "bundleIds", "id": bundleID]],
                "certificates": ["data": [["type": "certificates", "id": certificateID]]],
            ],
        ] as JSON]
        let (status, json) = await call("POST", "/v1/profiles", body: body)
        expect(status, json, "Creating the profile")
        write(base64: attributes(json["data"] as? JSON ?? [:])["profileContent"] as? String, to: out)
    }
    print(out)

case "app" where arguments.count == 2:
    // The app's Apple ID, once its record exists in App Store Connect.
    let (status, json) = await call("GET", "/v1/apps", query: ["filter[bundleId]": arguments[1]])
    expect(status, json, "Looking up the app")
    guard let id = items(json).first(where: { attributes($0)["bundleId"] as? String == arguments[1] })?["id"] as? String
    else { fail("no app with the bundle ID \(arguments[1]) in App Store Connect yet", code: 3) }
    print(id)

default:
    fail("unknown command; see the top of scripts/asc.swift")
}
