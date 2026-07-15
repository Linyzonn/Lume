import XCTest
@testable import Lume

// Tests de la logique la plus fragile de l'app : parsing multi-artistes,
// nettoyage des metadonnees, paroles synchronisees et fusion des doublons.
// Executes automatiquement par GitHub Actions a chaque push (job "test").
@MainActor
final class LumeTests: XCTestCase {

    private func makeTrack(title: String,
                           artist: String,
                           duration: Double = 200,
                           isFavorite: Bool = false,
                           dateAdded: Date = Date()) -> Track {
        Track(fileName: "\(UUID().uuidString).m4a",
              title: title,
              artist: artist,
              album: "Album test",
              duration: duration,
              dateAdded: dateAdded,
              isFavorite: isFavorite)
    }

    // MARK: - Decoupage multi-artistes (Track.artistList)

    func testArtistListSplitsCollaborations() {
        let t = makeTrack(title: "X", artist: "JAY-Z, Rihanna & Kanye West")
        XCTAssertEqual(t.artistList, ["JAY-Z", "Rihanna", "Kanye West"])
    }

    func testArtistListKeepsProtectedNames() {
        XCTAssertEqual(makeTrack(title: "X", artist: "Tyler, The Creator").artistList,
                       ["Tyler, The Creator"])
        XCTAssertEqual(makeTrack(title: "X", artist: "AC/DC").artistList,
                       ["AC/DC"])
        XCTAssertEqual(makeTrack(title: "X", artist: "Earth, Wind & Fire").artistList,
                       ["Earth, Wind & Fire"])
    }

    func testArtistListProtectedNameAmongOthers() {
        let t = makeTrack(title: "X", artist: "Earth, Wind & Fire, Drake")
        XCTAssertEqual(t.artistList, ["Earth, Wind & Fire", "Drake"])
    }

    func testArtistListFeaturingSeparators() {
        XCTAssertEqual(makeTrack(title: "X", artist: "Drake feat. Rihanna").artistList,
                       ["Drake", "Rihanna"])
        XCTAssertEqual(makeTrack(title: "X", artist: "Drake ft. Rihanna").artistList,
                       ["Drake", "Rihanna"])
    }

    func testArtistListSingleArtistUntouched() {
        XCTAssertEqual(makeTrack(title: "X", artist: "Stromae").artistList, ["Stromae"])
    }

    // MARK: - Nettoyage des metadonnees (LibraryStore statiques)

    func testCleanedTitleRemovesYouTubeSuffixes() {
        XCTAssertEqual(LibraryStore.cleanedTitle("Run This Town (Official Video)"),
                       "Run This Town")
        XCTAssertEqual(LibraryStore.cleanedTitle("Alors on danse [Clip Officiel]"),
                       "Alors on danse")
        XCTAssertEqual(LibraryStore.cleanedTitle("Titre (Lyrics)"), "Titre")
        // Un titre sans suffixe parasite reste intact.
        XCTAssertEqual(LibraryStore.cleanedTitle("Bohemian Rhapsody"), "Bohemian Rhapsody")
    }

    func testExtractFeaturedArtists() {
        let (title1, feats1) = LibraryStore.extractFeaturedArtists(
            from: "Run This Town ft. Rihanna, Kanye West")
        XCTAssertEqual(title1, "Run This Town")
        XCTAssertEqual(feats1, ["Rihanna", "Kanye West"])

        let (title2, feats2) = LibraryStore.extractFeaturedArtists(from: "Song (feat. Drake & SZA)")
        XCTAssertEqual(title2, "Song")
        XCTAssertEqual(feats2, ["Drake", "SZA"])

        // Pas de featuring -> rien ne change.
        let (title3, feats3) = LibraryStore.extractFeaturedArtists(from: "Simple Song")
        XCTAssertEqual(title3, "Simple Song")
        XCTAssertTrue(feats3.isEmpty)
    }

    func testNormalizedFoldsCaseAndDiacritics() {
        XCTAssertEqual(LibraryStore.normalized("JAŸ-Z"), LibraryStore.normalized("jay-z"))
        XCTAssertEqual(LibraryStore.normalized("  Stromaé "), "stromae")
    }

    // MARK: - Paroles synchronisees (LRCParser)

