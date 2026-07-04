import Bonsplit
import Foundation

enum MosaicSurfaceTabBarBuiltInAction: String, Codable, Sendable, CaseIterable, Hashable {
    case newWorkspace = "mosaic.newWorkspace"
    case cloudVM = "mosaic.cloudvm"
    case newTerminal = "mosaic.newTerminal"
    case newBrowser = "mosaic.newBrowser"
    case splitRight = "mosaic.splitRight"
    case splitDown = "mosaic.splitDown"

    init?(configID: String) {
        switch configID {
        case "mosaic.newWorkspace", "newWorkspace":
            self = .newWorkspace
        case "mosaic.cloudvm", "mosaic.cloudVM", "cloudVM", "cloudvm",
             "mosaic.newCloudVM", "mosaic.newCloudVm", "newCloudVM", "newCloudVm",
             "mosaic.startCloudVM", "mosaic.startCloudVm", "startCloudVM", "startCloudVm":
            self = .cloudVM
        case "mosaic.newTerminal", "newTerminal":
            self = .newTerminal
        case "mosaic.newBrowser", "newBrowser":
            self = .newBrowser
        case "mosaic.splitRight", "splitRight":
            self = .splitRight
        case "mosaic.splitDown", "splitDown":
            self = .splitDown
        default:
            return nil
        }
    }

    var configID: String {
        rawValue
    }

    var defaultIcon: String {
        switch self {
        case .newWorkspace:
            return "plus.square"
        case .cloudVM:
            return "cloud"
        case .newTerminal:
            return "plus"
        case .newBrowser:
            return "globe"
        case .splitRight:
            return "square.split.2x1"
        case .splitDown:
            return "square.split.1x2"
        }
    }

    var bonsplitAction: BonsplitConfiguration.SplitActionButton.Action? {
        switch self {
        case .newWorkspace, .cloudVM:
            return nil
        case .newTerminal:
            return .newTerminal
        case .newBrowser:
            return .newBrowser
        case .splitRight:
            return .splitRight
        case .splitDown:
            return .splitDown
        }
    }
}
