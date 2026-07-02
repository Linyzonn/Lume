import Foundation

// Recherche de paroles en ligne via LRCLIB (https://lrclib.net) :
// service libre et gratuit, sans cle API ni inscription.
// Quand elles existent, il fournit des paroles SYNCHRONISEES (format LRC,
// chaque ligne horodatee "[mm:ss.xx]") qui permettent le suivi en direct ;
// sinon des paroles en texte simple.
enum LyricsFetcher {

    private struct LrclibEntry: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    enum FetchError: Error { case notFound, network }

    // Cherche les paroles d'un morceau. Privilegie les paroles synchronisees.
    static func fetch(title: String, artist: String, duration: Double) async throws -> String {
        // 1) Correspondance exacte : titre + artiste + duree (tolerance ±2 s cote serveur).
        if let entry = try? await get(title: title, artist: artist, duration: duration),
           let lyrics = best(of: entry) {
            return lyrics
        }
        // 2) Recherche approchee (utile si la duree ou l'orthographe differe un peu).
        let results = try await search(title: title, artist: artist)
        if let synced = results.first(where: { nonEmpty($0.syncedLyrics) != nil })?.syncedLyrics {
            return synced
        }
        if let plain = results.first(where: { nonEmpty($0.plainLyrics) != nil })?.plainLyrics {
            return plain
        }
        throw FetchError.notFound
    }

    // MARK: - Appels reseau

    private static func get(title: String, artist: String, duration: Double) async throws -> LrclibEntry {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        let data = try await requestData(url: comps.url!)
        return try JSONDecoder().decode(LrclibEntry.self, from: data)
    }

    private static func search(title: String, artist: String) async throws -> [LrclibEntry] {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        let data = try await requestData(url: comps.url!)
        return (try? JSONDecoder().decode([LrclibEntry].self, from: data)) ?? []
    }

    private static func requestData(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        // LRCLIB demande poliment un User-Agent identifiant l'application.
        req.setValue("Lume/1.5 (https://github.com/Linyzonn/Lume)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw FetchError.network }
        guard http.statusCode == 200 else { throw FetchError.notFound }
        return data
    }

    // MARK: - Aides

    private static func best(of entry: LrclibEntry) -> String? {
        nonEmpty(entry.syncedLyrics) ?? nonEmpty(entry.plainLyrics)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}

// MARK: - Analyse du format LRC (paroles synchronisees)

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double      // secondes depuis le debut du morceau
    let text: String
}

enum LRCParser {
    // Analyse des paroles au format LRC. Retourne nil si le texte ne contient
    // pas (assez) d'horodatages -> il sera alors affiche comme texte simple.
    // Gere plusieurs horodatages par ligne : "[00:12.5][01:04.2] refrain".
    static func parse(_ raw: String) -> [LyricLine]? {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)\]"#) else { return nil }
        var stamped: [(Double, String)] = []
        for line in raw.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                stamped.append((minutes * 60 + seconds, text))
            }
        }
        guard stamped.count >= 4 else { return nil }
        return stamped.sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
