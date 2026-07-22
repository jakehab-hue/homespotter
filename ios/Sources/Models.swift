import CoreLocation
import Foundation

/// One identifiable home — from an OSM building footprint or address point.
final class House: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    var addrShort: String?          // "228 Presley Pl"
    var addrFull: String?           // "228 Presley Pl, San Diego, CA 92127"
    var price: Int?
    var priceState: PriceState = .none
    var anchorID: UUID?
    var geocodePending = false

    enum PriceState { case none, loading, done, error }

    init(id: String, coordinate: CLLocationCoordinate2D, addrShort: String? = nil, addrFull: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.addrShort = addrShort
        self.addrFull = addrFull
    }

    var searchQuery: String {
        addrFull ?? addrShort ?? String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }
}

/// A tag projected into screen space for the current frame.
struct ScreenTag: Identifiable {
    let id: String
    let point: CGPoint
    let distance: Double
    let title: String
    let price: Int?
}

func formatPrice(_ p: Int) -> String {
    p >= 1_000_000 ? String(format: "$%.2fM", Double(p) / 1_000_000)
                   : "$\(Int((Double(p) / 1000).rounded()))K"
}
