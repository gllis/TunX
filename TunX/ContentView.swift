//
//  ContentView.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tunnel.createdAt, order: .reverse) private var tunnels: [Tunnel]

    @StateObject private var manager = TunnelManager.shared
    @State private var selectedTunnelID: UUID?

    var selectedTunnel: Tunnel? {
        tunnels.first { $0.id == selectedTunnelID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTunnelID) {
                ForEach(tunnels) { tunnel in
                    NavigationLink(value: tunnel.id) {
                        TunnelListRowView(tunnel: tunnel)
                    }
                    .tag(tunnel.id)
                }
                .onDelete(perform: deleteTunnels)
            }
            .navigationTitle("隧道")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Button(action: addTunnel) {
                        Label("新建隧道", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button(action: deleteSelectedTunnel) {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(selectedTunnel == nil)
                }
            }
        } detail: {
            if let tunnel = selectedTunnel {
                TunnelEditorView(tunnel: tunnel)
                    .id(tunnel.id)
            } else {
                ContentUnavailableView {
                    Label("未选择隧道", systemImage: "network")
                } description: {
                    Text("点击左侧 + 创建或选择一条隧道")
                }
            }
        }
    }

    private func addTunnel() {
        let defaultRule = ForwardRule(
            type: .local,
            localHost: "127.0.0.1",
            localPort: 8080,
            remoteHost: "localhost",
            remotePort: 80
        )
        let tunnel = Tunnel(
            name: "新隧道",
            host: "example.com",
            port: 22,
            user: "root",
            authMethod: .identityFile,
            rules: [defaultRule]
        )
        modelContext.insert(tunnel)
        selectedTunnelID = tunnel.id
    }

    private func deleteSelectedTunnel() {
        guard let tunnel = selectedTunnel else { return }
        deleteTunnel(tunnel)
    }

    private func deleteTunnels(offsets: IndexSet) {
        for index in offsets {
            deleteTunnel(tunnels[index])
        }
    }

    private func deleteTunnel(_ tunnel: Tunnel) {
        manager.stop(tunnel)
        manager.clearKeychainItems(for: tunnel)
        modelContext.delete(tunnel)
        if selectedTunnelID == tunnel.id {
            selectedTunnelID = nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tunnel.self, ForwardRule.self], inMemory: true)
}
