//
//  Extensions.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI

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
