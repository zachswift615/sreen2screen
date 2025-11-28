import SwiftUI

struct HostListView: View {
    @StateObject private var browser = BonjourBrowser()
    @State private var selectedHost: HostInfo?
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Group {
                if browser.discoveredHosts.isEmpty {
                    VStack(spacing: 20) {
                        if browser.isSearching {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Searching for Macs...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Macs found")
                                .font(.headline)
                            Text("Make sure Screen2Screen Host is running on your Mac")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    List(browser.discoveredHosts) { host in
                        Button(action: { selectedHost = host }) {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .font(.title2)
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading) {
                                    Text(host.name)
                                        .font(.headline)
                                    Text(host.host)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Screen2Screen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .fullScreenCover(item: $selectedHost) { host in
                RemoteSessionView(host: host, onDisconnect: {
                    selectedHost = nil
                })
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onDisappear {
            browser.stopBrowsing()
        }
    }

    private func refresh() {
        browser.discoveredHosts.removeAll()
        browser.stopBrowsing()
        browser.startBrowsing()
    }
}
