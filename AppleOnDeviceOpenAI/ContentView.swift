//
//  ContentView.swift
//  AppleOnDeviceOpenAI
//
//  Created by Channing Dai on 6/15/25.
//

import Combine
import SwiftUI
import Foundation
import Network

// MARK: - Models
struct ServerConfiguration: Codable {
    var host: String
    var port: Int

    static let `default` = ServerConfiguration(
        host: "127.0.0.1",
        port: 11535
    )

    var url: String {
        "http://\(host):\(port)"
    }

    var openaiBaseURL: String {
        "\(url)/v1"
    }

    var chatCompletionsEndpoint: String {
        "\(url)/v1/chat/completions"
    }
}

// MARK: - ViewModel
@MainActor
class ServerViewModel: ObservableObject {
    @Published var configuration = ServerConfiguration.default
    @Published var fileConfiguration = ServerConfiguration.default
    @Published var hostInput: String = "127.0.0.1"
    @Published var portInput: String = "11535"
    @Published var isModelAvailable: Bool = false
    @Published var modelUnavailableReason: String?
    @Published var isCheckingModel: Bool = false

    @Published var availableAddresses: [String] = []
    @Published var selectedAddress: String = "127.0.0.1" {
        didSet { hostInput = selectedAddress }
    }

    private let serverManager = VaporServerManager()

    var isRunning: Bool {
        serverManager.isRunning
    }

    var lastError: String? {
        serverManager.lastError
    }

    /// True whenever the user is binding to something other than 127.0.0.1.
    var needsLANWarning: Bool {
        // Treat “all interfaces” (0.0.0.0) as LAN‑visible too.
        selectedAddress != "127.0.0.1"
    }

    private var advertisedHost: String {
        switch configuration.host {
        case "0.0.0.0":
            // We are listening on *all* interfaces – pick something shareable
            return primaryLANAddress() ?? "127.0.0.1"
        default:
            // The user chose a concrete IP (loop‑back included)
            return configuration.host
        }
    }

    var serverURL: String {
        "http://\(advertisedHost):\(configuration.port)"
    }

    var openaiBaseURL: String {
        "\(serverURL)/v1"
    }

    var chatCompletionsEndpoint: String {
        "\(serverURL)/v1/chat/completions"
    }

    let modelName = "apple-on-device"
    
