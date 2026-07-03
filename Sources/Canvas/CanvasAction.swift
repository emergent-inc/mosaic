import Foundation
import CmuxCanvas
import CmuxCanvasUI

/// Every user-invokable canvas operation, behind one shared entrypoint.
///
/// Keyboard shortcuts, the command palette, the View menu, and the
/// `canvas.*` debug-socket verbs all construct a `CanvasAction` and run it
/// through ``CanvasActionExecutor`` — no surface carries its own logic.
enum CanvasAction: Equatable {
    /// Toggle the workspace between split and canvas layout.
    case toggleLayout
    /// Scroll the focused pane fully into view.
    case revealFocusedPane
    /// Toggle the fit-all overview zoom.
    case toggleOverview
    /// Zoom in one step, anchored at the viewport center.
    case zoomIn
    /// Zoom out one step, anchored at the viewport center.
    case zoomOut
    /// Return to 100% magnification.
    case zoomReset
    /// Apply an alignment/distribution/tidy command to all panes.
    case alignment(CanvasAlignmentCommand)

    var analyticsID: String {
        switch self {
        case .toggleLayout:
            return "canvas.toggle_layout"
        case .revealFocusedPane:
            return "canvas.reveal_focused_pane"
        case .toggleOverview:
            return "canvas.toggle_overview"
        case .zoomIn:
            return "canvas.zoom_in"
        case .zoomOut:
            return "canvas.zoom_out"
        case .zoomReset:
            return "canvas.zoom_reset"
        case .alignment(let command):
            return "canvas.alignment.\(command.rawValue)"
        }
    }
}

extension KeyboardShortcutSettings.Action {
    /// All shortcut actions that map onto canvas actions, in dispatch order.
    static let canvasActions: [KeyboardShortcutSettings.Action] = [
        .toggleCanvasLayout,
        .canvasRevealFocusedPane,
        .canvasOverview,
        .canvasZoomIn,
        .canvasZoomOut,
        .canvasZoomReset,
        .canvasTidy,
        .canvasAlignLeft,
        .canvasAlignRight,
        .canvasAlignTop,
        .canvasAlignBottom,
        .canvasEqualizeWidths,
        .canvasEqualizeHeights,
        .canvasDistributeHorizontally,
        .canvasDistributeVertically,
    ]

    /// The canvas action this shortcut action runs, if any.
    var canvasAction: CanvasAction? {
        switch self {
        case .toggleCanvasLayout: return .toggleLayout
        case .canvasRevealFocusedPane: return .revealFocusedPane
        case .canvasOverview: return .toggleOverview
        case .canvasZoomIn: return .zoomIn
        case .canvasZoomOut: return .zoomOut
        case .canvasZoomReset: return .zoomReset
        case .canvasTidy: return .alignment(.tidy)
        case .canvasAlignLeft: return .alignment(.alignLeft)
        case .canvasAlignRight: return .alignment(.alignRight)
        case .canvasAlignTop: return .alignment(.alignTop)
        case .canvasAlignBottom: return .alignment(.alignBottom)
        case .canvasEqualizeWidths: return .alignment(.equalizeWidths)
        case .canvasEqualizeHeights: return .alignment(.equalizeHeights)
        case .canvasDistributeHorizontally: return .alignment(.distributeHorizontally)
        case .canvasDistributeVertically: return .alignment(.distributeVertically)
        default: return nil
        }
    }
}

/// Executes ``CanvasAction``s against a workspace. The single shared
/// execution path for every canvas entrypoint.
@MainActor
struct CanvasActionExecutor {
    let workspace: Workspace

    /// One keyboard/palette zoom step (matches typical app zoom increments).
    static let zoomStepFactor: CGFloat = 1.25

    /// Runs the action. Returns `false` when the action does not apply
    /// (for example a canvas-only action while the workspace is in splits).
    @discardableResult
    func perform(_ action: CanvasAction) -> Bool {
        let didPerform: Bool
        switch action {
        case .toggleLayout:
            workspace.toggleCanvasLayout()
            didPerform = true
        case .revealFocusedPane:
            if workspace.layoutMode == .canvas,
               let panelId = workspace.focusedPanelId {
                workspace.canvasModel.viewport?.revealPane(panelId, animated: true)
                didPerform = true
            } else {
                didPerform = false
            }
        case .toggleOverview:
            if workspace.layoutMode == .canvas {
                workspace.canvasModel.viewport?.toggleOverview()
                didPerform = true
            } else {
                didPerform = false
            }
        case .zoomIn:
            if workspace.layoutMode == .canvas {
                workspace.canvasModel.viewport?.zoom(by: Self.zoomStepFactor)
                didPerform = true
            } else {
                didPerform = false
            }
        case .zoomOut:
            if workspace.layoutMode == .canvas {
                workspace.canvasModel.viewport?.zoom(by: 1 / Self.zoomStepFactor)
                didPerform = true
            } else {
                didPerform = false
            }
        case .zoomReset:
            if workspace.layoutMode == .canvas {
                workspace.canvasModel.viewport?.resetZoom()
                didPerform = true
            } else {
                didPerform = false
            }
        case .alignment(let command):
            if workspace.layoutMode == .canvas {
                let changed = workspace.canvasModel.applyAlignment(
                    command,
                    to: [],
                    reference: workspace.focusedPanelId
                )
                if changed {
                    workspace.canvasModel.viewport?.modelDidChangeExternally(animated: true)
                }
                didPerform = changed
            } else {
                didPerform = false
            }
        }
        PostHogAnalytics.shared.trackAction(
            actionID: action.analyticsID,
            surface: "canvas",
            entrypoint: "shared_executor",
            source: "CanvasActionExecutor.perform",
            result: didPerform ? "performed" : "not_applicable"
        )
        return didPerform
    }
}
