# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a macOS SwiftUI application that creates an OpenAI-compatible API server using Apple's on-device Foundation Models. The server exposes local Apple Intelligence models through familiar OpenAI API endpoints, enabling developers to use Apple's on-device AI with existing OpenAI-compatible tools.

**Important**: This is a GUI application (not a CLI tool) to avoid Apple's rate limiting policies for Foundation Models. Command-line tools are rate-limited, but foreground GUI apps are not.

## Requirements

- macOS 26 beta 2 or newer
- Xcode 26 beta 2 (for building)
- Apple Intelligence must be enabled in Settings > Apple Intelligence & Siri
- Device must support Apple Intelligence (Mac with Apple Silicon)

## Building and Running

### Build and run in Xcode:
```bash
open AppleOnDeviceOpenAI.xcodeproj
# Then build and run using Xcode (Cmd+R)
```

### Testing the server:
```bash
python3 test_server.py
```

The test script verifies server health, model availability, OpenAI SDK compatibility, multi-turn conversations, multilingual support, and streaming functionality.

## Architecture

### Core Components

**VaporServerManager** (`Services/VaporServerManager.swift`)
- Main HTTP server using the Vapor framework
- Manages server lifecycle (start/stop)
- Configures OpenAI-compatible API routes
- Handles both streaming and non-streaming responses
- **Important**: Bootstraps logging system only once per process to avoid errors when restarting server

**OnDeviceModelManager** (`Services/OnDeviceModelManager.swift`)
- Actor-isolated manager for Apple's SystemLanguageModel
- Checks model availability and returns detailed error reasons
- Converts OpenAI chat messages to Apple's Transcript format
- Handles conversation context by converting message history to transcript entries
- Supports temperature and max_tokens parameters

**ContentView** (`ContentView.swift`)
- Main UI with server configuration and status
- Displays server URLs, endpoints, and integration examples
- Provides network interface picker for bind address (127.0.0.1, 0.0.0.0, or specific IPs)
- Includes refresh button to rescan network interfaces
- Shows LAN visibility warning when binding to non-localhost addresses

**OpenAIModels** (`Models/OpenAIModels.swift`)
- Defines OpenAI-compatible request/response structures
- Uses snake_case for JSON keys (e.g., `max_tokens`, `finish_reason`)
- All models are `nonisolated` and `Sendable` for actor isolation safety
- Includes streaming-specific models (`ChatCompletionStreamResponse`, `ChatCompletionDelta`)

### Message Flow

1. Client sends OpenAI-compatible request to `/v1/chat/completions`
2. VaporServerManager validates request and extracts messages array
3. OnDeviceModelManager converts message history (excluding last message) to Transcript entries
4. System messages → Transcript.Instructions
5. User messages → Transcript.Prompt
6. Assistant messages → Transcript.Response
7. Last message becomes the current prompt
8. LanguageModelSession is created with conversation transcript
9. Response is generated and returned in OpenAI format

### Streaming Implementation

Streaming uses Server-Sent Events (SSE):
- Sets proper headers (`text/event-stream`, `Cache-Control: no-cache`, etc.)
- Uses Vapor's `Response.Body(stream:)` for async streaming
- Tracks cumulative content and sends only deltas
- First chunk includes role ("assistant")
- Final chunk has `finish_reason: "stop"`
- Ends with `data: [DONE]` message

## API Endpoints

- `GET /health` - Health check (returns 200 OK)
- `GET /status` - Model availability, supported languages, server version
- `GET /v1/models` - List available models (OpenAI-compatible)
- `POST /v1/chat/completions` - Chat completions (streaming and non-streaming)

Default server address: `http://127.0.0.1:11535`

## Common Patterns

### Model Availability Checking
Always check model availability before generating responses. The system provides detailed error reasons:
- `deviceNotEligible` - Hardware doesn't support Apple Intelligence
- `appleIntelligenceNotEnabled` - Settings not configured
- `modelNotReady` - Model still downloading

### Conversation Context
Multi-turn conversations work by passing all previous messages in the request. The manager builds a transcript from message history, maintaining context across turns.

### Actor Isolation
OnDeviceModelManager is an actor to safely manage the SystemLanguageModel. All calls to it use `await` and run on the actor's isolated context.

### Server Configuration Persistence
Server configuration (host/port) is stored in ServerConfiguration struct. The UI uses separate input bindings (`hostInput`, `portInput`) that update the configuration when starting the server.

## Known Issues

- Rate limiting may still occur due to Apple FoundationModels limitations - restart the server if this happens
- Logging system can only be initialized once per process (handled by `loggingBootstrapped` flag)