    func readConfiguration() -> ServerConfiguration {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configDir = homeDir.appendingPathComponent(".config")
        let configFile = homeDir.appendingPathComponent("apple-on-device.json")
        
        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: configDir.path) {
                try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: configFile.path) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]  // make JSON readable
                let data = try encoder.encode(ServerConfiguration.default)
                try data.write(to: configFile)
                print("Created config file with defaults at \(configFile.path)")
            }
            
            print("Reading config at \(configFile.path)")
            let data = try Data(contentsOf: configFile)
            let config = try JSONDecoder().decode(ServerConfiguration.self, from: data)
            return config
            
        } catch {
            let config = ServerConfiguration.default
            print("Error handling config: \(error)")
            return config
        }

        return ServerConfiguration.default
    }

    init() {
        fileConfiguration = readConfiguration()
        refreshAddresses()                              // populate the picker
        selectedAddress = fileConfiguration.host
        
        configuration.host = fileConfiguration.host
        configuration.port = fileConfiguration.port

        // Initialize with current configuration values
        self.hostInput = configuration.host
        self.portInput = String(configuration.port)
        print("Host: \(configuration.host)")
        print("Port: \(configuration.port)")


        // Check model availability on startup
        Task {
            await checkModelAvailability()
        }
    }

    func checkModelAvailability() async {
        isCheckingModel = true

        let result = await aiManager.isModelAvailable()

        isModelAvailable = result.available
        modelUnavailableReason = result.reason
        isCheckingModel = false
    }

    func startServer() async {
        // Check model availability before starting
        await checkModelAvailability()

        guard isModelAvailable else {
            return
        }

        updateConfiguration()
        await serverManager.startServer(configuration: configuration)
    }

    func stopServer() async {
        await serverManager.stopServer()
    }

    private func updateConfiguration() {
        configuration.host = selectedAddress

        if let port = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)),
            port > 0 && port <= 65535
        {
            configuration.port = port
        }
    }

    func resetToDefaults() {
        configuration = ServerConfiguration.default
        selectedAddress = configuration.host
        hostInput = configuration.host
        portInput = String(configuration.port)
    }

    func copyToClipboard(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Refresh the list (e.g. when a new Wi‑Fi network is joined).
    func refreshAddresses() {
        // Put localhost first, keep “all interfaces”, then the rest.
        availableAddresses = ["127.0.0.1", "0.0.0.0"]
            + currentIPv4Addresses().filter { $0 != "127.0.0.1" }
        // Keep selection valid
        if !availableAddresses.contains(selectedAddress) {
            selectedAddress = availableAddresses.first ?? "0.0.0.0"
        }
    }

    /// Returns all IPv4 addresses currently assigned to the device,
    /// sorted and deduplicated (loop‑back first).
    func currentIPv4Addresses() -> [String] {
        var addresses: Set<String> = []

        var addrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPointer) == 0 else { return [] }
        defer { freeifaddrs(addrPointer) }

        var ptr = addrPointer
        while let iface = ptr?.pointee {
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = iface.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    &addr,
                    socklen_t(iface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                addresses.insert(String(cString: hostname))
            }
            ptr = iface.ifa_next
        }

        // Keep loop‑back first, then alphabetical
        return ["127.0.0.1"] + addresses.subtracting(["127.0.0.1"]).sorted()
    }

    /// Return the first non‑loop‑back IPv4 address that is *not* link‑local (169.254.x.x).
    /// Falls back to nil when no such address exists.
    private func primaryLANAddress() -> String? {
        for addr in currentIPv4Addresses() {
            if addr != "127.0.0.1" && !addr.hasPrefix("169.254") {
                return addr          // Wi‑Fi / Ethernet / USB‑C / Thunderbolt, etc.
            }
        }
        return nil
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var viewModel = ServerViewModel()
    @State private var isStarting = false
    @State private var isStopping = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text("Apple On-Device OpenAI API")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text("Local Apple Intelligence through OpenAI-compatible endpoints")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Server Status
                GroupBox("Server Status") {
                    VStack(spacing: 16) {
                        HStack {
                            Circle()
                                .fill(viewModel.isRunning ? Color.green : Color.red)
                                .frame(width: 12, height: 12)

                            Text(viewModel.isRunning ? "Running" : "Stopped")
                                .font(.headline)
                                .foregroundColor(viewModel.isRunning ? .green : .red)

                            Spacer()

                            // Model name badge
                            if viewModel.isRunning {
                                Text(viewModel.modelName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Model Availability Status
                        HStack {
                            Text("Apple Intelligence:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if viewModel.isCheckingModel {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Checking...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Circle()
                                    .fill(viewModel.isModelAvailable ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)

                                Text(viewModel.isModelAvailable ? "Available" : "Not Available")
                                    .font(.subheadline)
                                    .foregroundColor(viewModel.isModelAvailable ? .green : .orange)
                            }

                            Spacer()

                            if !viewModel.isModelAvailable && !viewModel.isCheckingModel {
                                Button("Retry") {
                                    Task {
                                        await viewModel.checkModelAvailability()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }

                        // Model unavailable reason
                        if !viewModel.isModelAvailable,
                            let reason = viewModel.modelUnavailableReason
                        {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Issue:")
                                    .font(.caption)
                                    .foregroundColor(.orange)

                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        if let error = viewModel.lastError {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Error:")
                                    .font(.caption)
                                    .foregroundColor(.red)

                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        HStack {
                            if viewModel.isRunning {
                                Button("Stop Server") {
                                    Task {
                                        isStopping = true
                                        await viewModel.stopServer()
                                        isStopping = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isStopping)
                                .tint(.red)
                            } else {
                                Button(
                                    viewModel.isModelAvailable
                                        ? "Start Server" : "Model Not Available"
                                ) {
                                    Task {
                                        isStarting = true
                                        await viewModel.startServer()
                                        isStarting = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(
                                    isStarting || !viewModel.isModelAvailable
                                        || viewModel.isCheckingModel
                                )
                                .tint(viewModel.isModelAvailable ? .green : .gray)
                            }

                            if isStarting || isStopping {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                }

                // OpenAI API Integration - Only show when running
                if viewModel.isRunning {
                    GroupBox("OpenAI API Integration") {
                        VStack(spacing: 16) {
                            // Base URL for OpenAI clients
                            APIEndpointRow(
                                title: "Base URL",
                                subtitle: "For OpenAI Python/JavaScript clients",
                                url: viewModel.openaiBaseURL,
                                onCopy: { viewModel.copyToClipboard(viewModel.openaiBaseURL) }
                            )

                            Divider()

                            // Chat Completions Endpoint
                            APIEndpointRow(
                                title: "Chat Completions",
                                subtitle: "Direct API endpoint",
                                url: viewModel.chatCompletionsEndpoint,
                                onCopy: {
                                    viewModel.copyToClipboard(viewModel.chatCompletionsEndpoint)
                                }
                            )

                            Divider()

                            // Model Name
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Model Name")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Use this in your API requests")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack {
                                    Text(viewModel.modelName)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)

                                    Button("Copy") {
                                        viewModel.copyToClipboard(viewModel.modelName)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // Quick Start Examples
                    GroupBox("Quick Start") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Python Example:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            let pythonCode = """
                                from openai import OpenAI

                                client = OpenAI(
                                    base_url="\(viewModel.openaiBaseURL)",
                                    api_key="not-needed"
                                )

                                response = client.chat.completions.create(
                                    model="\(viewModel.modelName)",
                                    messages=[{"role": "user", "content": "Hello!"}]
                                )
                                """

                            CodeBlock(
                                code: pythonCode,
                                onCopy: {
                                    viewModel.copyToClipboard(pythonCode)
                                })
                        }
                    }
                }

                // Server Configuration
                GroupBox("Server Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Bind Address", selection: $viewModel.selectedAddress) {
                                ForEach(viewModel.availableAddresses, id: \.self) { addr in
                                    Text(addr == "0.0.0.0" ? "All interfaces (0.0.0.0)" : addr).tag(addr)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(viewModel.isRunning)

                            Button {
                                viewModel.refreshAddresses()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .imageScale(.medium)      // optional: size the symbol
                            }
                            .help("Rescan network interfaces")
                            .disabled(viewModel.isRunning)
                        }

                        // LAN‑visibility warning
                        if viewModel.needsLANWarning {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Binding to this address makes the server reachable by other devices\n" +
                                     "on your local network. Make sure you trust the network or use a firewall.")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }

                        HStack {
                            Text("Port:")
                                .frame(width: 60, alignment: .leading)
                            TextField("11535", text: $viewModel.portInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(viewModel.isRunning)
                        }

                        HStack {
                            Spacer()
                            Button("Reset to Defaults") {
                                viewModel.resetToDefaults()
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isRunning)
                        }
                    }
                }

                // Available endpoints - More compact version
                if viewModel.isRunning {
                    GroupBox("All Available Endpoints") {
                        VStack(alignment: .leading, spacing: 8) {
                            EndpointRow(method: "GET", path: "/health", description: "Health check")
                            EndpointRow(method: "GET", path: "/status", description: "Model status")
                            EndpointRow(
                                method: "GET", path: "/v1/models", description: "List models")
                            EndpointRow(
                                method: "POST", path: "/v1/chat/completions",
                                description: "Chat completions")
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: 600)
    }
}

// MARK: - Helper Views
struct APIEndpointRow: View {
    let title: String
    let subtitle: String
    let url: String
    let onCopy: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Text(url)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)

                Button("Copy") {
                    onCopy()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct CodeBlock: View {
    let code: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button("Copy Code") {
                onCopy()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String

    var body: some View {
        HStack {
            Text(method)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor.opacity(0.2))
                .foregroundColor(methodColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(path)
                .font(.system(.body, design: .monospaced))

            Text("•")
                .foregroundColor(.secondary)

            Text(description)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var methodColor: Color {
        switch method {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "DELETE": return .red
        default: return .gray
        }
    }
}

#Preview {
    ContentView()
}
