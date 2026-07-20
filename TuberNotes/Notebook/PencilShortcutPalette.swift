import SwiftUI
import UIKit

/// Floating shortcut palette summoned by an Apple Pencil Pro squeeze (or by a
/// double-tap when Settings' preferred action is "Show Color Palette").
///
/// Rendered as a sibling layer in `NotebookView`'s ZStack rather than inside
/// `NotebookCanvas`: the canvas carries `.id(currentPageID)` and is rebuilt on
/// every page turn, and a `.popover` would need a UIKit anchor rect that the
/// zooming scroll view keeps invalidating.
struct PencilShortcutPalette: View {
    enum Mode {
        /// Squeeze: colors, tools, and undo/redo.
        case full
        /// Double-tap with the "show color palette" preferred action.
        case colorsOnly
    }

    @ObservedObject var vm: NotebookViewModel
    @ObservedObject var undo: NotebookUndoBridge
    let mode: Mode
    var onAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if !vm.settings.favoriteColors.isEmpty {
                colorRow
            }

            if mode == .full {
                if !vm.settings.favoriteColors.isEmpty {
                    separator
                }
                toolRow
                separator
                undoRow
            }
        }
        .padding(14)
        .frostedGlass(cornerRadius: 20)
        .environment(\.colorScheme, .dark)
        .frame(width: paletteWidth)
        .accessibilityIdentifier("pencil-shortcut-palette")
        .accessibilityElement(children: .contain)
    }

    /// Wide enough for four 34pt tool buttons plus padding; the color row wraps
    /// to the same width.
    private var paletteWidth: CGFloat { 212 }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
    }

    // MARK: Colors

    private var colorRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 5), spacing: 10) {
            ForEach(vm.settings.favoriteColors, id: \.self) { hex in
                swatch(hex)
            }
        }
    }

    // Deliberately not shared with `ColorPalettePopover`'s private `swatch`:
    // that one is sized for a 34pt popover grid and pulls in selection
    // chrome this palette sizes differently.
    private func swatch(_ hex: String) -> some View {
        let ui = UIColor(hex: hex) ?? .black
        let isSelected = vm.inkColorHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            vm.selectColor(hex)
            onAction()
        } label: {
            Circle()
                .fill(Color(ui))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ui.isLight ? Color.black : Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pencil-palette-swatch-\(hex)")
        .accessibilityLabel("Ink color \(hex)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Tools

    private var toolRow: some View {
        HStack(spacing: 6) {
            ForEach(WritingTool.allCases) { tool in
                let selected = vm.tool == tool && !vm.isLassoActive
                Button {
                    vm.selectTool(tool)
                    onAction()
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(selected ? Color.black : Color.white)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity(0.92))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pencil-palette-tool-\(tool.rawValue)")
                .accessibilityLabel(tool.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Undo / redo

    private var undoRow: some View {
        HStack(spacing: 6) {
            paletteButton(
                "arrow.uturn.backward",
                label: "Undo",
                identifier: "pencil-palette-undo",
                enabled: undo.canUndo
            ) {
                undo.undo()
                onAction()
            }
            paletteButton(
                "arrow.uturn.forward",
                label: "Redo",
                identifier: "pencil-palette-redo",
                enabled: undo.canRedo
            ) {
                undo.redo()
                onAction()
            }
        }
    }

    private func paletteButton(
        _ symbol: String,
        label: String,
        identifier: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.28))
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}
