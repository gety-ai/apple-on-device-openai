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
struct ServerConfiguration {
    var host: String
    var port: Int

    static let `default` = ServerConfiguration(
        host: "0.0.0.0",
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
    @Published var hostInput: String = "0.0.0.0"
    @Published var portInput: String = "11535"
    @Published var isModelAvailable: Bool = false
    @Published var modelUnavailableReason: String?
    @Published var isCheckingModel: Bool = false

    private let serverManager = VaporServerManager()

    var isRunning: Bool {
        serverManager.isRunning
    }

    var lastError: String? {
        serverManager.lastError
    }

    // Public URLs that the UI shows
    private var advertisedHost: String {
        if configuration.host == "0.0.0.0" {
            return Self.localIPAddress() ?? "127.0.0.1"
        } else {
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

    init() {
        // Initialize with current configuration values
        self.hostInput = configuration.host
        self.portInput = String(configuration.port)

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
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            configuration.host = trimmedHost
        }

        if let port = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)),
            port > 0 && port <= 65535
        {
            configuration.port = port
        }
    }

    func resetToDefaults() {
        configuration = ServerConfiguration.default
        hostInput = configuration.host
        portInput = String(configuration.port)
    }

    func copyToClipboard(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // Networking helpers
    private static func localIPAddress() -> String? {
        var addrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPointer) == 0 else { return nil }
        defer { freeifaddrs(addrPointer) }

        var ptr = addrPointer
        while ptr != nil {
            let iface = ptr!.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) { // IPv4
                let name = String(cString: iface.ifa_name)
                // Typical Apple interface names (en0 Wi‑Fi, en1 Ethernet/USB‑C)
                if name == "en0" || name == "en1" {
                    var addr = iface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addr,
                                socklen_t(iface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                0,
                                NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
            ptr = iface.ifa_next
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
                            Text("Host:")
                                .frame(width: 60, alignment: .leading)
                            TextField("127.0.0.1", text: $viewModel.hostInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(viewModel.isRunning)
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
