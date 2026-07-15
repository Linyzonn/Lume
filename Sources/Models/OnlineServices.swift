import Foundation

// MARK: - Construction d'URL sure
//
// PIEGE CONNU : URLComponents / .urlQueryAllowed n'encodent PAS les
// caracteres & + = a l'interieur des VALEURS de parametres (ils sont legaux
// dans une query au sens RFC 3986, donc laisses tels quels). Resultat :
// « Simon & Garfunkel » tronquait le parametre — paroles, pochettes et
// recommandations echouaient pour tout artiste/titre contenant & ou +.
// Ce constructeur encode strictement chaque valeur.
enum APIURL {
    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?/")
        return set
    }()

    static func encodeValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? value
    }

    static func build(_ base: String, _ params: [(String, String)]) -> URL? {
        guard !params.isEmpty else { return URL(string: base) }
        let query = params
            .map { "\($0.0)=\(encodeValue($0.1))" }
            .joined(separator: "&")
        return URL(string: "\(base)?\(query)")
    }
}

// MARK: - Pochettes via l'API de recherche iTunes (gratuite, sans cle)

enum ITunesArtwork {
    private struct SearchResponse: Decodable { let results: [Item] }
    private struct Item: Decodable { let artworkUrl100: String? }

    // Cherche la pochette d'un morceau et retourne les donnees de l'image (JPEG).
    static func fetchArtworkData(title: String, artist: String) async -> Data? {
        guard let url = APIURL.build("https://itunes.apple.com/search", [
                  ("term", "\(artist) \(title)"),
                  ("media", "music"),
                  ("entity", "song"),
                  ("limit", "3")
              ]),
              let data = await APICache.fetch(url: url, maxAge: 7 * 24 * 3600),
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

    // Espacement REEL des requetes. L'ancienne pause fixe de 130 ms ne
    // limitait rien en pratique : N requetes lancees en parallele dormaient
    // toutes EN MEME TEMPS puis partaient d'un coup. Cet acteur attribue les
    // creneaux en serie : ~12 requetes/s maximum, loin des ~50/5 s de l'API.
    private actor RequestPacer {
        private var nextSlot = Date.distantPast
        func waitTurn() async {
            let now = Date()
            let slot = max(now, nextSlot)
            nextSlot = slot.addingTimeInterval(0.08)
            let delay = slot.timeIntervalSince(now)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    private static let pacer = RequestPacer()

    private static func get<T: Decodable>(_ urlString: String, as type: T.Type,
                                          ignoreCache: Bool = false) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        // 1) Cache disque 24 h : les tops, artistes proches et genres bougent
        //    peu. Sert instantanement, sans toucher au reseau ni au quota.
        //    `ignoreCache` (rafraichissement force de Decouvrir) saute cette
        //    etape : sans cela, le bouton « Actualiser » ressortait les MEMES
        //    reponses pendant 24 h. La reponse fraiche est quand meme stockee
        //    (etape 2), et le cache perime reste le repli hors-ligne (etape 3).
        if !ignoreCache, let cached = APICache.data(for: url, maxAge: 24 * 3600) {
            return try? JSONDecoder().decode(T.self, from: cached)
        }
        // 2) Reseau, cadence par le pacer (l'API Deezer limite a
        //    ~50 requetes / 5 s / IP ; on reste largement dessous).
        await pacer.waitTurn()
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let (data, response) = try? await URLSession.shared.data(for: req),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            APICache.store(data, for: url)
            return try? JSONDecoder().decode(T.self, from: data)
        }
        // 3) Echec reseau : on ressert la derniere reponse connue, meme vieille
        //    (mode hors-ligne).
        if let stale = APICache.data(for: url, maxAge: nil) {
            return try? JSONDecoder().decode(T.self, from: stale)
        }
        return nil
    }

    static func searchArtist(_ name: String) async -> Artist? {
        let q = APIURL.encodeValue(name)
        let r: ListResponse<Artist>? = await get("https://api.deezer.com/search/artist?q=\(q)&limit=1",
                                                 as: ListResponse<Artist>.self)
        return r?.data.first
    }

    static func relatedArtists(id: Int, ignoreCache: Bool = false) async -> [Artist] {
        let r: ListResponse<Artist>? = await get("https://api.deezer.com/artist/\(id)/related?limit=12",
                                                 as: ListResponse<Artist>.self, ignoreCache: ignoreCache)
        return r?.data ?? []
    }

    static func topTracks(artistID: Int, limit: Int = 6, ignoreCache: Bool = false) async -> [TrackItem] {
        let r: ListResponse<TrackItem>? = await get("https://api.deezer.com/artist/\(artistID)/top?limit=\(limit)",
                                                    as: ListResponse<TrackItem>.self, ignoreCache: ignoreCache)
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
        let q = APIURL.encodeValue("artist:\"\(artist)\" track:\"\(title)\"")
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

    static func genreChartTracks(genreID: Int, limit: Int = 12, ignoreCache: Bool = false) async -> [TrackItem] {
        let r: EditorialCharts? = await get("https://api.deezer.com/editorial/\(genreID)/charts",
                                            as: EditorialCharts.self, ignoreCache: ignoreCache)
        return Array((r?.tracks?.data ?? []).prefix(limit))
    }

    static func imageData(from urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              data.count > 1000 else { return nil }
        return data
    }
}
