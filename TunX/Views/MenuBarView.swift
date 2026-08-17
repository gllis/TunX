//
//  MenuBarView.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tunnel.createdAt) private var tunnels: [Tunnel]
    @StateObject private var manager = TunnelManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tunnels.isEmpty {
                Text("暂无隧道")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ForEach(tunnels) { tunnel in
                    let status = manager.status(for: tunnel)
                    Button {
                        manager.toggle(tunnel)
                    } label: {
                        HStack {
                            Circle()
                                .fill(status.state.color)
                                .frame(width: 6, height: 6)
                            Text(tunnel.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(status.state.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                NotificationCenter.default.post(name: .openTunXMainWindow, object: nil)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "arrow.up.forward.app")
                    Text("打开 TunX")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .padding(.vertical, 8)
    }
}
