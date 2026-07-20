import Combine
import Foundation

/// Owns the `UndoManager` the notebook canvas registers strokes against.
///
/// This can't live on `ZoomablePageView`: `NotebookView` applies
/// `.id(vm.currentPageID)` to the canvas, so the representable and its views are
/// destroyed on every page turn. The bridge hangs off `NotebookViewModel`
/// instead and is handed down, which also lets the toolbar drive undo/redo.
///
/// `UndoManager` isn't Combine-observable, so `canUndo`/`canRedo` are mirrored
/// from its notifications.
@MainActor
final class NotebookUndoBridge: ObservableObject {
    let manager = UndoManager()

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var observers: [NSObjectProtocol] = []

    init() {
        // groupsByEvent (the default) is what makes one stroke one undo step.
        manager.groupsByEvent = true

        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
            .NSUndoManagerCheckpoint,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: manager, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// `NSUndoManagerCheckpoint` fires very frequently and `@Published` emits
    /// even when the value is unchanged, so this must compare before assigning
    /// or SwiftUI re-renders mid-stroke.
    private func refresh() {
        if canUndo != manager.canUndo { canUndo = manager.canUndo }
        if canRedo != manager.canRedo { canRedo = manager.canRedo }
    }

    func undo() {
        guard manager.canUndo else { return }
        manager.undo()
        refresh()
    }

    func redo() {
        guard manager.canRedo else { return }
        manager.redo()
        refresh()
    }

    /// Per-page undo stacks: called when the canvas loads a different page.
    func reset() {
        manager.removeAllActions()
        refresh()
    }

    /// Runs `body` with undo registration off, so programmatic `drawing`
    /// assignments don't land on the stack as user-visible steps.
    func withoutRegistration(_ body: () -> Void) {
        manager.disableUndoRegistration()
        body()
        manager.enableUndoRegistration()
    }
}
