# Six7 Protocol Specification v1.1

A JSON-based messaging protocol for secure peer-to-peer communication, designed for interoperability between Six7 CLI and mobile applications.

## Overview

The Six7 Protocol defines message formats and transport mechanisms for:
- Direct 1:1 messaging (RPC)
- Group messaging (PubSub)
- Presence/heartbeat (PubSub)
- Anonymous matching ("Vibes")

All messages are JSON-encoded and transported over Korium's adaptive networking fabric.

## Message Types

```
text           - Plain text message
image          - Image attachment
video          - Video attachment
audio          - Audio attachment
document       - Document/file attachment
location       - Geographic coordinates
contact        - Shared contact information
groupInvite    - Invitation to join a group
contactRequest - Request to add as contact
contactAccepted - Acceptance of contact request
vibe           - Anonymous matching signal
readReceipt    - Delivery/read confirmation
```

## Direct Message (RPC)

Used for 1:1 direct messages between peers.

> **Note:** Sender identity is authenticated by Korium's transport layer and is not included in the message payload.

### Schema

```json
{
  "id": "<uuid-v4>",
  "content": "<json-escaped-string>",
  "timestamp": <unix-epoch-milliseconds>,
  "messageType": "<message-type>"
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID v4 unique message identifier |
| `content` | string | Message content (JSON-escaped) |
| `timestamp` | integer | Unix epoch timestamp in milliseconds |
| `messageType` | string | One of the message type enum values |

### Example

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "content": "Hello, world!",
  "timestamp": 1737878400000,
  "messageType": "text"
}
```

### ACK Response

Direct messages return an acknowledgment:

```json
{
  "ack": true
}
```

## Group Message (PubSub)

Published to topic: `six7-group:{groupId}`

> **Note:** Sender identity is authenticated by Korium's transport layer and is not included in the message payload.

### Schema

```json
{
  "id": "<uuid-v4>",
  "content": "<json-escaped-string>",
  "timestamp": <unix-epoch-milliseconds>,
  "groupId": "<uuid-v4>"
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID v4 unique message identifier |
| `content` | string | Message content (JSON-escaped) |
| `timestamp` | integer | Unix epoch timestamp in milliseconds |
| `groupId` | string | UUID v4 group identifier (36 chars) |

## Group Invite Payload

Embedded in `DirectMessage.content` as a JSON string when `messageType` is `groupInvite`.

### Schema

```json
{
  "groupId": "<uuid-v4>",
  "name": "<group-name>",
  "description": "<group-description>",
  "memberIds": ["<identity-hex>", ...],
  "memberNames": {
    "<identity-hex>": "<display-name>",
    ...
  },
  "creatorId": "<identity-hex>",
  "createdAtMs": <unix-epoch-milliseconds>
}
```

## Contact Request / Accepted

Special direct messages for contact management. Sender identity is provided by Korium transport.

### Contact Request
```json
{
  "id": "<uuid-v4>",
  "content": "<sender-display-name>",
  "timestamp": <unix-epoch-milliseconds>,
  "messageType": "contactRequest"
}
```

### Contact Accepted
```json
{
  "id": "<uuid-v4>",
  "content": "<sender-display-name>",
  "timestamp": <unix-epoch-milliseconds>,
  "messageType": "contactAccepted"
}
```

## Read Receipt

Confirms message delivery/read status:

```json
{
  "id": "rr-<timestamp>",
  "content": "<message-id-1>,<message-id-2>,...",
  "timestamp": <unix-epoch-milliseconds>,
  "messageType": "readReceipt"
}
```

The `content` field contains comma-separated message IDs being acknowledged.

## Vibe Protocol (Anonymous Matching)

Published to topic: `six7-vibes-v1`

### Commitment Phase

```json
{
  "type": "commitment",
  "vibeId": "<uuid>",
  "commitment": "<hash>"
}
```

### Reveal Phase

```json
{
  "type": "reveal",
  "vibeId": "<uuid>",
  "secret": "<secret-value>"
}
```

## Topic Naming

| Purpose | Topic Pattern |
|---------|---------------|
| Group chat | `six7-group:{groupId}` |
| Presence inbox | `six7-presence-inbox:{identity}` |
| Vibes matching | `six7-vibes-v1` |

## Limits

| Constraint | Value |
|------------|-------|
| Max message size | 65,536 bytes |
| Max topic length | 256 characters |
| Identity length | 64 hex characters |
| Group ID length | 36 characters (UUID) |

## Timing

| Parameter | Value |
|-----------|-------|
| Heartbeat interval | 30 seconds |
| Offline threshold | 75 seconds |

## Identity Format

Identities are 64-character hexadecimal strings representing Ed25519 public keys.

Example: `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`

## Transport

All messages are transported over Korium's adaptive networking fabric which provides:
- NAT traversal
- End-to-end encryption
- DHT-based peer discovery
- PubSub for group messaging
- RPC for direct messaging

## Versioning

Protocol version is indicated in the message header and CLI banner. This document describes **Protocol Version 1.1**.

### Changelog

- **v1.1** - Removed redundant `from` field; sender identity authenticated by Korium transport layer
- **v1.0** - Initial JSON message format for app interoperability
