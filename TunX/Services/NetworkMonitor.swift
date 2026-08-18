//
//  NetworkMonitor.swift
//  TunX
//
//  Created by glli on 2026/8/18.
//

import Foundation
import Network
import Combine

/// 监听系统网络路径，供隧道在无网时暂停重连、有网后恢复。
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    /// 是否存在可建立连接的网络路径。
    @Published private(set) var isSatisfied = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "TunX.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.isSatisfied != satisfied {
                    self.isSatisfied = satisfied
                }
            }
        }
        monitor.start(queue: queue)
    }
}
