import ARKit
import Combine
import CoreLocation
import RealityKit
import SwiftUI

@MainActor
final class ARManager: NSObject, ObservableObject {
    @Published var tags: [ScreenTag] = []
    @Published var selected: House?
    @Published var statusLine = "starting…"
    @Published var trackingReady = false
    @Published var fatalMessage: String?      // geo tracking unavailable here / unsupported device

    weak var arView: ARView?
    private let locationManager = CLLocationManager()
    private var housesByAnchor: [UUID: House] = [:]
    private var allHouses: [House] = []
    private var lastFetch: CLLocation?
    private var fetching = false
    private var frameCount = 0
    private var resolverTimer: Timer?

    func attach(_ view: ARView) {
        arView = view
        view.automaticallyConfigureSession = false
        view.session.delegate = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        guard ARGeoTrackingConfiguration.isSupported else {
            fatalMessage = "This iPhone doesn't support ARKit geo tracking (needs A12 chip or newer)."
            return
        }
        locationManager.requestWhenInUseAuthorization()

        resolverTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.resolverTick() }
        }
    }

    private func startSessionIfAvailable() {
        ARGeoTrackingConfiguration.checkAvailability { [weak self] available, _ in
            Task { @MainActor in
                guard let self else { return }
                if available {
                    let config = ARGeoTrackingConfiguration()
                    self.arView?.session.run(config)
                    self.statusLine = "looking around to localize…"
                    self.locationManager.startUpdatingLocation()
                } else {
                    self.fatalMessage = """
                    Apple's geo tracking isn't available at this exact location. \
                    It covers most metro areas — try from the street rather than indoors.
                    """
                }
            }
        }
    }

    // MARK: - data

    private func fetchHousesIfNeeded(near loc: CLLocation) {
        if fetching { return }
        if let last = lastFetch, loc.distance(from: last) < 100 { return }
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let houses = try await Overpass.fetchHouses(around: loc.coordinate)
                lastFetch = loc
                addAnchors(for: houses, near: loc)
                statusLine = "\(houses.count) homes loaded"
            } catch {
                statusLine = "map data failed: \(error.localizedDescription)"
            }
        }
    }

    private func addAnchors(for houses: [House], near loc: CLLocation) {
        guard let session = arView?.session else { return }
        let known = Set(allHouses.map(\.id))
        let fresh = houses
            .filter { !known.contains($0.id) }
            .sorted {
                loc.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <
                loc.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            }
            .prefix(60)
        for house in fresh {
            let anchor = ARGeoAnchor(coordinate: house.coordinate)
            house.anchorID = anchor.identifier
            housesByAnchor[anchor.identifier] = house
            allHouses.append(house)
            session.add(anchor: anchor)
        }
    }

    // MARK: - background address/price resolution

    private func resolverTick() async {
        guard trackingReady else { return }
        if let house = allHouses.first(where: { $0.addrShort == nil && !$0.geocodePending }) {
            house.geocodePending = true
            if let addr = await Geocoder.shared.address(for: house.coordinate) {
                house.addrShort = addr.short
                house.addrFull = addr.full
            }
            return
        }
        if !RentCast.apiKey.isEmpty,
           let house = allHouses.first(where: { $0.addrFull != nil && $0.priceState == .none }) {
            house.priceState = .loading
            if let price = await RentCast.value(address: house.addrFull!) {
                house.price = price
                house.priceState = .done
            } else {
                house.priceState = .error
            }
        }
    }

    func select(id: String) {
        selected = allHouses.first { $0.id == id }
        if let s = selected, s.priceState == .none, !RentCast.apiKey.isEmpty, let addr = s.addrFull {
            s.priceState = .loading
            Task {
                s.price = await RentCast.value(address: addr)
                s.priceState = s.price == nil ? .error : .done
                objectWillChange.send()
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let status = frame.geoTrackingStatus
        let camera = frame.camera.transform
        let anchors = frame.anchors.compactMap { $0 as? ARGeoAnchor }
        Task { @MainActor in
            self.processFrame(status: status, camera: camera, anchors: anchors)
        }
    }

    private func processFrame(status: ARGeoTrackingStatus?, camera: simd_float4x4, anchors: [ARGeoAnchor]) {
        frameCount += 1
        if frameCount % 3 != 0 { return }   // ~20Hz UI updates

        if let status {
            switch status.state {
            case .localized:
                trackingReady = true
                statusLine = "locked on · \(allHouses.count) homes"
            case .localizing:
                statusLine = "point at buildings across the street to localize…"
            case .initializing:
                statusLine = "starting AR…"
            case .notAvailable:
                statusLine = "geo tracking not available here"
            @unknown default: break
            }
        }
        guard trackingReady, let arView else { tags = []; return }

        let camPos = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        let forward = -SIMD3<Float>(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)

        var newTags: [ScreenTag] = []
        for anchor in anchors {
            guard let house = housesByAnchor[anchor.identifier] else { continue }
            let base = anchor.transform.columns.3
            let world = SIMD3<Float>(base.x, base.y + 3.0, base.z)   // tag ~3m above ground
            let rel = world - camPos
            let dist = Double(simd_length(rel))
            guard dist > 4, dist < 140 else { continue }
            guard simd_dot(simd_normalize(rel), forward) > 0.15 else { continue }  // behind camera
            guard let pt = arView.project(world) else { continue }
            guard pt.x > -60, pt.x < arView.bounds.width + 60,
                  pt.y > -40, pt.y < arView.bounds.height + 40 else { continue }
            newTags.append(ScreenTag(id: house.id, point: pt, distance: dist,
                                     title: house.addrShort ?? "House", price: house.price))
        }
        // nearest first; drop tags that would overlap an already-kept one
        newTags.sort { $0.distance < $1.distance }
        var kept: [ScreenTag] = []
        for tag in newTags where kept.count < 8 {
            if kept.allSatisfy({ abs($0.point.x - tag.point.x) > 90 || abs($0.point.y - tag.point.y) > 44 }) {
                kept.append(tag)
            }
        }
        tags = kept
    }
}

// MARK: - CLLocationManagerDelegate

extension ARManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startSessionIfAvailable()
            case .denied, .restricted:
                self.fatalMessage = "Location access is required — enable it in Settings → Privacy."
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.fetchHousesIfNeeded(near: loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
