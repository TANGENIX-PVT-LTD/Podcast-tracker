import SwiftUI

enum PodSpacing {
    static let page: CGFloat = 20
    static let section: CGFloat = 24
    static let card: CGFloat = 16
}

struct IOSGlassSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 22,
        interactive: Bool = false,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            interactive
                                ? Glass.clear.tint(tint).interactive()
                                : Glass.clear.tint(tint),
                            in: .rect(cornerRadius: cornerRadius, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .light
                                ? Color(.systemBackground).opacity(0.84)
                                : Color.white.opacity(0.07)
                        )
                        .shadow(
                            color: colorScheme == .light ? Color.black.opacity(0.05) : .clear,
                            radius: 8,
                            y: 2
                        )
                }
            }
            .overlay {
                if #unavailable(iOS 26.0) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                }
            }
    }
}

struct IOSLoadingStatus: View {
    let title: String
    var detail: String?
    var onDarkBackground = false

    var body: some View {
        IOSGlassSurface(cornerRadius: 22) {
            HStack(spacing: 13) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(onDarkBackground ? .white : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(onDarkBackground ? Color.white.opacity(0.68) : Color.secondary)
                    }
                }
            }
            .foregroundStyle(onDarkBackground ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Flat container on the page, outlined like Duolingo's iOS app. Lift is reserved for buttons.
private struct PodCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSoft: Bool

    func body(content: Content) -> some View {
        content.outlined(cornerRadius)
    }
}

extension View {
    func podCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(PodCardModifier(cornerRadius: cornerRadius, isSoft: false))
    }

    func podSoftCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PodCardModifier(cornerRadius: cornerRadius, isSoft: true))
    }
}

struct PodcastThumbnail: View {
    let podcast: Podcast
    var width: CGFloat?
    var height: CGFloat

    var body: some View {
        AsyncImage(url: podcast.thumbnailURL.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                ZStack { placeholder; ProgressView().tint(.white) }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: min(16, height * 0.16), style: .continuous))
        .overlay(alignment: .center) {
            Image(systemName: "play.fill")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(9)
                .background(.black.opacity(0.58), in: Circle())
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(colors: [.indigo.opacity(0.8), .cyan.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { Image(systemName: "headphones").font(.title2).foregroundStyle(.white.opacity(0.8)) }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Double {
    var podTimestamp: String {
        let total = max(0, Int(self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
