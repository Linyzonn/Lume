import Foundation

// MARK: - Pochettes via l'API de recherche iTunes (gratuite, sans cle)

enum ITunesArtwork {
    private struct SearchResponse: Decodable { let results: [Item] }
    private struct Item: Decodable { let artworkUrl100: String? }

    // Cherche la pochette d'un morceau et retourne les donnees de l'image (JPEG).
    static func fetchArtworkData(title: String, artist: String) async -> Data? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        for item in response.results {
            guard let small = item.artworkUrl100 else { continue }
            // Astuce connue : l'URL "100x100" existe aussi en "600x600".
            let big = small.replacingOccurrences(of: "100x100", with: "600x600")
            if let imgURL = URL(string: big),
               let (imgData, _) = try? await URLSession.shared.data(from: imgURL),
               imgData.count > 1000 {
                return imgData
            }
        }
        return nil
    }
}

// MARK: - Deezer (gratuit, sans cle) : photos d'artistes, artistes proches,
// tops titres avec extraits audio de 30 s ecoutables en ligne.

enum DeezerAPI {
    struct Artist: Decodable, Identifiable {
        let id: Int
        let name: String
        let picture_medium: String?
        let picture_big: String?
    }
    struct TrackItem: Decodable, Identifiable {
        let id: Int
        let title: String
        let preview: String?          // extrait MP3 de 30 s
        let link: String?             // page Deezer du titre
        let artist: ArtistRef
        let album: AlbumRef?
    }
    struct ArtistRef: Decodable { let name: String }
    struct AlbumRef: Decodable { let title: String?; let cover_medium: String?; let cover_big: String? }

    private struct ListResponse<T: Decodable>: Decodable { let data: [T] }

    private static func get<T: Decodable>(_ urlString: String, as type: T.Type) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func searchArtist(_ name: String) async -> Artist? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let r: ListResponse<Artist>? = await get("https://api.deezer.com/search/artist?q=\(q)&limit=1",
                                                 as: ListResponse<Artist>.self)
        return r?.data.first
    }

    static func relatedArtists(id: Int) async -> [Artist] {
        let r: ListResponse<Artist>? = await get("https://api.deezer.com/artist/\(id)/related?limit=6",
                                                 as: ListResponse<Artist>.self)
        return r?.data ?? []
    }

    static func topTracks(artistID: Int, limit: Int = 6) async -> [TrackItem] {
        let r: ListResponse<TrackItem>? = await get("https://api.deezer.com/artist/\(artistID)/top?limit=\(limit)",
                                                    as: ListResponse<TrackItem>.self)
        return r?.data ?? []
    }

    static func imageData(from urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              data.count > 1000 else { return nil }
        return data
    }
}
