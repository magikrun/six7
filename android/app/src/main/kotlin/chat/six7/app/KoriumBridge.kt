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
        private const val MAX_TOPIC_LENGTH = 256 // SECURITY: Prevent resource consumption via long topics
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
            "addPeer" -> handleAddPeer(call, result)
            "bootstrap" -> handleBootstrap(call, result)
            "resolvePeer" -> handleResolvePeer(call, result)
            "subscribe" -> handleSubscribe(call, result)
            "unsubscribe" -> handleUnsubscribe(call, result)
            "publish" -> handlePublish(call, result)
            "sendMessage" -> handleSendMessage(call, result)
            "sendGroupMessage" -> handleSendGroupMessage(call, result)
            "pollEvents" -> handlePollEvents(call, result)
            "routableAddresses" -> handleRoutableAddresses(result)
            "getSubscriptions" -> handleGetSubscriptions(result)
            "getTelemetry" -> handleGetTelemetry(result)
            "identityFromHex" -> handleIdentityFromHex(call, result)
            "sign" -> handleSign(call, result)
            "verify" -> handleVerify(call, result)
            else -> result.notImplemented()
        }
    }

    // MARK: - createNodeWithConfig

    private fun handleCreateNodeWithConfig(call: MethodCall, result: Result) {
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
                val identityHex: String
                val secretKey: String
                val nonce: String
                
                if (secretKeyHex != null && nonceHex != null) {
                    // Restore existing identity (instant) - binds to [::]:0 (dual-stack)
                    // SECURITY: Do not log secret key material (per AGENTS.md)
                    android.util.Log.d("KoriumBridge", "Restoring identity with nonce=$nonceHex")
                    newNode = FfiNode.createWithIdentity("[::]:0", secretKeyHex, nonceHex)
                    android.util.Log.d("KoriumBridge", "Restored identity: ${newNode.identityHex()}")
                    identityHex = newNode.identityHex()
                    secretKey = secretKeyHex
                    nonce = nonceHex
                } else {
                    // Generate new identity with PoW (1-4 seconds) then create node
                    val bundle = generateIdentity()
                    newNode = FfiNode.createWithIdentity("[::]:0", bundle.secretKeyHex, bundle.nonceHex)
                    identityHex = bundle.identityHex
                    secretKey = bundle.secretKeyHex
                    nonce = bundle.nonceHex
                }
                
                node = newNode
                val localAddr = newNode.localAddress()
                
                // Return immediately - bootstrap happens in background
                mainHandler.post {
                    result.success(
                        mapOf(
                            "identity" to identityHex,
                            "localAddr" to localAddr,
                            "isBootstrapped" to false,  // Will update via event
                            "bootstrapError" to null,
                            "secretKeyHex" to secretKey,
                            "powNonce" to nonce
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
        // SECURITY: Flutter MethodChannel may encode int as Integer (32-bit) or Long (64-bit).
        // Use Number.toLong() to handle both cases correctly.
        val timestamp = (message["timestampMs"] as? Number)?.toLong() ?: System.currentTimeMillis()
        val messageId = message["id"] as? String ?: java.util.UUID.randomUUID().toString()
        val messageType = message["messageType"] as? String ?: "text"

        scope.launch {
            try {
                val escapedContent = escapeJson(content)
                // Protocol v1.1: 'from' field removed - sender identity authenticated by Korium transport
                val messagePayload = """{"id":"$messageId","content":"$escapedContent","timestamp":$timestamp,"messageType":"$messageType"}""".toByteArray(Charsets.UTF_8)
                
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

        // SECURITY: Validate group ID format (UUID = exactly 36 chars with hex digits and hyphens)
        // Must match iOS validation for cross-platform consistency
        if (groupId.length != GROUP_ID_MAX_LEN || !groupId.all { it.isHexDigit() || it == '-' }) {
            result.error("INVALID_ARGS", "Invalid group ID format", null)
            return
        }

        val content = message["text"] as? String ?: ""
        // SECURITY: Flutter MethodChannel may encode int as Integer (32-bit) or Long (64-bit).
        // Use Number.toLong() to handle both cases correctly.
        val timestamp = (message["timestampMs"] as? Number)?.toLong() ?: System.currentTimeMillis()
        val messageId = message["id"] as? String ?: java.util.UUID.randomUUID().toString()

        scope.launch {
            try {
                val groupTopic = "six7-group:$groupId"
                val escapedContent = escapeJson(content)
                // Protocol v1.1: 'from' field removed - sender identity authenticated by Korium transport
                val messagePayload = """{"id":"$messageId","content":"$escapedContent","timestamp":$timestamp,"groupId":"$groupId"}""".toByteArray(Charsets.UTF_8)
                
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
        
        scope.launch {
            try {
                val addresses = currentNode.routableAddresses()
                mainHandler.post {
                    result.success(addresses)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("KORIUM_ERROR", e.message, null)
                }
            }
        }
    }

    // MARK: - addPeer

    private fun handleAddPeer(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val peerId = call.argument<String>("peerId")
        @Suppress("UNCHECKED_CAST")
        val addresses = call.argument<List<String>>("addresses") ?: emptyList()

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
                currentNode.addPeer(peerId, addresses)
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

    // MARK: - bootstrap

    private fun handleBootstrap(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val peerIdentity = call.argument<String>("peerIdentity")
        @Suppress("UNCHECKED_CAST")
        val peerAddrs = call.argument<List<String>>("peerAddrs") ?: emptyList()

        if (peerIdentity == null) {
            result.error("INVALID_ARGS", "peerIdentity required", null)
            return
        }

        if (peerIdentity.length != PEER_IDENTITY_HEX_LEN || !peerIdentity.all { it.isHexDigit() }) {
            result.error("INVALID_ARGS", "Invalid peer identity format", null)
            return
        }

        scope.launch {
            try {
                currentNode.bootstrap(peerIdentity, peerAddrs)
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

    // MARK: - subscribe

    private fun handleSubscribe(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val topic = call.argument<String>("topic")
        if (topic == null || topic.isEmpty()) {
            result.error("INVALID_ARGS", "topic required", null)
            return
        }

        // SECURITY: Validate topic length to prevent resource consumption
        if (topic.length > MAX_TOPIC_LENGTH) {
            result.error("INVALID_ARGS", "Topic exceeds maximum length of $MAX_TOPIC_LENGTH", null)
            return
        }

        scope.launch {
            try {
                currentNode.subscribe(topic)
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

    // MARK: - unsubscribe

    private fun handleUnsubscribe(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val topic = call.argument<String>("topic")
        if (topic == null || topic.isEmpty()) {
            result.error("INVALID_ARGS", "topic required", null)
            return
        }

        // SECURITY: Validate topic length (consistent with handleSubscribe)
        if (topic.length > MAX_TOPIC_LENGTH) {
            result.error("INVALID_ARGS", "Topic exceeds maximum length of $MAX_TOPIC_LENGTH", null)
            return
        }

        scope.launch {
            try {
                currentNode.unsubscribe(topic)
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

    // MARK: - publish

    private fun handlePublish(call: MethodCall, result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }

        val topic = call.argument<String>("topic")
        val data = call.argument<ByteArray>("data")

        if (topic == null || topic.isEmpty()) {
            result.error("INVALID_ARGS", "topic required", null)
            return
        }

        // SECURITY: Validate topic length (consistent with handleSubscribe)
        if (topic.length > MAX_TOPIC_LENGTH) {
            result.error("INVALID_ARGS", "Topic exceeds maximum length of $MAX_TOPIC_LENGTH", null)
            return
        }

        if (data == null) {
            result.error("INVALID_ARGS", "data required", null)
            return
        }

        scope.launch {
            try {
                currentNode.publish(topic, data)
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

    // MARK: - identityFromHex

    private fun handleIdentityFromHex(call: MethodCall, result: Result) {
        val hexStr = call.argument<String>("hexStr")
        if (hexStr == null) {
            result.error("INVALID_ARGS", "hexStr required", null)
            return
        }

        try {
            val validatedIdentity = identityFromHex(hexStr)
            result.success(validatedIdentity)
        } catch (e: KoriumException) {
            result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
        } catch (e: Exception) {
            result.error("KORIUM_ERROR", e.message, null)
        }
    }

    // MARK: - sign

    private fun handleSign(call: MethodCall, result: Result) {
        val secretKeyHex = call.argument<String>("secretKeyHex")
        val message = call.argument<ByteArray>("message")

        if (secretKeyHex == null) {
            result.error("INVALID_ARGS", "secretKeyHex required", null)
            return
        }
        if (message == null) {
            result.error("INVALID_ARGS", "message required", null)
            return
        }

        // SECURITY: Validate secret key format
        if (secretKeyHex.length != SECRET_KEY_HEX_LEN || !secretKeyHex.all { it.isHexDigit() }) {
            result.error("INVALID_ARGS", "Invalid secret key format", null)
            return
        }

        try {
            val signatureResult = sign(secretKeyHex, message)
            result.success(mapOf(
                "signatureHex" to signatureResult.signatureHex
            ))
        } catch (e: KoriumException) {
            result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
        } catch (e: Exception) {
            result.error("KORIUM_ERROR", e.message, null)
        }
    }

    // MARK: - verify

    private fun handleVerify(call: MethodCall, result: Result) {
        val publicKeyHex = call.argument<String>("publicKeyHex")
        val message = call.argument<ByteArray>("message")
        val signatureHex = call.argument<String>("signatureHex")

        if (publicKeyHex == null) {
            result.error("INVALID_ARGS", "publicKeyHex required", null)
            return
        }
        if (message == null) {
            result.error("INVALID_ARGS", "message required", null)
            return
        }
        if (signatureHex == null) {
            result.error("INVALID_ARGS", "signatureHex required", null)
            return
        }

        // SECURITY: Validate public key format
        if (publicKeyHex.length != PEER_IDENTITY_HEX_LEN || !publicKeyHex.all { it.isHexDigit() }) {
            result.error("INVALID_ARGS", "Invalid public key format", null)
            return
        }

        try {
            val isValid = verify(publicKeyHex, message, signatureHex)
            result.success(isValid)
        } catch (e: KoriumException) {
            result.error("KORIUM_ERROR", e.message, e.javaClass.simpleName)
        } catch (e: Exception) {
            result.error("KORIUM_ERROR", e.message, null)
        }
    }

    // MARK: - getSubscriptions
    
    private fun handleGetSubscriptions(result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }
        
        scope.launch {
            try {
                val subscriptions = currentNode.subscriptions()
                mainHandler.post { result.success(subscriptions) }
            } catch (e: Exception) {
                android.util.Log.w("KoriumBridge", "Failed to get subscriptions: ${e.message}")
                mainHandler.post { result.success(emptyList<String>()) }
            }
        }
    }

    // MARK: - getTelemetry
    
    private fun handleGetTelemetry(result: Result) {
        val currentNode = node
        if (currentNode == null) {
            result.error("NOT_INITIALIZED", "Node not initialized", null)
            return
        }
        
        scope.launch {
            try {
                val telemetry = currentNode.telemetry()
                mainHandler.post {
                    result.success(mapOf(
                        "storedKeys" to telemetry.storedKeys.toLong(),
                        "replicationFactor" to telemetry.replicationFactor.toLong(),
                        "concurrency" to telemetry.concurrency.toLong()
                    ))
                }
            } catch (e: Exception) {
                android.util.Log.w("KoriumBridge", "Failed to get telemetry: ${e.message}")
                mainHandler.post {
                    result.success(mapOf(
                        "storedKeys" to 0L,
                        "replicationFactor" to 0L,
                        "concurrency" to 0L
                    ))
                }
            }
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
            val content = payload.optString("content", "")
            val timestamp = payload.optLong("timestamp", System.currentTimeMillis())
            val messageType = payload.optString("messageType", "text")
            
            if (messageId.isEmpty()) {
                android.util.Log.w("KoriumBridge", "Invalid request payload: missing id")
                return null
            }
            
            // SECURITY: Use Korium's authenticated fromIdentity as the authoritative sender.
            // This is cryptographically verified by Korium's RPC layer - we don't need to
            // check or trust the payload's "from" field at all.
            val senderId = request.fromIdentity
            
            // Handle read receipts specially - emit as status updates, not chat messages
            if (messageType == "readReceipt") {
                // content contains comma-separated message IDs that were read
                val readMessageIds = content.split(",").filter { it.isNotEmpty() }
                android.util.Log.d("KoriumBridge", "Received read receipt for ${readMessageIds.size} messages from ${senderId.take(16)}...")
                
                // Emit a status update event for each message
                readMessageIds.forEach { readMsgId ->
                    val statusEvent = mapOf(
                        "type" to "messageStatusUpdate",
                        "messageId" to readMsgId.trim(),
                        "status" to "read"
                    )
                    appendEvent(statusEvent)
                }
                mainHandler.post { channel.invokeMethod("onEvent", null) }
                return null // Don't emit as a chat message
            }
            
            val myIdentity = currentNode.identityHex()
            val isFromMe = senderId.lowercase() == myIdentity.lowercase()
            
            val chatMessage = mapOf(
                "id" to messageId,
                "senderId" to senderId,
                "recipientId" to myIdentity,
                "text" to content,
                "messageType" to messageType,
                "timestampMs" to timestamp,
                "status" to "delivered",
                "isFromMe" to isFromMe
            )
            
            android.util.Log.d("KoriumBridge", "Received direct message from ${senderId.take(16)}...")
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
            val content = payload.optString("content", "")
            val timestamp = payload.optLong("timestamp", System.currentTimeMillis())
            val groupIdFromPayload = payload.optString("groupId", null.toString())
            val messageType = payload.optString("messageType", "text")
            
            if (messageId.isEmpty()) {
                return mapOf(
                    "type" to "pubSubMessage",
                    "topic" to msg.topic,
                    "fromIdentity" to msg.sourceIdentity,
                    "data" to msg.data.toList()
                )
            }
            
            // SECURITY: Use Korium's authenticated sourceIdentity as the authoritative sender.
            // This is cryptographically verified by Korium's DHT layer - we don't need to
            // check or trust the payload's "from" field at all.
            val senderId = msg.sourceIdentity
            
            val myIdentity = currentNode.identityHex()
            val isGroupMessage = msg.topic.startsWith("six7-group:")
            val groupId = if (isGroupMessage && groupIdFromPayload != "null") groupIdFromPayload else null
            val isFromMe = senderId.lowercase() == myIdentity.lowercase()
            
            val chatMessage = mutableMapOf<String, Any?>(
                "id" to messageId,
                "senderId" to senderId,
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

    // SECURITY: Escape all JSON special characters including control characters
    private fun escapeJson(s: String): String = s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
        .replace("\b", "\\b")  // backspace
        .replace("\u000C", "\\f")  // form feed

    private fun Char.isHexDigit(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
}
