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

    /// Pencil Pro shortcut palette. The anchor is in screen space; the canvas
    /// reports it that way so this view doesn't need to know the canvas's
    /// padding or whether the page strip is showing.
    @State private var pencilPaletteAnchor: CGPoint?
    @State private var pencilPaletteMode: PencilShortcutPalette.Mode = .full

    init(notebook: Notebook, store: NotebookStore) {
        _vm = StateObject(wrappedValue: NotebookViewModel(notebook: notebook, store: store))
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                if showStrip {
                    PageStripView(vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                pageArea
            }

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
                    undo: vm.undo,
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

            // Above the toolbar (7), below the page navigator (8).
            if pencilPaletteAnchor != nil {
                pencilPaletteLayer
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(7.5)
            }

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
        .onChange(of: vm.currentPageID) { _, _ in dismissPencilPalette() }
        .onChange(of: vm.isLassoActive) { _, active in if active { dismissPencilPalette() } }
        .onChange(of: vm.isArrangingImages) { _, active in if active { dismissPencilPalette() } }
        .onDisappear { vm.persistNow() }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: Pencil shortcut palette

    private var pencilPaletteLayer: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let anchor = pencilPaletteAnchor ?? .zero
            // Screen space -> this layer's space.
            let local = CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY)
            let size = estimatedPaletteSize

            ZStack(alignment: .topLeading) {
                // Tap-away dismissal.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissPencilPalette() }

                PencilShortcutPalette(
                    vm: vm,
                    undo: vm.undo,
                    mode: pencilPaletteMode,
                    onAction: { dismissPencilPalette() }
                )
                .position(clampedPalettePosition(near: local, size: size, in: geo.size))
            }
        }
        .ignoresSafeArea()
    }

    /// The palette has no intrinsic size until it lays out, so clamping uses an
    /// estimate. Close enough: the clamp only has to keep it on screen.
    private var estimatedPaletteSize: CGSize {
        let width: CGFloat = 212
        let swatchRows = max(1, Int(ceil(Double(vm.settings.favoriteColors.count) / 5.0)))
        let hasColors = !vm.settings.favoriteColors.isEmpty
        var height: CGFloat = 28  // vertical padding
        if hasColors { height += CGFloat(swatchRows) * 30 + CGFloat(swatchRows - 1) * 10 }
        if pencilPaletteMode == .full {
            if hasColors { height += 13 }   // separator + spacing
            height += 34 + 12               // tools
            height += 13                    // separator + spacing
            height += 34                    // undo/redo
        }
        return CGSize(width: width, height: height)
    }

    /// Offsets the palette down-right of the pencil tip (so the hand doesn't
    /// cover it), then pulls it back inside the visible bounds near a page edge.
    private func clampedPalettePosition(near point: CGPoint, size: CGSize, in bounds: CGSize) -> CGPoint {
        let margin: CGFloat = 12
        let tipOffset: CGFloat = 28

        var center = CGPoint(x: point.x + tipOffset + size.width / 2,
                             y: point.y + tipOffset + size.height / 2)

        // Flip to the other side of the tip if that would run off the edge.
        if center.x + size.width / 2 > bounds.width - margin {
            center.x = point.x - tipOffset - size.width / 2
        }
        if center.y + size.height / 2 > bounds.height - margin {
            center.y = point.y - tipOffset - size.height / 2
        }

        center.x = min(max(center.x, margin + size.width / 2), bounds.width - margin - size.width / 2)
        center.y = min(max(center.y, margin + size.height / 2), bounds.height - margin - size.height / 2)
        return center
    }

    private func showPencilPalette(at screenPoint: CGPoint, colorsOnly: Bool) {
        let mode: PencilShortcutPalette.Mode = colorsOnly ? .colorsOnly : .full
        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
            // A second squeeze closes it; a double-tap in a different mode
            // re-opens it rather than toggling off.
            if pencilPaletteAnchor != nil, pencilPaletteMode == mode {
                pencilPaletteAnchor = nil
            } else {
                pencilPaletteMode = mode
                pencilPaletteAnchor = screenPoint
            }
        }
    }

    private func dismissPencilPalette() {
        guard pencilPaletteAnchor != nil else { return }
        withAnimation(.easeOut(duration: 0.16)) { pencilPaletteAnchor = nil }
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
            undo: vm.undo,
            pencilDoubleTapEnabled: vm.settings.pencilDoubleTapEnabled,
            pencilSqueezeEnabled: vm.settings.pencilSqueezeEnabled,
            pencilHoverPreviewEnabled: vm.settings.pencilHoverPreviewEnabled,
            onChange: { vm.updateCurrentDrawing($0) },
            onPencilToggleEraser: { vm.togglePencilEraser() },
            onPencilSwapTool: { vm.swapToPreviousTool() },
            onPencilShowPalette: { point, colorsOnly in
                showPencilPalette(at: point, colorsOnly: colorsOnly)
            },
            onLongPress: { withAnimation { showPages = true } },
            onZoomChanged: { vm.zoomScale = $0 },
            onLassoChanged: { vm.lassoRect = $0 },
            onImagesChanged: { vm.updateImages($0) },
            onSelectImage: { vm.selectImage($0) }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 74)
        .id(vm.currentPageID)
        .accessibilityIdentifier("notebook-page-area")
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
