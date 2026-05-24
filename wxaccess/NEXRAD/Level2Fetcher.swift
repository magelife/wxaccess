import Foundation
import OSLog

// Fetches NEXRAD Level 2 scan files from Unidata's THREDDS Data Server.
// The former NOAA S3 bucket (noaa-nexrad-level2) now returns 403 for anonymous
// access; Unidata THREDDS provides the same Archive II format with 7-day rolling
// retention and free HTTP access.
//
// Catalog URL:  https://thredds.ucar.edu/thredds/catalog/nexrad/level2/{SITE}/{YYYYMMDD}/catalog.xml
// Download URL: https://thredds.ucar.edu/thredds/fileServer/{urlPath}
// File format:  Archive II (.ar2v) — identical to the former _V06 format

final class Level2Fetcher: @unchecked Sendable {
    static let shared = Level2Fetcher()

    private let threddsBase = "https://thredds.ucar.edu/thredds"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "Level2Fetcher")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    // MARK: - List scans

    func listScans(site: NEXRADSite, date: Date = .now) async throws -> [ScanEntry] {
        let cal      = Calendar(identifier: .gregorian)
        let comps    = cal.dateComponents(in: .gmt, from: date)
        let yyyymmdd = String(format: "%04d%02d%02d", comps.year!, comps.month!, comps.day!)

        guard let catalogURL = URL(string:
            "\(threddsBase)/catalog/nexrad/level2/\(site.icao)/\(yyyymmdd)/catalog.xml") else {
            throw URLError(.badURL)
        }
        let (xmlData, response) = try await session.data(from: catalogURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try parseThreddsCatalog(xmlData: xmlData, site: site)
    }

    // MARK: - Download

    func download(entry: ScanEntry) async throws -> Data {
        // entry.id is the THREDDS urlPath returned by the catalog
        guard let url = URL(string: "\(threddsBase)/fileServer/\(entry.id)") else {
            throw URLError(.badURL)
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        } catch {
            logger.error("Level 2 download failed for \(entry.fileName): \(error)")
            throw error
        }
    }

    // MARK: - THREDDS InvCatalog XML parser

    private func parseThreddsCatalog(xmlData: Data, site: NEXRADSite) throws -> [ScanEntry] {
        let parser    = ThreddsCatalogParser(site: site)
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }
    }
}

// MARK: - XMLParserDelegate for THREDDS InvCatalog

private final class ThreddsCatalogParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    var entries: [ScanEntry] = []

    init(site: NEXRADSite) { self.site = site }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        guard elementName == "dataset",
              let name    = attributes["name"],
              let urlPath = attributes["urlPath"],
              name.hasSuffix(".ar2v"),
              !urlPath.isEmpty,
              let date = dateFromFilename(name) else { return }
        entries.append(ScanEntry(id: urlPath, site: site, scanTime: date, fileName: name))
    }

    // Filename format: Level2_KEWX_20260523_2356.ar2v
    private func dateFromFilename(_ name: String) -> Date? {
        guard name.hasPrefix("Level2_"), name.hasSuffix(".ar2v") else { return nil }
        let body  = String(name.dropFirst(7).dropLast(5))   // "KEWX_20260523_2356"
        let parts = body.split(separator: "_")
        guard parts.count >= 3 else { return nil }
        let dateStr = String(parts[1]) + String(parts[2])   // "202605232356"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: dateStr)
    }
}
