import SwiftUI
import UIKit

/// Editor for one notebook: the zoomable page on a dark backdrop, a frosted
/// floating tool bar, a toggleable top page strip, a template menu, and the
/// frosted assistant sidebar (with lasso selection) that floats over the page.
struct NotebookView: View {
    @StateObject private var vm: NotebookViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tuber.fingerDrawing") private var fingerDrawing = false
    @AppStorage("tuber.snapStraight") private var snapStraight = true

    @State private var showPages = false
    @State private var showStrip = false
    @State private var showSidebar = false
    @State private var showKeyPopup = false
    @State private var isPageLocked = false
    @State private var exportItem: ExportItem?
    @StateObject private var rippleModel = AmbientRippleModel()

    // Interactive page-flip state.
    @State private var flipDX: CGFloat = 0
    @State private var isFlipAnimating = false
    @State private var containerWidth: CGFloat = 1024

    private let sidebarShift: CGFloat = 348

    init(notebook: Notebook, store: NotebookStore) {
        _vm = StateObject(wrappedValue: NotebookViewModel(notebook: notebook, store: store))
    }

    var body: some View {
        ZStack {
            AmbientBackground(rippleModel: rippleModel)

            // Passive, non-blocking touch observer feeds ripples. It never
            // intercepts input, so drawing / tools / scrolling keep priority.
            AmbientTouchLayer { point in rippleModel.add(at: point) }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if showStrip {
                    PageStripView(vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                pageArea
            }
            .padding(.trailing, showSidebar ? sidebarShift : 0)

            // Assistant floats OVER the page (doesn't shrink it).
            if showSidebar {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AgentSidebarView(
                        vm: vm,
                        onClose: { withAnimation { showSidebar = false } },
                        onEditKey: { withAnimation { showKeyPopup = true } }
                    )
                }
                .transition(.move(edge: .trailing))
                .zIndex(5)
            }

            if vm.isArrangingImages {
                arrangeControls.zIndex(6)
            }

            VStack {
                Spacer()
                NotebookToolbar(
                    vm: vm,
                    isPageLocked: $isPageLocked,
                    isLassoActive: $vm.isLassoActive,
                    onHome: { vm.persistNow(); dismiss() },
                    onShowPages: { withAnimation { showPages = true } },
                    onExportPDF: { exportPage(.pdf) },
                    onExportArchive: { exportPage(.archive) }
                )
                .padding(.bottom, 16)
                .padding(.trailing, showSidebar ? 348 : 0)
            }
            .zIndex(7)

            if showPages {
                PageFlipOverlay(vm: vm) { withAnimation { showPages = false } }
                    .transition(.opacity)
                    .zIndex(8)
            }

            if showKeyPopup {
                APIKeyPopup { withAnimation { showKeyPopup = false } }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
        .navigationTitle(vm.notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { vm.persistNow(); dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityIdentifier("notebook-back")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation { showStrip.toggle() } } label: {
                    Image(systemName: showStrip ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                }
                .accessibilityIdentifier("nav-page-strip")

                templateMenu

                Button { withAnimation { showSidebar.toggle() } } label: {
                    Image(systemName: showSidebar ? "sparkles.rectangle.stack.fill" : "sparkles")
                }
                .accessibilityIdentifier("nav-assistant")
            }
        }
        .onDisappear { vm.persistNow() }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: Export

    private enum ExportKind { case pdf, archive }

    private func exportPage(_ kind: ExportKind) {
        let data: Data?
        let ext: String
        switch kind {
        case .pdf:     data = vm.exportPDF();     ext = "pdf"
        case .archive: data = vm.exportArchive(); ext = "spud"
        }
        guard let data else { return }
        let safeTitle = vm.notebook.title.isEmpty ? "Notebook" : vm.notebook.title
        let name = "\(safeTitle)-p\(vm.currentIndex + 1).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            exportItem = ExportItem(url: url)
        } catch {
            vm.exportError = error.localizedDescription
        }
    }

    private var templateMenu: some View {
        Menu {
            Picker("Template", selection: Binding(get: { vm.currentTemplate }, set: { vm.setTemplate($0) })) {
                ForEach(PageTemplate.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Toggle("Snap to straight line", isOn: $snapStraight)
            Toggle("Finger drawing", isOn: $fingerDrawing)
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .accessibilityIdentifier("nav-template")
    }

    private var arrangeControls: some View {
        VStack {
            HStack(spacing: 10) {
                Label("Move & pinch to resize", systemImage: "hand.draw")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                Divider().frame(height: 18).overlay(.white.opacity(0.3))
                Button(role: .destructive) { vm.deleteSelectedImage() } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(vm.selectedImageID == nil)
                Button("Done") { withAnimation { vm.finishArrangingImages() } }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .environment(\.colorScheme, .dark)
            .padding(.top, 12)
            Spacer()
        }
    }

    private var pageArea: some View {
        NotebookCanvas(
            pageID: vm.currentPageID,
            drawingData: vm.currentPage.drawingData,
            tool: vm.tool,
            color: vm.inkUIColor,
            width: vm.activeWidth,
            template: vm.currentTemplate,
            zoomScale: vm.zoomScale,
            fingerDrawing: fingerDrawing,
            isLassoActive: vm.isLassoActive,
            lassoRect: vm.lassoRect,
            snapStraight: snapStraight,
            images: vm.currentPage.images,
            isArrangingImages: vm.isArrangingImages,
            selectedImageID: vm.selectedImageID,
            onChange: { vm.updateCurrentDrawing($0) },
            onLongPress: { withAnimation { showPages = true } },
            onZoomChanged: { vm.zoomScale = $0 },
            onLassoChanged: { vm.lassoRect = $0 },
            onImagesChanged: { vm.updateImages($0) },
            onSelectImage: { vm.selectImage($0) },
            onFlipChanged: { tx in handleFlipChanged(tx) },
            onFlipEnded: { tx, vx in handleFlipEnded(tx, vx) }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 74)
        .offset(x: flipDX)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        )
        .accessibilityIdentifier("notebook-page-area")
    }

    // MARK: Interactive page flip

    private func handleFlipChanged(_ tx: CGFloat) {
        guard !isFlipAnimating else { return }
        var d = tx
        // Rubber-band when there's no page to flip to in that direction.
        if (d < 0 && !vm.canGoForward) || (d > 0 && !vm.canGoBack) {
            d *= 0.28
        }
        flipDX = d
    }

    private func handleFlipEnded(_ tx: CGFloat, _ vx: CGFloat) {
        guard !isFlipAnimating else { return }
        let width = max(containerWidth, 320)
        let threshold = width * 0.28
        let goNext = (tx < -threshold || vx < -800) && vm.canGoForward
        let goPrev = (tx > threshold || vx > 800) && vm.canGoBack

        if goNext {
            completeFlip(next: true, width: width)
        } else if goPrev {
            completeFlip(next: false, width: width)
        } else {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) { flipDX = 0 }
        }
    }

    /// Slide the current page out in the drag direction, swap, then slide the
    /// new page in from the opposite side — a tactile turn rather than a fade.
    private func completeFlip(next: Bool, width: CGFloat) {
        isFlipAnimating = true
        withAnimation(.easeOut(duration: 0.18)) { flipDX = next ? -width : width }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if next { vm.goForward() } else { vm.goBack() }
            flipDX = next ? width : -width          // pre-position new page off-screen
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.20)) { flipDX = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    isFlipAnimating = false
                }
            }
        }
    }
}

/// Identifiable wrapper so a freshly-written export file can drive `.sheet(item:)`.
private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Minimal UIActivityViewController bridge for sharing/saving an exported file.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
