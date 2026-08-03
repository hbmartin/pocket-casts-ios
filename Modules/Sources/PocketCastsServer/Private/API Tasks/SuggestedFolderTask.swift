import Foundation
import PocketCastsUtils
import SwiftProtobuf

public struct SuggestedFoldersResponse: Sendable {
    public let suggestions: [String: [String]]

    /// Repairs an untrusted provider response into a complete, deterministic
    /// partition of the submitted UUIDs.
    public static func repaired(
        _ raw: [String: [String]],
        submittedUUIDs: [String],
        otherName: String
    ) -> SuggestedFoldersResponse {
        let valid = Set(submittedUUIDs)
        let otherFolded = otherName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
        var merged: [String: (name: String, uuids: [String])] = [:]
        var forcedOther = Set<String>()

        for name in raw.keys.sorted() {
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
            let recognized = (raw[name] ?? []).filter { valid.contains($0) }
            if folded == otherFolded {
                forcedOther.formUnion(recognized)
                continue
            }
            var group = merged[folded] ?? (name, [])
            var existingUUIDs = Set(group.uuids)
            group.uuids.append(contentsOf: recognized.filter { existingUUIDs.insert($0).inserted })
            merged[folded] = group
        }

        var occurrences: [String: Int] = [:]
        for group in merged.values {
            for uuid in group.uuids { occurrences[uuid, default: 0] += 1 }
        }
        for uuid in forcedOther { occurrences[uuid, default: 0] += 1 }

        var other = Set(valid.filter { occurrences[$0] != 1 })
        other.formUnion(forcedOther)
        var groups = merged.values.compactMap { group -> (name: String, uuids: [String])? in
            let uuids = group.uuids.filter { occurrences[$0] == 1 }.sorted()
            guard uuids.count >= 2 else {
                other.formUnion(uuids)
                return nil
            }
            return (group.name, uuids)
        }
        groups.sort {
            if $0.uuids.count != $1.uuids.count { return $0.uuids.count > $1.uuids.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let totalFolderCount = groups.count + (other.isEmpty ? 0 : 1)
        if totalFolderCount > 8 {
            for group in groups.dropFirst(7) { other.formUnion(group.uuids) }
            groups = Array(groups.prefix(7))
        }

        var repaired = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.uuids) })
        if !other.isEmpty { repaired[otherName] = other.sorted() }
        return SuggestedFoldersResponse(suggestions: repaired)
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SuggestedFoldersTask: ApiBaseTask, @unchecked Sendable {
    var uuids: [String]
    var language: String
    var completion: ((SuggestedFoldersResponse?) -> Void)?

    init(uuids: [String], language: String, completion: ((SuggestedFoldersResponse?) -> Void)?) {
        self.uuids = uuids
        self.language = language
        self.completion = completion
    }

    override func main() {
        doNetworkCall()
    }

    func doNetworkCall() {
        let urlString = "\(ServerConstants.Urls.cache())podcast/suggest_folders"

        do {
            guard let requestData = try? JSONSerialization.data(withJSONObject: ["language": language, "uuids": uuids]) else {
                FileLog.shared.addMessage("Failed to encode uuids for suggested folders call")
                completion?(nil)
                return
            }

            let (data, statusCode) = super.performPostToServer(url: urlString, token: nil, data: requestData)
            guard let responseData = data,
                  statusCode == ServerConstants.HttpConstants.ok
            else {
                FileLog.shared.addMessage("Failed to get suggested folders - server returned \(statusCode)")
                completion?(nil)
                return
            }
            let validationResponse = try JSONSerialization.jsonObject(with: responseData)
            guard let jsonDictionary = validationResponse as? [String: [String]] else {
                FileLog.shared.addMessage("Failed to parse Suggested Folders Response - not a dictionary")
                completion?(nil)
                return
            }
            let suggestions = SuggestedFoldersResponse.repaired(
                jsonDictionary,
                submittedUUIDs: uuids,
                otherName: Self.localizedOther(language: language)
            )
            completion?(suggestions)
        } catch {
            FileLog.shared.addMessage("Failed to parse Suggested Folders Response \(error.localizedDescription)")
            completion?(nil)
        }
    }

    private static func localizedOther(language: String) -> String {
        switch language.lowercased().split(separator: "-").first {
        case "de": "Andere"
        case "es": "Otros"
        case "fr": "Autres"
        case "it": "Altro"
        case "ja": "その他"
        case "nl": "Overig"
        case "pt": "Outros"
        case "ru": "Другое"
        case "sv": "Övrigt"
        case "zh": "其他"
        default: "Other"
        }
    }
}
