import CoreLocation
import Foundation

enum Overpass {
    static let mirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]
    static let skipTypes: Set<String> = ["garage", "garages", "shed", "carport", "roof", "greenhouse"]

    /// Building footprints + standalone address points around a coordinate.
    static func fetchHouses(around c: CLLocationCoordinate2D) async throws -> [House] {
        let q = """
        [out:json][timeout:15];(way["building"](around:220,\(c.latitude),\(c.longitude));\
        node["addr:housenumber"](around:220,\(c.latitude),\(c.longitude)););out geom;
        """
        var lastError: Error = URLError(.cannotConnectToHost)
        for mirror in mirrors {
            do {
                var req = URLRequest(url: URL(string: mirror)!, timeoutInterval: 12)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.httpBody = ("data=" + q.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).data(using: .utf8)
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                return parse(data: data)
            } catch { lastError = error }
        }
        throw lastError
    }

    private static func parse(data: Data) -> [House] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return [] }

        var houses: [House] = []
        // pass 1: building footprints -> centroid
        for el in elements {
            guard el["type"] as? String == "way",
                  let geom = el["geometry"] as? [[String: Double]], geom.count >= 3 else { continue }
            let tags = el["tags"] as? [String: String] ?? [:]
            if skipTypes.contains(tags["building"] ?? "") { continue }
            let lat = geom.compactMap { $0["lat"] }.reduce(0, +) / Double(geom.count)
            let lon = geom.compactMap { $0["lon"] }.reduce(0, +) / Double(geom.count)
            let h = House(id: "w\(el["id"] as? Int64 ?? 0)",
                          coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            applyOsmAddress(h, tags: tags)
            houses.append(h)
        }
        // pass 2: address points -> attach to nearest unaddressed footprint, else stand alone
        for el in elements {
            guard el["type"] as? String == "node",
                  let lat = el["lat"] as? Double, let lon = el["lon"] as? Double,
                  let tags = el["tags"] as? [String: String],
                  tags["addr:housenumber"] != nil else { continue }
            let pt = CLLocation(latitude: lat, longitude: lon)
            var host: House?
            var hostD = 30.0
            for h in houses {
                let d = pt.distance(from: CLLocation(latitude: h.coordinate.latitude, longitude: h.coordinate.longitude))
                if d < hostD { host = h; hostD = d }
            }
            if let host {
                if host.addrShort == nil { applyOsmAddress(host, tags: tags) }
            } else {
                let h = House(id: "n\(el["id"] as? Int64 ?? 0)",
                              coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                applyOsmAddress(h, tags: tags)
                houses.append(h)
            }
        }
        return houses
    }

    private static func applyOsmAddress(_ h: House, tags: [String: String]) {
        guard let num = tags["addr:housenumber"], let street = tags["addr:street"] else { return }
        h.addrShort = "\(num) \(street)"
        h.addrFull = h.addrShort! + (tags["addr:city"].map { ", \($0)" } ?? "")
    }
}

/// Apple's geocoder — no rate-key needed, but keep it to one lookup at a time.
actor Geocoder {
    static let shared = Geocoder()
    private let geocoder = CLGeocoder()

    func address(for c: CLLocationCoordinate2D) async -> (short: String, full: String)? {
        let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
        guard let pm = try? await geocoder.reverseGeocodeLocation(loc).first,
              let street = pm.thoroughfare else { return nil }
        let short = [pm.subThoroughfare, street].compactMap { $0 }.joined(separator: " ")
        let full = [short, pm.locality, pm.administrativeArea, pm.postalCode]
            .compactMap { $0 }.joined(separator: ", ")
        return (short, full)
    }
}

enum RentCast {
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "rentcast_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "rentcast_key") }
    }

    static func value(address: String) async -> Int? {
        guard !apiKey.isEmpty,
              let enc = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.rentcast.io/v1/avm/value?address=\(enc)") else { return nil }
        if let cached = UserDefaults.standard.object(forKey: "price_\(address)") as? Int { return cached }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let price = root["price"] as? Double else { return nil }
        UserDefaults.standard.set(Int(price), forKey: "price_\(address)")
        return Int(price)
    }
}