    func testLRCParserParsesTimestamps() throws {
        let raw = """
        [00:05.00] Première ligne
        [00:12.50] Deuxième ligne
        [01:02.25] Troisième ligne
        [01:30] Quatrième ligne
        """
        let lines = try XCTUnwrap(LRCParser.parse(raw))
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].time, 5.0, accuracy: 0.01)
        XCTAssertEqual(lines[1].time, 12.5, accuracy: 0.01)
        XCTAssertEqual(lines[2].text, "Troisième ligne")
        XCTAssertEqual(lines[3].time, 90.0, accuracy: 0.01)
    }

    func testLRCParserHandlesRepeatedTimestamps() throws {
        let raw = """
        [00:10.00][01:10.00] Refrain
        [00:20.00] Couplet
        [00:40.00] Pont
        """
        let lines = try XCTUnwrap(LRCParser.parse(raw))
        // Le refrain apparait deux fois (a 10 s et 70 s), trie chronologiquement.
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.first?.text, "Refrain")
        let lastLine = try XCTUnwrap(lines.last)
        XCTAssertEqual(lastLine.time, 70.0, accuracy: 0.01)
    }

    func testLRCParserRejectsPlainText() {
        XCTAssertNil(LRCParser.parse("Des paroles\nsans aucun\nhorodatage\nsur quatre lignes"))
    }

    // MARK: - Construction d'URL (encodage strict des valeurs)

    func testAPIURLEncodesAmpersandInValues() throws {
        let url = try XCTUnwrap(APIURL.build("https://example.com/search",
                                             [("q", "Simon & Garfunkel"), ("limit", "1")]))
        XCTAssertEqual(url.absoluteString,
                       "https://example.com/search?q=Simon%20%26%20Garfunkel&limit=1")
    }

    func testAPIURLEncodesPlusAndEquals() throws {
        let url = try XCTUnwrap(APIURL.build("https://example.com",
                                             [("q", "Dan + Shay = duo")]))
        XCTAssertEqual(url.absoluteString,
                       "https://example.com?q=Dan%20%2B%20Shay%20%3D%20duo")
    }

    func testAPIURLKeepsSimpleValuesReadable() throws {
        let url = try XCTUnwrap(APIURL.build("https://example.com",
                                             [("media", "music"), ("limit", "3")]))
        XCTAssertEqual(url.absoluteString, "https://example.com?media=music&limit=3")
    }

    // MARK: - Decodage tolerant (protection contre la perte de bibliotheque)

    func testTrackDecodingToleratesMissingFields() throws {
        let json = Data(#"{"fileName":"a.m4a","title":"Titre"}"#.utf8)
        let t = try JSONDecoder().decode(Track.self, from: json)
        XCTAssertEqual(t.fileName, "a.m4a")
        XCTAssertEqual(t.title, "Titre")
        XCTAssertEqual(t.artist, "Artiste inconnu")
        XCTAssertEqual(t.duration, 0)
        XCTAssertFalse(t.isFavorite)
    }

    func testTrackDecodingRoundTrip() throws {
        let original = makeTrack(title: "Run This Town", artist: "JAY-Z", isFavorite: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.artist, original.artist)
        XCTAssertTrue(decoded.isFavorite)
    }

    func testPlaylistDecodingToleratesMissingFields() throws {
        let json = Data(#"{"name":"Ma playlist"}"#.utf8)
        let p = try JSONDecoder().decode(Playlist.self, from: json)
        XCTAssertEqual(p.name, "Ma playlist")
        XCTAssertTrue(p.trackIDs.isEmpty)
    }

    // MARK: - Fusion des doublons (LibraryStore)

    func testRemoveDuplicatesMergesAndRemaps() {
        let store = LibraryStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LumeTests-\(UUID().uuidString)", isDirectory: true),
            documentsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LumeTestsDocs-\(UUID().uuidString)", isDirectory: true))
        let old = Date(timeIntervalSinceNow: -3600)

        let original = makeTrack(title: "Run This Town", artist: "JAY-Z",
                                 duration: 267, dateAdded: old)
        let duplicate = makeTrack(title: "run this town", artist: "jay-z",
                                  duration: 268, isFavorite: true)
        let unrelated = makeTrack(title: "Alors on danse", artist: "Stromae", duration: 210)

        store.tracks = [original, duplicate, unrelated]
        store.playlists = [Playlist(name: "Ma playlist", trackIDs: [duplicate.id, unrelated.id])]

        let removed = store.removeDuplicateTracks()

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.tracks.count, 2)
        // L'original (le plus ancien) est conserve...
        XCTAssertNotNil(store.tracks.first(where: { $0.id == original.id }))
        XCTAssertNil(store.tracks.first(where: { $0.id == duplicate.id }))
        // ...et herite du statut favori du doublon.
        XCTAssertTrue(store.tracks.first(where: { $0.id == original.id })?.isFavorite ?? false)
        // La playlist pointe desormais vers l'original.
        XCTAssertEqual(store.playlists[0].trackIDs, [original.id, unrelated.id])
    }

    func testRemoveDuplicatesIgnoresDifferentDurations() {
        let store = LibraryStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LumeTests-\(UUID().uuidString)", isDirectory: true),
            documentsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LumeTestsDocs-\(UUID().uuidString)", isDirectory: true))
        // Meme titre/artiste mais durees eloignees (ex. version radio vs live) :
        // ce ne sont PAS des doublons.
        store.tracks = [makeTrack(title: "Song", artist: "A", duration: 180),
                        makeTrack(title: "Song", artist: "A", duration: 320)]
        store.playlists = []
        XCTAssertEqual(store.removeDuplicateTracks(), 0)
        XCTAssertEqual(store.tracks.count, 2)
    }
}
