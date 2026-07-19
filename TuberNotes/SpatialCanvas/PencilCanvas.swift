import PencilKit
import SwiftUI

struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let penFixture: PenFixture?
#if DEBUG
    @EnvironmentObject private var agentSession: AgentInteractionSession
#endif

    func makeCoordinator() -> Coordinator {
#if DEBUG
        Coordinator(drawing: $drawing, session: agentSession)
#else
        Coordinator(drawing: $drawing)
#endif
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = FixtureCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas
        canvas.pendingFixture = penFixture

        DispatchQueue.main.async {
            guard canvas.window != nil else { return }
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
            context.coordinator.toolPicker = picker
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
#if DEBUG
        context.coordinator.session = agentSession
#endif
        guard context.coordinator.loadedFixtureName != penFixture?.name else { return }
        (canvas as? FixtureCanvasView)?.pendingFixture = penFixture
        context.coordinator.loadedFixtureName = penFixture?.name
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?
        var loadedFixtureName: String?
        var drawing: Binding<PKDrawing>
#if DEBUG
        var session: AgentInteractionSession

        init(drawing: Binding<PKDrawing>, session: AgentInteractionSession) {
            self.drawing = drawing
            self.session = session
            super.init()
        }
#else
        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
            super.init()
        }
#endif

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
#if DEBUG
            Task { @MainActor in
                session.handleDrawingChange(drawing: canvasView.drawing, canvasSize: canvasView.bounds.size)
            }
#endif
        }
    }
}

private final class FixtureCanvasView: PKCanvasView {
    var pendingFixture: PenFixture? {
        didSet { setNeedsLayout() }
    }
    private var appliedFixtureName: String?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0,
              bounds.height > 0,
              let pendingFixture,
              appliedFixtureName != pendingFixture.name else { return }
        drawing = pendingFixture.makeDrawing(in: bounds.size)
        appliedFixtureName = pendingFixture.name
    }
}
