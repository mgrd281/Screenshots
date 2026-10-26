// Checks the translations: every L("...") in the code has an entry in each
// language, and no language keeps entries the code no longer uses; and each
// language asks every one of the Mac's permission questions.
// A missing translation is only a warning, because the app shows the English
// text instead. Everything else is an error.
// Usage: swift scripts/check-strings.swift
import Foundation

let sources = URL(fileURLWithPath: "Sources/Tendedero")
let resources = sources.appendingPathComponent("Resources")
// The iPhone app and its share extension share the translations.
let iPhone = URL(fileURLWithPath: "iOS/Snapfly")
let shareExtension = URL(fileURLWithPath: "iOS/Share")
let fm = FileManager.default

// Every L("...") call. A call that is not a plain string literal cannot be
// checked, so it is reported too.
var used = Set<String>()
var problems: [String] = []
var warnings: [String] = []
let literal = try NSRegularExpression(pattern: #"\bL\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#)
let anyCall = try NSRegularExpression(pattern: #"\bL\("#)
// What Shortcuts shows of the iPhone's actions: their titles, descriptions,
// parameters' titles and short titles, which iOS looks up in
// Localizable.strings by their English text, as L() does.
let intentLiteral = try NSRegularExpression(
    pattern: #"(?:LocalizedStringResource\s*=|IntentDescription\(|\b(?:title|shortTitle):)\s*"((?:[^"\\]|\\.)*)""#)
for folder in [sources, iPhone, shareExtension] {
    for case let file as URL in fm.enumerator(at: folder, includingPropertiesForKeys: nil)!
    where file.pathExtension == "swift" && file.lastPathComponent != "Localization.swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(text.startIndex..., in: text)
        let literals = literal.matches(in: text, range: range)
        for match in literals {
            let key = String(text[Range(match.range(at: 1), in: text)!])
            used.insert(key.replacingOccurrences(of: #"\""#, with: #"""#))
        }
        if text.contains("import AppIntents") {
            for match in intentLiteral.matches(in: text, range: range) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                used.insert(key.replacingOccurrences(of: #"\""#, with: #"""#))
            }
        }
        let calls = anyCall.numberOfMatches(in: text, range: range)
        if calls != literals.count {
            problems.append("\(file.lastPathComponent): \(calls - literals.count) L(...) call(s) without a plain string")
        }
    }
}

let languages = try fm.contentsOfDirectory(atPath: resources.path)
    .filter { $0.hasSuffix(".lproj") }.sorted()
for folder in languages {
    let url = resources.appendingPathComponent(folder).appendingPathComponent("Localizable.strings")
    guard let table = NSDictionary(contentsOf: url) as? [String: String] else {
        problems.append("\(folder): Localizable.strings is missing or cannot be read")
        continue
    }
    let keys = Set(table.keys)
    for key in used.subtracting(keys).sorted() {
        let message = "\(folder): missing \"\(key)\""
        if folder == "en.lproj" { problems.append(message) } else { warnings.append(message) }
    }
    for key in keys.subtracting(used).sorted() { problems.append("\(folder): unused \"\(key)\"") }
}

// The questions macOS asks before the Mac app may watch a folder, use the
// microphone or ask a browser: scripts/build-app.sh writes the English ones
// into Info.plist, and each language's InfoPlist.strings asks every one of
// them, the English one in the same words, and nothing else.
let buildScript = try String(contentsOfFile: "scripts/build-app.sh", encoding: .utf8)
let usage = try NSRegularExpression(pattern: #"<key>(NS\w+UsageDescription)</key>\s*<string>([^<]*)</string>"#)
var asked: [String: String] = [:]
for match in usage.matches(in: buildScript, range: NSRange(buildScript.startIndex..., in: buildScript)) {
    let key = String(buildScript[Range(match.range(at: 1), in: buildScript)!])
    asked[key] = String(buildScript[Range(match.range(at: 2), in: buildScript)!])
}
if asked.isEmpty { problems.append("scripts/build-app.sh: no usage descriptions found in its Info.plist") }
let macQuestions = sources.appendingPathComponent("InfoPlist")
for folder in languages {
    let url = macQuestions.appendingPathComponent(folder).appendingPathComponent("InfoPlist.strings")
    guard let table = NSDictionary(contentsOf: url) as? [String: String] else {
        problems.append("\(folder): the Mac's InfoPlist.strings is missing or cannot be read")
        continue
    }
    for key in Set(asked.keys).subtracting(table.keys).sorted() {
        problems.append("\(folder): the Mac's InfoPlist.strings misses \(key)")
    }
    for key in Set(table.keys).subtracting(asked.keys).sorted() {
        problems.append("\(folder): the Mac's InfoPlist.strings has \(key), which scripts/build-app.sh does not ask")
    }
    if folder == "en.lproj" {
        for (key, english) in asked.sorted(by: { $0.key < $1.key }) where table[key].map({ $0 != english }) ?? false {
            problems.append("en.lproj: the Mac's InfoPlist.strings words \(key) otherwise than scripts/build-app.sh")
        }
    }
}

warnings.forEach { print("warning: \($0)") }
if problems.isEmpty {
    print("\(used.count) strings and the Mac's \(asked.count) permission questions, checked in \(languages.map { $0.replacingOccurrences(of: ".lproj", with: "") }.joined(separator: ", "))")
} else {
    problems.forEach { print($0) }
    exit(1)
}
