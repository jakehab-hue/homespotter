import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let manager: ARManager
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        manager.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var ar = ARManager()
    @State private var showingSettings = false
    @State private var keyDraft = ""

    var body: some View {
        ZStack {
            ARViewContainer(manager: ar).ignoresSafeArea()

            ForEach(ar.tags) { tag in
                TagView(tag: tag)
                    .position(tag.point)
                    .onTapGesture { ar.select(id: tag.id) }
            }

            VStack {
                HStack {
                    Text(ar.statusLine)
                        .font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                    Spacer()
                    Button {
                        keyDraft = RentCast.apiKey
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6), in: Circle())
                    }
                }
                .padding(.horizontal)
                Spacer()
                if let house = ar.selected {
                    HouseCard(house: house) { ar.selected = nil }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }

            if let msg = ar.fatalMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
                    Text(msg).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .padding(32)
            }
        }
        .alert("RentCast API key", isPresented: $showingSettings) {
            TextField("paste key (free at rentcast.io)", text: $keyDraft)
            Button("Save") { RentCast.apiKey = keyDraft.trimmingCharacters(in: .whitespaces) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds price estimates above each house.")
        }
        .statusBarHidden()
    }
}

struct TagView: View {
    let tag: ScreenTag
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 1) {
                if let price = tag.price {
                    Text(formatPrice(price))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color(red: 0.49, green: 0.91, blue: 0.53))
                }
                Text(tag.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(Int(tag.distance))m")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
            Rectangle().fill(.white.opacity(0.7)).frame(width: 2, height: 12)
            Circle().fill(.white).frame(width: 6, height: 6).shadow(radius: 3)
        }
        .fixedSize()
    }
}

struct HouseCard: View {
    let house: House
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let price = house.price {
                    Text(formatPrice(price) + " est.")
                        .font(.title2.bold())
                        .foregroundStyle(Color(red: 0.49, green: 0.91, blue: 0.53))
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }
            }
            Text(house.addrFull ?? house.addrShort ?? "Resolving address…")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                linkButton("Zillow", color: Color(red: 0.07, green: 0.47, blue: 0.88),
                           url: "https://www.zillow.com/homes/\(enc(house.searchQuery))_rb/")
                linkButton("Redfin", color: Color(red: 0.78, green: 0.13, blue: 0.13),
                           url: "https://www.google.com/search?q=\(enc(house.searchQuery))+site%3Aredfin.com")
                linkButton("Google", color: Color(white: 0.3),
                           url: "https://www.google.com/search?q=\(enc(house.searchQuery))")
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    @ViewBuilder
    private func linkButton(_ label: String, color: Color, url: String) -> some View {
        if let u = URL(string: url) {
            Link(label, destination: u)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(color, in: Capsule())
        }
    }
}
