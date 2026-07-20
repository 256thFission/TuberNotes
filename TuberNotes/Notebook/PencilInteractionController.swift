import UIKit

/// Apple Pencil Pro side-tap and squeeze handling for the notebook canvas.
///
/// Split out of `NotebookCanvas.Coordinator`, which already carries four
/// protocol conformances. `ZoomablePageView` owns an instance and attaches the
/// interaction to *itself* rather than to the `PKCanvasView`: `UIPencilHoverPose`
/// reports `location` in the interaction view's coordinate space, and the
/// floating palette is positioned in that same space, so anchoring here avoids
/// converting through the zooming scroll view on every zoom and scroll.
final class PencilInteractionController: NSObject, UIPencilInteractionDelegate {
    /// Toggle the eraser against the previously-used tool.
    var onToggleEraser: (() -> Void)?
    /// Unconditionally swap to the previously-used tool.
    var onSwapPreviousTool: (() -> Void)?
    /// Show the palette limited to color swatches, at the given point.
    var onShowColorPalette: ((CGPoint) -> Void)?
    /// Toggle the full shortcut palette at the given point.
    var onSqueeze: ((CGPoint) -> Void)?

    /// Where to put the palette when the pencil isn't hovering (`hoverPose` is
    /// nil off-hover, and on iPads older than M2 it's always nil).
    var fallbackPoint: (() -> CGPoint)?

    var isDoubleTapEnabled = true
    var isSqueezeEnabled = true

    private(set) lazy var interaction = UIPencilInteraction(delegate: self)

    /// The user's Settings preference for whether hovering shows a tool preview.
    /// Read-only — the hover dot honors it rather than overriding it. There's no
    /// system preview to suppress here, since the notebook uses a custom toolbar
    /// rather than `PKToolPicker`.
    static var prefersHoverPreview: Bool { UIPencilInteraction.prefersHoverToolPreview }

    private func point(_ pose: UIPencilHoverPose?) -> CGPoint {
        pose?.location ?? fallbackPoint?() ?? .zero
    }

    // MARK: UIPencilInteractionDelegate

    // Only the iOS 17.5 methods are implemented. The deprecated
    // `pencilInteractionDidTap(_:)` is deliberately absent — implementing both
    // is documented to deliver only the new one, but keeping it out makes that
    // unambiguous.

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard isDoubleTapEnabled else { return }
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            onToggleEraser?()
        case .switchPrevious:
            onSwapPreviousTool?()
        case .showColorPalette:
            onShowColorPalette?(point(tap.hoverPose))
        case .ignore:
            break
        default:
            // `.showInkAttributes`, `.showContextualPalette`, `.runSystemShortcut`,
            // and anything added later. The enum is non-frozen, so this switch
            // can't be exhaustive anyway.
            break
        }
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard isSqueezeEnabled else { return }
        // Act on `.began` for GoodNotes' immediate feel; the palette then stays
        // up until it's squeezed again, acted on, or tapped away, so the other
        // phases are noise.
        guard squeeze.phase == .began else { return }
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        onSqueeze?(point(squeeze.hoverPose))
    }
}
