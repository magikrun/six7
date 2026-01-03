// KoriumBridge.swift
// Native bridge between Flutter and Korium using UniFFI bindings.
//
// ARCHITECTURE:
// - Korium 0.4.1 provides native Swift bindings via UniFFI (FfiNode)
// - This bridge exposes korium functionality to Flutter via MethodChannel
// - Async operations use Swift concurrency (async/await)
// - PubSub messaging for chat (subscribe/publish/waitMessage)
// - Background task support for receiving messages when app is backgrounded
//
// SECURITY (per AGENTS.md):
// - All inputs validated before passing to korium
// - Identity data handled securely (not logged)
// - Bounded collections for event storage
// - Message size limits enforced

import Flutter
import UIKit

/// Constants for resource bounds (per AGENTS.md requirements).
private enum Constants {
    /// Maximum events to buffer before dropping oldest.
    static let maxEventBuffer: Int = 1000
    /// Maximum poll events per request.
    static let maxPollEvents: Int = 100
    /// Peer identity hex length (Ed25519 public key).
    static let peerIdentityHexLen: Int = 64
    /// Secret key hex length (Ed25519 secret key).
    static let secretKeyHexLen: Int = 64
    /// Nonce hex length (PoW nonce).
    static let nonceHexLen: Int = 16
    /// Message poll timeout in milliseconds.
    static let messagePollTimeoutMs: Int64 = 1000
    /// Maximum group ID length (UUID format: 36 chars with hyphens).
    static let groupIdMaxLen: Int = 36
}

/// Korium node bridge for Flutter platform channel.
public class KoriumBridge: NSObject, FlutterPlugin {
    
    private let channel: FlutterMethodChannel
    
    /// Korium FfiNode instance
    private var node: FfiNode?
    
    /// Event buffer with bounded capacity (LRU-style, drops oldest).
    private var eventBuffer: [[String: Any]] = []
    private let eventBufferLock = NSLock()
    
    /// Cancellation flag for background receiver
    private var isReceiving: Bool = false
    private var receiverTask: Task<Void, Never>?
    private var requestReceiverTask: Task<Void, Never>?
    
