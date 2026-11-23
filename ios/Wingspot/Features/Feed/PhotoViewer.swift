import Account
import SwiftUI

/// A photo shown big on a dark background. Swipe sideways for the other photos of the check-in, pinch to zoom,
/// double-tap to zoom in or out, and swipe up or down or tap the close button to leave. A zoomed photo is moved with
/// one finger.
///
/// The swipe to close sits around the whole pager, not on each photo: a drag gesture on a photo takes the sideways swipe
/// away from the pager (#292). It only reacts to a drag that is mostly vertical, and only while no photo is zoomed.
struct PhotoViewer: View {
    let photos: [FeedPhoto]
    @State private var selection: UUID
    /// How far the photos follow the finger while swiping to close.
    @State private var dragY: CGFloat = 0
    /// True once a drag was recognised as the swipe to close, until the finger lifts.
    @State private var isClosing = false
    /// Reported by the photos: one of them is zoomed in, so a drag moves it and does not close the viewer.
    @State private var isZoomed = false
    @Environment(\.dismiss) private var dismiss

    init(photos: [FeedPhoto], start: FeedPhoto) {
        self.photos = photos
        _selection = State(initialValue: start.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    ZoomablePhoto(url: photo.url, isZoomed: $isZoomed)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .offset(y: dragY)
            .simultaneousGesture(swipeToClose)
            .onChange(of: selection) { isZoomed = false }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
                    .padding()
            }
            .accessibilityLabel("Close")
        }
        // Fades while the photos are pulled away, so it is clear that letting go closes it.
        .presentationBackground(.black.opacity(0.92 * (1 - min(1, abs(dragY) / 300))))
    }

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isZoomed else { return }
                if !isClosing, abs(value.translation.height) > abs(value.translation.width) { isClosing = true }
                if isClosing { dragY = value.translation.height }
            }
            .onEnded { value in
                defer { isClosing = false }
                guard isClosing else { return }
                // Far enough, or flicked: closes. Otherwise the photos settle back.
                if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dragY = 0 }
                }
            }
    }
}

private struct ZoomablePhoto: View {
    let url: URL
    @Binding var isZoomed: Bool

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
                    // A one-finger drag only moves a zoomed photo. Not zoomed, it must stay free for the page view around
                    // the photos: a drag gesture here would take the sideways swipe to the next photo.
                    .simultaneousGesture(drag, including: scale > 1 ? .all : .none)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onChange(of: scale) { isZoomed = scale > 1 }
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
                offset = CGSize(width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
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
