//
//  TunnelListRowView.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import SwiftUI

/// 侧边栏中单条隧道的名称、目标与连接状态。
struct TunnelListRowView: View {
    let tunnel: Tunnel
    @StateObject private var manager = TunnelManager.shared

    var body: some View {
        let status = manager.status(for: tunnel)

        HStack(spacing: 10) {
            Circle()
                .fill(status.state.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.state.color.opacity(0.5), radius: 2, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: tunnel.firstRuleType.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(tunnel.destination)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(status.state.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