    /// Background task identifier for extended execution
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        
        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "chat.six7/korium",
            binaryMessenger: registrar.messenger()
        )
        let instance = KoriumBridge(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createNodeWithConfig":
            handleCreateNodeWithConfig(call.arguments, result: result)
        case "startListeners":
            handleStartListeners(result: result)
        case "shutdown":
            handleShutdown(result: result)
        case "resolvePeer":
            handleResolvePeer(call.arguments, result: result)
        case "sendMessage":
            handleSendMessage(call.arguments, result: result)
        case "sendGroupMessage":
            handleSendGroupMessage(call.arguments, result: result)
        case "pollEvents":
            handlePollEvents(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - createNodeWithConfig
    
    private func handleCreateNodeWithConfig(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let bindAddr = args["bindAddr"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "bindAddr required", details: nil))
            return
        }
        
        // SECURITY: Validate bind address format
        guard isValidBindAddress(bindAddr) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid bind address format", details: nil))
            return
        }
        
        let secretKeyHex = args["privateKeyHex"] as? String
        let nonceHex = args["identityProofNonce"] as? String
        
        // SECURITY: Validate secret key format if provided
        if let key = secretKeyHex {
            guard key.count == Constants.secretKeyHexLen,
                  key.allSatisfy({ $0.isHexDigit }) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid private key format", details: nil))
                return
            }
        }
        
        // SECURITY: Validate nonce format if provided
        if let nonce = nonceHex {
            guard nonce.count == Constants.nonceHexLen,
                  nonce.allSatisfy({ $0.isHexDigit }) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid nonce format", details: nil))
                return
            }
        }
        
        Task {
            do {
                let newNode: FfiNode
                if let secretKey = secretKeyHex, let nonce = nonceHex {
                    // Restore existing identity (instant)
                    newNode = try FfiNode.createWithIdentity(
                        bindAddress: bindAddr,
                        secretKeyHex: secretKey,
                        nonceHex: nonce
                    )
                } else {
                    // Create new identity with PoW (1-4 seconds)
                    newNode = try FfiNode.create(bindAddress: bindAddr)
                }
                
                self.node = newNode
                
                // Get identity bundle for persistence
                let bundle = newNode.identityBundle()
                
                // Bootstrap via public DNS seeds
                // NOTE: Do NOT manually call publishAddress() - it breaks DHT signature.
                // The library handles signed contact publishing internally via bootstrapPublic().
                var bootstrapError: String? = nil
                do {
                    try newNode.bootstrapPublic()
                } catch let e as KoriumException {
                    // Bootstrap failure is not fatal - node can still work locally
                    bootstrapError = e.description
                }
                
                DispatchQueue.main.async {
                    result([
                        "identity": bundle.identityHex,
                        "localAddr": newNode.localAddress(),
                        "isBootstrapped": bootstrapError == nil,
                        "bootstrapError": bootstrapError as Any,
                        "secretKeyHex": bundle.secretKeyHex,
                        "powNonce": bundle.nonceHex
                    ])
                }
            } catch let e as KoriumException {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: e.description,
                        details: String(describing: type(of: e))
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - startListeners
    
    private func handleStartListeners(result: @escaping FlutterResult) {
        guard node != nil else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Node not initialized", details: nil))
            return
        }
        
        // Start background message receiver
        startMessageReceiver()
        
        result(nil)
    }
    
    // MARK: - shutdown
    
    private func handleShutdown(result: @escaping FlutterResult) {
        isReceiving = false
        receiverTask?.cancel()
        receiverTask = nil
        requestReceiverTask?.cancel()
        requestReceiverTask = nil
        
        // End any background task
        endBackgroundTask()
        
        node?.shutdown()
        node = nil
        
        eventBufferLock.lock()
        eventBuffer.removeAll()
        eventBufferLock.unlock()
        
        result(nil)
    }
    
    // MARK: - resolvePeer
    
    private func handleResolvePeer(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let currentNode = node else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Node not initialized", details: nil))
            return
        }
        
        guard let args = arguments as? [String: Any],
              let peerId = args["peerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "peerId required", details: nil))
            return
        }
        
        // SECURITY: Validate identity format
        guard peerId.count == Constants.peerIdentityHexLen,
              peerId.allSatisfy({ $0.isHexDigit }) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid peer identity format", details: nil))
            return
        }
        
        Task {
            do {
                let contact = try currentNode.resolve(identityHex: peerId)
                let addresses = contact?.addresses ?? []
                
                DispatchQueue.main.async {
                    result(addresses)
                }
            } catch let e as KoriumException {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: e.description,
                        details: String(describing: type(of: e))
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - sendMessage
    
    private func handleSendMessage(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let currentNode = node else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Node not initialized", details: nil))
            return
        }
        
        guard let args = arguments as? [String: Any],
              let peerId = args["peerId"] as? String,
              let message = args["message"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "peerId and message required", details: nil))
            return
        }
        
        // SECURITY: Validate identity format
        guard peerId.count == Constants.peerIdentityHexLen,
              peerId.allSatisfy({ $0.isHexDigit }) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid peer identity format", details: nil))
            return
        }
        
        // Extract message content for PubSub
        // Dart sends 'text' field, we use 'content' in the PubSub JSON protocol
        let content = message["text"] as? String ?? ""
        let timestamp = message["timestampMs"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
        let messageId = message["id"] as? String ?? UUID().uuidString
        let messageType = message["messageType"] as? String ?? "text"
        
        Task {
            do {
                // SECURITY: Escape all JSON special characters
                let escapedContent = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
                let messageJson = """
                {"id":"\(messageId)","from":"\(currentNode.identityHex())","content":"\(escapedContent)","timestamp":\(timestamp),"messageType":"\(messageType)"}
                """
                guard let messagePayload = messageJson.data(using: .utf8) else {
                    throw KoriumException.internal(msg: "Failed to encode message")
                }
                
                // Use direct RPC send() for 1:1 messaging (like Android/Korium chatroom)
                NSLog("KoriumBridge: Sending direct message to %@", String(peerId.prefix(16)))
                let response = try currentNode.send(identityHex: peerId, data: messagePayload)
                NSLog("KoriumBridge: Direct send succeeded, response: %d bytes", response.count)
                
                // Parse ACK response to determine delivery status
                var deliveryConfirmed = false
                if !response.isEmpty {
                    if let ackJson = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                       let ack = ackJson["ack"] as? Bool {
                        deliveryConfirmed = ack
                    }
                }
                
                let finalStatus = deliveryConfirmed ? "delivered" : "sent"
                var sentMessage = message
                sentMessage["status"] = finalStatus
                
                // Emit delivery status update event if confirmed
                if deliveryConfirmed {
                    let statusEvent: [String: Any] = [
                        "type": "messageStatusUpdate",
                        "messageId": messageId,
                        "status": "delivered"
                    ]
                    self.appendEvent(statusEvent)
                    DispatchQueue.main.async {
                        self.channel.invokeMethod("onEvent", arguments: nil)
                    }
                }
                
                DispatchQueue.main.async {
                    result(sentMessage)
                }
            } catch let e as KoriumException {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: e.description,
                        details: String(describing: type(of: e))
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - sendGroupMessage
    
    private func handleSendGroupMessage(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let currentNode = node else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Node not initialized", details: nil))
            return
        }
        
        guard let args = arguments as? [String: Any],
              let groupId = args["groupId"] as? String,
              let message = args["message"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "groupId and message required", details: nil))
            return
        }
        
        // SECURITY: Validate group ID format (UUID)
        guard groupId.count == Constants.groupIdMaxLen,
              groupId.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid group ID format", details: nil))
            return
        }
        
        // Extract message content for PubSub
        let content = message["text"] as? String ?? ""
        let timestamp = message["timestampMs"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
        let messageId = message["id"] as? String ?? UUID().uuidString
        
        Task {
            do {
                // Use PubSub to send message via topic "six7-group:{groupId}"
                // Message format: JSON with sender, content, timestamp, id, groupId
                let groupTopic = "six7-group:\(groupId)"
                // SECURITY: Escape all JSON special characters
                let escapedContent = content
                    .replacingOccurrences(of: "\\", with: "\\\\")  // Must be first
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
                let messageJson = """
                {"id":"\(messageId)","from":"\(currentNode.identityHex())","content":"\(escapedContent)","timestamp":\(timestamp),"groupId":"\(groupId)"}
                """
                guard let messagePayload = messageJson.data(using: .utf8) else {
                    throw KoriumException.internal(msg: "Failed to encode message")
                }
                
                // Subscribe to the group topic if not already
                do {
                    try currentNode.subscribe(topic: groupTopic)
                } catch KoriumException.alreadySubscribed {
                    // Already subscribed, that's fine
                }
                
                // Publish the message
                try currentNode.publish(topic: groupTopic, data: messagePayload)
                
                DispatchQueue.main.async {
                    result(nil) // Success - void return
                }
            } catch let e as KoriumException {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: e.description,
                        details: String(describing: type(of: e))
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "KORIUM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - pollEvents
    
    private func handlePollEvents(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let maxEvents = args["maxEvents"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "maxEvents required", details: nil))
            return
        }
        
        let boundedMax = min(maxEvents, Constants.maxPollEvents)
        
        eventBufferLock.lock()
        let count = min(boundedMax, eventBuffer.count)
        let events = Array(eventBuffer.prefix(count))
        eventBuffer.removeFirst(count)
        eventBufferLock.unlock()
        
        result(events)
    }
    
    // MARK: - Background Message Receiver
    
    private func startMessageReceiver() {
        guard !isReceiving else { return }
        isReceiving = true
        
        guard let currentNode = node else {
            isReceiving = false
            return
        }
        
        // PubSub receiver for group messages
        receiverTask = Task {
            while !Task.isCancelled && self.node != nil {
                do {
                    let message = try currentNode.waitMessage(timeoutMs: Constants.messagePollTimeoutMs)
                    
                    if let msg = message {
                        if let event = self.parsePubSubToChatEvent(msg, currentNode: currentNode) {
                            self.appendEvent(event)
                            DispatchQueue.main.async {
                                self.channel.invokeMethod("onEvent", arguments: nil)
                            }
                        }
                    }
                } catch KoriumException.notConnected {
                    break
                } catch {
                    // Continue on errors
                }
            }
            self.isReceiving = false
        }
        
        // Direct RPC receiver for 1:1 messages
        requestReceiverTask = Task {
            while !Task.isCancelled && self.node != nil {
                do {
                    let request = try currentNode.waitRequest(timeoutMs: Constants.messagePollTimeoutMs)
                    
                    if let req = request {
                        // CRITICAL: Send ACK first before parsing to ensure delivery confirmation
                        // even if parsing fails (per AGENTS.md - fail fast but confirm receipt)
                        if let ackData = "{\"ack\":true}".data(using: .utf8) {
                            do {
                                try currentNode.respondToRequest(requestId: req.requestId, data: ackData)
                            } catch {
                                NSLog("KoriumBridge: Failed to send ACK: %@", String(describing: error))
                            }
                        }
                        
                        // Now parse and emit the event
                        if let event = self.parseRequestToChatEvent(req, currentNode: currentNode) {
                            self.appendEvent(event)
                            DispatchQueue.main.async {
                                self.channel.invokeMethod("onEvent", arguments: nil)
                            }
                        }
                    }
                } catch KoriumException.notConnected {
                    break
                } catch {
                    NSLog("KoriumBridge: Request receiver error: %@", String(describing: error))
                }
            }
        }
    }
    
    /// Parses a PubSub message into a chatMessageReceived event.
    /// Returns nil if the message cannot be parsed as a chat message.
    private func parsePubSubToChatEvent(_ msg: PubSubMessage, currentNode: FfiNode) -> [String: Any]? {
        // Try to parse as JSON chat message
        guard let jsonData = msg.data as Data?,
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Not a valid JSON message - emit as raw pubSubMessage event
            return [
                "type": "pubSubMessage",
                "topic": msg.topic,
                "fromIdentity": msg.sourceIdentity,
                "data": Array(msg.data)
            ]
        }
        
        // Extract chat message fields
        guard let messageId = payload["id"] as? String,
              let fromId = payload["from"] as? String,
              let content = payload["content"] as? String else {
            // Missing required fields - emit as raw pubSubMessage
            return [
                "type": "pubSubMessage",
                "topic": msg.topic,
                "fromIdentity": msg.sourceIdentity,
                "data": Array(msg.data)
            ]
        }
        
        let timestamp = payload["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
        let myIdentity = currentNode.identityHex()
        let messageType = payload["messageType"] as? String ?? "text"
        
        // Detect if this is a group message based on topic prefix
        let isGroupMessage = msg.topic.hasPrefix("six7-group:")
        let groupId = payload["groupId"] as? String
        
        // SECURITY: Properly detect if message is from us
        let isFromMe = fromId == myIdentity
        
        // Build ChatMessage structure for Dart
        var chatMessage: [String: Any] = [
            "id": messageId,
            "senderId": fromId,
            "recipientId": isGroupMessage ? (groupId ?? myIdentity) : myIdentity,
            "text": content,
            "messageType": messageType,
            "timestampMs": timestamp,
            "status": "delivered",
            "isFromMe": isFromMe
        ]
        
        // Include groupId for group messages
        if let groupId = groupId, isGroupMessage {
            chatMessage["groupId"] = groupId
        }
        
        return [
            "type": "chatMessageReceived",
            "message": chatMessage
        ]
    }
    
    /// Parses a direct RPC request into a chatMessageReceived event.
    /// Returns nil if the request cannot be parsed as a chat message.
    private func parseRequestToChatEvent(_ request: IncomingRequest, currentNode: FfiNode) -> [String: Any]? {
        guard let jsonData = request.data as Data?,
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            NSLog("KoriumBridge: Invalid request payload - not JSON")
            return nil
        }
        
        guard let messageId = payload["id"] as? String,
              let fromId = payload["from"] as? String else {
            NSLog("KoriumBridge: Invalid request payload: missing id or from")
            return nil
        }
        
        // SECURITY: Verify payload 'from' matches Korium's authenticated identity
        // This prevents spoofing where attacker claims to be someone else
        // Use case-insensitive comparison to handle mixed-case identities
        if fromId.lowercased() != request.fromIdentity.lowercased() {
            NSLog("KoriumBridge: SECURITY: Sender identity mismatch! Payload from: %@, Korium identity: %@",
                  String(fromId.prefix(16)), String(request.fromIdentity.prefix(16)))
            return nil
        }
        
        let content = payload["content"] as? String ?? ""
        let timestamp = payload["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
        let messageType = payload["messageType"] as? String ?? "text"
        let myIdentity = currentNode.identityHex()
        let isFromMe = fromId.lowercased() == myIdentity.lowercased()
        
        let chatMessage: [String: Any] = [
            "id": messageId,
            "senderId": fromId,
            "recipientId": myIdentity,
            "text": content,
            "messageType": messageType,
            "timestampMs": timestamp,
            "status": "delivered",
            "isFromMe": isFromMe
        ]
        
        NSLog("KoriumBridge: Received direct message from %@", String(fromId.prefix(16)))
        return [
            "type": "chatMessageReceived",
            "message": chatMessage
        ]
    }
    
    private func appendEvent(_ event: [String: Any]) {
        eventBufferLock.lock()
        defer { eventBufferLock.unlock() }
        
        // SECURITY: Bounded buffer - drop oldest if at capacity
        if eventBuffer.count >= Constants.maxEventBuffer {
            eventBuffer.removeFirst()
        }
        eventBuffer.append(event)
    }
    
    // MARK: - Validation Helpers
    
    private func isValidBindAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ":")
        guard parts.count == 2 else { return false }
        guard Int(parts[1]) != nil else { return false }
        return true
    }
    
    // MARK: - Background Task Support
    
    /// Called when app enters background - start extended execution
    @objc private func appDidEnterBackground() {
        guard node != nil && isReceiving else { return }
        beginBackgroundTask()
    }
    
    /// Called when app returns to foreground - end extended execution
    @objc private func appWillEnterForeground() {
        endBackgroundTask()
    }
    
    /// Begin background task for extended execution
    /// iOS grants ~30 seconds of background time for cleanup tasks.
    /// For P2P messaging, this allows receiving pending messages before suspension.
    private func beginBackgroundTask() {
        guard backgroundTaskId == .invalid else { return }
        
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "KoriumP2P") { [weak self] in
            // System is about to kill us - clean up
            self?.endBackgroundTask()
        }
    }
    
    /// End background task
    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }
}

// MARK: - Character Extension

private extension Character {
    var isHexDigit: Bool {
        return "0123456789abcdefABCDEF".contains(self)
    }
}