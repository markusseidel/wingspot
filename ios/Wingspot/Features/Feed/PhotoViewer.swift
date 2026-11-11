import Account
import SwiftUI

/// A photo shown big on a dark background. Swipe sideways for the other photos of the check-in, pinch to zoom,
/// double-tap to zoom in or out, and swipe down or tap the close button to leave.
struct PhotoViewer: View {
    let photos: [FeedPhoto]
    @State private var selection: UUID
    @Environment(\.dismiss) private var dismiss

    init(photos: [FeedPhoto], start: FeedPhoto) {
        self.photos = photos
        _selection = State(initialValue: start.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    ZoomablePhoto(url: photo.url, onSwipeDown: { dismiss() })
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
                    .padding()
            }
            .accessibilityLabel("Close")
        }
        .presentationBackground(.black.opacity(0.92))
    }
}

private struct ZoomablePhoto: View {
    let url: URL
    let onSwipeDown: () -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoom)
                    .simultaneousGesture(drag)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .accessibilityLabel("Photo")
            case .failure:
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            default:
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { scale = max(1, baseScale * $0.magnification) }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1.01 { reset() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                // Zoomed in, the picture moves. Otherwise a drag down is the way out.
                if scale > 1 {
                    offset = CGSize(width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height)
                } else {
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if scale > 1 {
                    baseOffset = offset
                } else if value.translation.height > 120 {
                    onSwipeDown()
                } else {
                    withAnimation { offset = .zero }
                }
            }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 }
        }
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}
