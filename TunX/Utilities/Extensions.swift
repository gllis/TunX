//
//  Extensions.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import SwiftUI

extension String {
    /// 空字符串转为 nil，便于可选路径字段存储。
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Tunnel {
    /// 侧边栏展示用：取第一条转发规则的类型图标。
    var firstRuleType: ForwardType {
        rules.first?.type ?? .local
    }
}
