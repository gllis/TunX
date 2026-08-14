//
//  Extensions.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI

extension TunnelState {
    var color: Color {
        switch self {
        case .stopped:
            return Color.secondary
        case .starting, .stopping, .reconnecting:
            return Color.orange
        case .running:
            return Color.green
        case .error:
            return Color.red
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Tunnel {
    var firstRuleType: ForwardType {
        rules.first?.type ?? .local
    }
}
