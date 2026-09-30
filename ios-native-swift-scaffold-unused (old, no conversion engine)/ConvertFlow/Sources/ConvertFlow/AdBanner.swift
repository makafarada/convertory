import SwiftUI
import GoogleMobileAds

// TODO: replace with the real Convertory iOS banner ad unit once the AdMob account exists.
// This is Google's public test banner unit; it always serves test ads.
private let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

/// Bottom banner ad shown to free-tier users only. Never shown in the Pro tier.
/// Not used anywhere outside the iOS app (the MS Store / web build has no ads).
struct AdBannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AdBannerViewController {
        AdBannerViewController()
    }

    func updateUIViewController(_ uiViewController: AdBannerViewController, context: Context) {}
}

final class AdBannerViewController: UIViewController {
    private let bannerView = BannerView(adSize: AdSizeBanner)

    override func viewDidLoad() {
        super.viewDidLoad()
        bannerView.adUnitID = bannerAdUnitID
        bannerView.rootViewController = self
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        bannerView.load(Request())
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preferredContentSize = bannerView.adSize.size
    }
}

/// Wraps content with a bottom AdMob banner for free-tier users, matching the Android layout.
struct AdBannerContainer<Content: View>: View {
    let isPro: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
            if !isPro {
                AdBannerView()
                    .frame(height: 50)
            }
        }
    }
}
