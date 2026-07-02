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
    struct AlbumRef: Decodable { let id: Int?; let title: String?; let cover_medium: String?; let cover_big: String? }

    private struct ListResponse<T: Decodable>: Decodable { let data: [T] }

    private static func get<T: Decodable>(_ urlString: String, as type: T.Type) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        // Petite pause entre les appels : l'API Deezer limite a ~50 requetes
        // par 5 secondes et par IP. On reste largement en dessous.
        try? await Task.sleep(nanoseconds: 130_000_000)
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

    // Details complets d'un titre — inclut notamment le BPM (0 si inconnu).
    struct TrackDetails: Decodable {
        let id: Int
        let bpm: Double?
    }

    static func trackDetails(id: Int) async -> TrackDetails? {
        await get("https://api.deezer.com/track/\(id)", as: TrackDetails.self)
    }

    // Recherche d'un titre precis (pour retrouver le BPM des morceaux de ta bibliotheque).
    static func searchTrack(title: String, artist: String) async -> TrackItem? {
        let raw = "artist:\"\(artist)\" track:\"\(title)\""
        let q = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        let r: ListResponse<TrackItem>? = await get("https://api.deezer.com/search?q=\(q)&limit=1",
                                                    as: ListResponse<TrackItem>.self)
        return r?.data.first
    }

    // Genres musicaux Deezer (id -> nom).
    struct Genre: Decodable { let id: Int; let name: String }

    static func genres() async -> [Int: String] {
        let r: ListResponse<Genre>? = await get("https://api.deezer.com/genre", as: ListResponse<Genre>.self)
        var map: [Int: String] = [:]
        for g in r?.data ?? [] { map[g.id] = g.name }
        return map
    }

    // Premier album d'un artiste (pour connaitre son genre principal).
    struct AlbumItem: Decodable { let id: Int; let genre_id: Int? }

    static func artistMainGenreID(artistID: Int) async -> Int? {
        let r: ListResponse<AlbumItem>? = await get("https://api.deezer.com/artist/\(artistID)/albums?limit=3",
                                                    as: ListResponse<AlbumItem>.self)
        return r?.data.compactMap { $0.genre_id }.first(where: { $0 > 0 })
    }

    // Tendances editoriales d'un genre (titres populaires du style en ce moment).
    private struct EditorialCharts: Decodable {
        let tracks: ListResponse<TrackItem>?
    }

    static func genreChartTracks(genreID: Int, limit: Int = 12) async -> [TrackItem] {
        let r: EditorialCharts? = await get("https://api.deezer.com/editorial/\(genreID)/charts",
                                            as: EditorialCharts.self)
        return Array((r?.tracks?.data ?? []).prefix(limit))
    }

    static func imageData(from urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              data.count > 1000 else { return nil }
        return data
    }
}
