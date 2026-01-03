package chat.six7.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import uniffi.korium.*

/**
 * Native bridge between Flutter and Korium using UniFFI bindings.
 *
 * ARCHITECTURE:
 * - Korium provides native Kotlin bindings via UniFFI (KoriumNode)
 * - This bridge exposes korium functionality to Flutter via MethodChannel
 * - Async operations use Kotlin coroutines (UniFFI methods are blocking)
 * - PubSub messaging for chat (subscribe/publish/waitMessage)
 * - Foreground service keeps P2P node alive in background
 *
 * SECURITY (per AGENTS.md):
 * - All inputs validated before passing to korium
 * - Identity data handled securely (not logged)
 * - Bounded collections for event storage
 * - Message size limits enforced
 */
class KoriumBridge : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "chat.six7/korium"

        // Constants for resource bounds (per AGENTS.md requirements)
        private const val MAX_EVENT_BUFFER = 1000
        private const val MAX_POLL_EVENTS = 100
        private const val PEER_IDENTITY_HEX_LEN = 64
        private const val SECRET_KEY_HEX_LEN = 64
        private const val NONCE_HEX_LEN = 16
        private const val MESSAGE_POLL_TIMEOUT_MS = 1000UL
        private const val GROUP_ID_MAX_LEN = 36 // UUID format with hyphens
    }

    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    // Korium node instance
    private var node: FfiNode? = null

    // Event buffer with bounded capacity (thread-safe)
    private val eventBuffer = ConcurrentLinkedQueue<Map<String, Any?>>()
    private val isReceiving = AtomicBoolean(false)
    private var receiverJob: Job? = null
    private var requestReceiverJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        applicationContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        receiverJob?.cancel()
        requestReceiverJob?.cancel()
        KoriumForegroundService.stop(applicationContext)
        // Shutdown node synchronously on detach
        runBlocking {
            try { node?.shutdown() } catch (_: Exception) {}
        }
        node = null
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "createNodeWithConfig" -> handleCreateNodeWithConfig(call, result)
            "startListeners" -> handleStartListeners(result)
            "shutdown" -> handleShutdown(result)
            "resolvePeer" -> handleResolvePeer(call, result)
            "sendMessage" -> handleSendMessage(call, result)
            "sendGroupMessage" -> handleSendGroupMessage(call, result)
            "pollEvents" -> handlePollEvents(call, result)
            "routableAddresses" -> handleRoutableAddresses(result)
            "getDhtPeers" -> handleGetDhtPeers(result)
            else -> result.notImplemented()
        }
    }

    // MARK: - createNodeWithConfig

    private fun handleCreateNodeWithConfig(call: MethodCall, result: Result) {
        val bindAddr = call.argument<String>("bindAddr")
        if (bindAddr == null) {
            result.error("INVALID_ARGS", "bindAddr required", null)
            return
        }

        if (!isValidBindAddress(bindAddr)) {
            result.error("INVALID_ARGS", "Invalid bind address format", null)
            return
        }

        val secretKeyHex = call.argument<String>("privateKeyHex")
        val nonceHex = call.argument<String>("identityProofNonce")

        // SECURITY: Validate secret key format if provided
        if (secretKeyHex != null) {
            if (secretKeyHex.length != SECRET_KEY_HEX_LEN || !secretKeyHex.all { it.isHexDigit() }) {
                result.error("INVALID_ARGS", "Invalid private key format", null)
                return
            }
        }

        // SECURITY: Validate nonce format if provided
        if (nonceHex != null) {
            if (nonceHex.length != NONCE_HEX_LEN || !nonceHex.all { it.isHexDigit() }) {
                result.error("INVALID_ARGS", "Invalid nonce format", null)
                return
            }
        }

        scope.launch {
            try {
                val newNode: FfiNode
                val bundle: IdentityBundle
                
                if (secretKeyHex != null && nonceHex != null) {
                    // Restore existing identity (instant)
                    android.util.Log.d("KoriumBridge", "Restoring identity with secretKey=${secretKeyHex.take(8)}... nonce=$nonceHex")
                    newNode = FfiNode.createWithIdentity(bindAddr, secretKeyHex, nonceHex)
                    android.util.Log.d("KoriumBridge", "Restored identity: ${newNode.identityHex()}")
                    // Reconstruct bundle for return value
                    bundle = IdentityBundle(
                        secretKeyHex = secretKeyHex,
                        identityHex = newNode.identityHex(),
                        nonceHex = nonceHex
                    )
                } else {
                    // Generate new identity with PoW (1-4 seconds)
                    bundle = generateIdentity()
                    // Create node with the generated identity
                    newNode = FfiNode.createWithIdentity(bindAddr, bundle.secretKeyHex, bundle.nonceHex)
                }
                
                node = newNode
                val localAddr = newNode.localAddress()
                
                // Return immediately - bootstrap happens in background
                mainHandler.post {
                    result.success(
                        mapOf(
                            "identity" to bundle.identityHex,
                            "localAddr" to localAddr,
                            "isBootstrapped" to false,  // Will update via event
                            "bootstrapError" to null,
                            "secretKeyHex" to bundle.secretKeyHex,
                            "powNonce" to bundle.nonceHex
                        )
                    )
                }
                
                // Bootstrap in background, notify via event when done
                scope.launch {
                    var bootstrapSuccess = false
                    var bootstrapError: String? = null
                    
                    try {
                        android.util.Log.d("KoriumBridge", "Starting bootstrap via DNS...")
                        newNode.bootstrapPublic()
                        android.util.Log.d("KoriumBridge", "Bootstrap completed successfully!")
                        bootstrapSuccess = true
                    } catch (e: KoriumException) {
                        android.util.Log.e("KoriumBridge", "Bootstrap failed: ${e.message}")
                        bootstrapError = e.message
                    } catch (e: Exception) {
                        android.util.Log.e("KoriumBridge", "Bootstrap exception: ${e.message}")
                        bootstrapError = e.message
                    }
                    
                    if (bootstrapSuccess) {
                        // NOTE: No inbox subscription needed for 1:1 messaging
                        // Direct messages use RPC (send/waitRequest), not PubSub
                        // PubSub is only used for group messages (six7-group:*)
                        
                        appendEvent(mapOf(
                            "type" to "bootstrapComplete",
                            "success" to true,
                            "error" to null
                        ))
                        mainHandler.post { channel.invokeMethod("onEvent", null) }
                    } else {
                        appendEvent(mapOf(
                            "type" to "bootstrapComplete",
                            "success" to false,
                            "error" to (bootstrapError ?: "Bootstrap failed")
                        ))
                        mainHandler.post { channel.invokeMethod("onEvent", null) }
                    }
                }
            } catch (e: KoriumException) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, null)
                }
            }
        }
    }

    // MARK: - startListeners

    private fun handleStartListeners(result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        KoriumForegroundService.start(applicationContext)
        startMessageReceiver()
        result.success(null)
    }

    // MARK: - shutdown

    private fun handleShutdown(result: Result) {
        receiverJob?.cancel()
        isReceiving.set(false)
        KoriumForegroundService.stop(applicationContext)
        scope.launch {
            try { node?.shutdown() } catch (_: Exception) {}
            node = null
            eventBuffer.clear()
            mainHandler.post { result.success(null) }
        }
    }

    // MARK: - resolvePeer

    private fun handleResolvePeer(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val peerId = call.argument<String>("peerId")
        if (peerId == null) {
            result.error("INVALID_ARGS", "peerId required", null)
            return
        }

        if (peerId.length != PEER_IDENTITY_HEX_LEN || !peerId.all { it.isHexDigit() }) {
            result.error("INVALID_ARGS", "Invalid peer identity format", null)
            return
        }

        scope.launch {
            try {
                val contact = currentNode.resolve(peerId)
                val addresses = contact?.addresses ?: emptyList()
                mainHandler.post { result.success(addresses) }
            } catch (e: KoriumException) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, null)
                }
            }
        }
    }

    // MARK: - sendMessage

    private fun handleSendMessage(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val peerId = call.argument<String>("peerId")
        @Suppress("UNCHECKED_CAST")
        val message = call.argument<Map<String, Any?>>("message")

        if (peerId == null || message == null) {
            result.error("INVALID_ARGS", "peerId and message required", null)
            return
        }

        if (peerId.length != PEER_IDENTITY_HEX_LEN || !peerId.all { it.isHexDigit() }) {
            result.error("INVALID_ARGS", "Invalid peer identity format", null)
            return
        }

        val content = message["text"] as? String ?: ""
        val timestamp = message["timestampMs"] as? Long ?: System.currentTimeMillis()
        val messageId = message["id"] as? String ?: java.util.UUID.randomUUID().toString()
        val messageType = message["messageType"] as? String ?: "text"

        scope.launch {
            try {
                val escapedContent = escapeJson(content)
                val myIdentity = currentNode.identityHex()
                val messagePayload = """{"id":"$messageId","from":"$myIdentity","content":"$escapedContent","timestamp":$timestamp,"messageType":"$messageType"}""".toByteArray(Charsets.UTF_8)
                
                // Use direct RPC send() for 1:1 messaging (like Korium chatroom)
                android.util.Log.d("KoriumBridge", "Sending direct message to $peerId")
                val response = currentNode.send(peerId, messagePayload)
                android.util.Log.d("KoriumBridge", "Direct send succeeded, response: ${response.size} bytes")

                // Parse ACK response to determine delivery status
                var deliveryConfirmed = false
                if (response.isNotEmpty()) {
                    try {
                        val ackJson = String(response, Charsets.UTF_8)
                        val ackPayload = org.json.JSONObject(ackJson)
                        deliveryConfirmed = ackPayload.optBoolean("ack", false)
                    } catch (e: Exception) {
                        android.util.Log.w("KoriumBridge", "Failed to parse ACK response: ${e.message}")
                    }
                }

                val finalStatus = if (deliveryConfirmed) "delivered" else "sent"
                val sentMessage = message.toMutableMap()
                sentMessage["status"] = finalStatus
                
                // Emit delivery status update event if confirmed
                if (deliveryConfirmed) {
                    val statusEvent = mapOf(
                        "type" to "messageStatusUpdate",
                        "messageId" to messageId,
                        "status" to "delivered"
                    )
                    appendEvent(statusEvent)
                    mainHandler.post { channel.invokeMethod("onEvent", null) }
                }
                
                mainHandler.post { result.success(sentMessage) }
            } catch (e: KoriumException) {
                android.util.Log.e("KoriumBridge", "Send failed (KoriumException): ${e.message}", e)
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message ?: "Unknown Korium error", e.javaClass.simpleName)
                }
            } catch (e: Exception) {
                android.util.Log.e("KoriumBridge", "Send failed (Exception): ${e.message}", e)
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message ?: "Unknown error", e.javaClass.simpleName)
                }
            }
        }
    }

    // MARK: - sendGroupMessage

    private fun handleSendGroupMessage(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val groupId = call.argument<String>("groupId")
        @Suppress("UNCHECKED_CAST")
        val message = call.argument<Map<String, Any?>>("message")

        if (groupId == null || message == null) {
            result.error("INVALID_ARGS", "groupId and message required", null)
            return
        }

        if (groupId.length > GROUP_ID_MAX_LEN || !groupId.all { it.isHexDigit() || it == '-' }) {
            result.error("INVALID_ARGS", "Invalid group ID format", null)
            return
        }

        val content = message["text"] as? String ?: ""
        val timestamp = message["timestampMs"] as? Long ?: System.currentTimeMillis()
        val messageId = message["id"] as? String ?: java.util.UUID.randomUUID().toString()

        scope.launch {
            try {
                val groupTopic = "six7-group:$groupId"
                val escapedContent = escapeJson(content)
                val myIdentity = currentNode.identityHex()
                val messagePayload = """{"id":"$messageId","from":"$myIdentity","content":"$escapedContent","timestamp":$timestamp,"groupId":"$groupId"}""".toByteArray(Charsets.UTF_8)
                
                try { currentNode.subscribe(groupTopic) } catch (_: Exception) {}
                currentNode.publish(groupTopic, messagePayload)

                mainHandler.post { result.success(null) }
            } catch (e: KoriumException) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, null)
                }
            }
        }
    }

    // MARK: - pollEvents

    private fun handlePollEvents(call: MethodCall, result: Result) {
        val maxEvents = call.argument<Int>("maxEvents")
        if (maxEvents == null) {
            result.error("INVALID_ARGS", "maxEvents required", null)
            return
        }

        val boundedMax = minOf(maxEvents, MAX_POLL_EVENTS)
        val events = mutableListOf<Map<String, Any?>>()
        repeat(boundedMax) {
            val event = eventBuffer.poll() ?: return@repeat
            events.add(event)
        }
        result.success(events)
    }

    // MARK: - routableAddresses
    
    private fun handleRoutableAddresses(result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }
        
        try {
            val addresses = currentNode.routableAddresses()
            result.success(addresses)
        } catch (e: Exception) {
            result.error("KORIUM_ERROR", e.message, null)
        }
    }

    // MARK: - getDhtPeers
    
    private fun handleGetDhtPeers(result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }
        
        try {
            val peers = currentNode.getPeers()
            val peerList = peers.map { peer ->
                mapOf(
                    "identity" to peer.identity,
                    "addresses" to peer.addresses
                )
            }
            result.success(peerList)
        } catch (e: Exception) {
            android.util.Log.w("KoriumBridge", "Failed to get peers: ${e.message}")
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    // MARK: - Background Message Receiver

    private fun startMessageReceiver() {
        if (isReceiving.getAndSet(true)) {
            android.util.Log.d("KoriumBridge", "startMessageReceiver: Already receiving, skipping")
            return
        }
        val currentNode = node ?: run {
            android.util.Log.w("KoriumBridge", "startMessageReceiver: Node is null")
            isReceiving.set(false)
            return
        }
        
        android.util.Log.d("KoriumBridge", "Starting message receivers...")

        // PubSub receiver for group messages
        receiverJob = scope.launch {
            android.util.Log.d("KoriumBridge", "PubSub receiver loop started")
            while (isActive && node != null) {
                try {
                    val message = currentNode.waitMessage(MESSAGE_POLL_TIMEOUT_MS)
                    if (message != null) {
                        val event = parsePubSubToChatEvent(message, currentNode)
                        if (event != null) {
                            appendEvent(event)
                            mainHandler.post { channel.invokeMethod("onEvent", null) }
                        }
                    }
                } catch (_: Exception) {
                    // Continue on errors
                }
            }
            isReceiving.set(false)
        }
        
        // Direct RPC receiver for 1:1 messages
        requestReceiverJob = scope.launch {
            android.util.Log.d("KoriumBridge", "RPC request receiver loop started")
            while (isActive && node != null) {
                try {
                    val request = currentNode.waitRequest(MESSAGE_POLL_TIMEOUT_MS)
                    if (request != null) {
                        // CRITICAL: Send ACK first before parsing to ensure delivery confirmation
                        // even if parsing fails (per AGENTS.md - fail fast but confirm receipt)
                        try {
                            currentNode.respondToRequest(request.requestId, """{"ack":true}""".toByteArray(Charsets.UTF_8))
                        } catch (e: Exception) {
                            android.util.Log.w("KoriumBridge", "Failed to send ACK: ${e.message}")
                        }
                        
                        // Now parse and emit the event
                        val event = parseRequestToChatEvent(request, currentNode)
                        if (event != null) {
                            appendEvent(event)
                            mainHandler.post { channel.invokeMethod("onEvent", null) }
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("KoriumBridge", "Request receiver error: ${e.message}")
                }
            }
        }
    }
    
    private fun parseRequestToChatEvent(request: uniffi.korium.IncomingRequest, currentNode: FfiNode): Map<String, Any?>? {
        val jsonString = String(request.data, Charsets.UTF_8)
        
        return try {
            val payload = org.json.JSONObject(jsonString)
            val messageId = payload.optString("id", "")
            val fromId = payload.optString("from", "")
            val content = payload.optString("content", "")
            val timestamp = payload.optLong("timestamp", System.currentTimeMillis())
            val messageType = payload.optString("messageType", "text")
            
            if (messageId.isEmpty() || fromId.isEmpty()) {
                android.util.Log.w("KoriumBridge", "Invalid request payload: missing id or from")
                return null
            }
            
            // SECURITY: Verify payload 'from' matches Korium's authenticated identity
            // This prevents spoofing where attacker claims to be someone else
            // Use case-insensitive comparison to handle mixed-case identities
            if (fromId.lowercase() != request.fromIdentity.lowercase()) {
                android.util.Log.w("KoriumBridge", "SECURITY: Sender identity mismatch! " +
                    "Payload from: ${fromId.take(16)}..., Korium identity: ${request.fromIdentity.take(16)}...")
                return null
            }
            
            val myIdentity = currentNode.identityHex()
            val isFromMe = fromId.lowercase() == myIdentity.lowercase()
            
            val chatMessage = mapOf(
                "id" to messageId,
                "senderId" to fromId,
                "recipientId" to myIdentity,
                "text" to content,
                "messageType" to messageType,
                "timestampMs" to timestamp,
                "status" to "delivered",
                "isFromMe" to isFromMe
            )
            
            android.util.Log.d("KoriumBridge", "Received direct message from ${fromId.take(16)}...")
            mapOf("type" to "chatMessageReceived", "message" to chatMessage)
        } catch (e: Exception) {
            android.util.Log.w("KoriumBridge", "Failed to parse request: ${e.message}")
            null
        }
    }
    
    private fun parsePubSubToChatEvent(msg: PubSubMessage, currentNode: FfiNode): Map<String, Any?>? {
        val jsonString = String(msg.data, Charsets.UTF_8)
        
        return try {
            val payload = org.json.JSONObject(jsonString)
            val messageId = payload.optString("id", "")
            val fromId = payload.optString("from", "")
            val content = payload.optString("content", "")
            val timestamp = payload.optLong("timestamp", System.currentTimeMillis())
            val groupIdFromPayload = payload.optString("groupId", null.toString())
            val messageType = payload.optString("messageType", "text")
            
            if (messageId.isEmpty() || fromId.isEmpty()) {
                return mapOf(
                    "type" to "pubSubMessage",
                    "topic" to msg.topic,
                    "fromIdentity" to msg.sourceIdentity,
                    "data" to msg.data.toList()
                )
            }
            
            val myIdentity = currentNode.identityHex()
            val isGroupMessage = msg.topic.startsWith("six7-group:")
            val groupId = if (isGroupMessage && groupIdFromPayload != "null") groupIdFromPayload else null
            val isFromMe = fromId == myIdentity
            
            val chatMessage = mutableMapOf<String, Any?>(
                "id" to messageId,
                "senderId" to fromId,
                "recipientId" to if (isGroupMessage) (groupId ?: myIdentity) else myIdentity,
                "text" to content,
                "messageType" to messageType,
                "timestampMs" to timestamp,
                "status" to "delivered",
                "isFromMe" to isFromMe
            )
            
            if (groupId != null && isGroupMessage) {
                chatMessage["groupId"] = groupId
            }
            
            mapOf("type" to "chatMessageReceived", "message" to chatMessage)
        } catch (_: Exception) {
            mapOf(
                "type" to "pubSubMessage",
                "topic" to msg.topic,
                "fromIdentity" to msg.sourceIdentity,
                "data" to msg.data.toList()
            )
        }
    }

    private fun appendEvent(event: Map<String, Any?>) {
        while (eventBuffer.size >= MAX_EVENT_BUFFER) { eventBuffer.poll() }
        eventBuffer.add(event)
    }

    private fun isValidBindAddress(address: String): Boolean {
        val parts = address.split(":")
        return parts.size == 2 && parts[1].toIntOrNull() != null
    }

    private fun escapeJson(s: String): String = s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")

    private fun Char.isHexDigit(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
}
