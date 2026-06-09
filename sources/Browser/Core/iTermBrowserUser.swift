//
//  iTermBrowserUser.swift
//  iTerm2
//
//  Created by George Nachman on 6/26/25.
//


enum iTermBrowserUser: Hashable, Equatable {
    case regular(id: UUID)
    case devNull

    // The shared identity used by the default (non-dev-null) browser user. All
    // regular browser sessions use this so they share one WKWebsiteDataStore.
    static let defaultRegularID = UUID(uuidString: "AC0E9812-7F88-478B-B361-5526082EDDB3")!
}

extension iTermBrowserUser: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .regular(id: let id):
            return "iTermBrowserUser.regular(\(id))"
        case .devNull:
            return "iTermBrowserUser.devNull"
        }
    }
}
