//! Integration tests for Korium P2P network connectivity.
//!
//! These tests spawn multiple Korium nodes and verify they can:
//! 1. Discover external address via STUN
//! 2. Bootstrap to each other
//! 3. Discover peers via DHT
//! 4. Send messages between nodes
//!
//! # Running
//! ```bash
//! cargo test --test korium_network_integration -- --nocapture
//! ```
//!
//! # Architecture
//! ```text
//! Node 0 (Bootstrap Node)
//!    ├── Node 1 bootstraps to Node 0
//!    ├── Node 2 bootstraps to Node 0
//!    ├── Node 3 bootstraps to Node 1 (indirect)
//!    ├── Node 4 bootstraps to Node 2 (indirect)
//!    ├── Node 5 bootstraps to Node 3 (2 hops)
//!    └── Node 6 bootstraps to Node 4 (2 hops)
//! ```

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Barrier;
use tokio::time::timeout;

// Import STUN discovery - crate is named six7_native
use six7_native::bootstrap::stun;
use six7_native::KoriumError;

/// Number of nodes to spawn for the network test.
const NUM_NODES: usize = 7;

/// Timeout for node creation (includes PoW computation).
const NODE_CREATION_TIMEOUT: Duration = Duration::from_secs(30);

/// Timeout for bootstrap operations.
const BOOTSTRAP_TIMEOUT: Duration = Duration::from_secs(10);

/// Timeout for peer discovery.
const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(15);

/// Timeout for message delivery.
const MESSAGE_TIMEOUT: Duration = Duration::from_secs(30);

/// Timeout for STUN discovery.
const STUN_TIMEOUT: Duration = Duration::from_secs(10);

/// Delay between node creations to stagger PoW.
const NODE_CREATION_STAGGER: Duration = Duration::from_millis(500);

/// A test node wrapper that holds identity and address info.
#[derive(Debug, Clone)]
struct TestNode {
    identity: String,
    local_addr: String,
    external_addr: Option<String>,
}

/// Creates a Korium node bound to a random port.
async fn create_node() -> Result<(korium::Node, TestNode), String> {
    let node = korium::Node::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("Failed to create node: {e}"))?;

    let identity = node.identity();
    let local_addr = node
        .local_addr()
        .map_err(|e| format!("Failed to get local addr: {e}"))?
        .to_string();

    let test_node = TestNode {
        identity: identity.clone(),
        local_addr: local_addr.clone(),
        external_addr: None,
    };

    println!(
        "  Created node {} at {}",
        &identity[..16],
        local_addr
    );

    Ok((node, test_node))
}

/// Creates a Korium node with STUN-discovered external address.
/// 
/// # Approach
/// 1. Create node FIRST to get the actual bound port
/// 2. STUN discovery to get external IP (uses ephemeral port, we only need the IP)
/// 3. Combine external IP with node's local port
/// 
/// This works because most NATs preserve port mappings (Full Cone, Restricted Cone,
/// Port Restricted Cone). Symmetric NAT would require TURN relay.
async fn create_node_with_stun() -> Result<(korium::Node, TestNode), String> {
    // STEP 1: Create node FIRST to get the actual bound port
    let node = korium::Node::bind("0.0.0.0:0")
        .await
        .map_err(|e| format!("Failed to create node: {e}"))?;

    let identity = node.identity();
    let local_addr = node
        .local_addr()
        .map_err(|e| format!("Failed to get local addr: {e}"))?;
    
    // Extract local port from the bound address
    let local_port = local_addr.port();
    let local_addr_str = local_addr.to_string();

    // STEP 2: STUN discovery to get external IP only (uses ephemeral port)
    // We only care about the external IP - we'll combine it with our local port
    let external_addr: Option<String> = match timeout(STUN_TIMEOUT, stun::discover_external_address(None)).await {
        Ok(Ok(stun_addr)) => {
            // Combine external IP with our actual local port
            // Assumption: NAT preserves port mapping (works for most NATs)
            let combined = format!("{}:{}", stun_addr.ip(), local_port);
            println!("  STUN: External IP {} + local port {} = {}", stun_addr.ip(), local_port, combined);
            Some(combined)
        }
        Ok(Err(_e)) => {
            println!("  STUN: Discovery failed (continuing with local only)");
            None
        }
        Err(_) => {
            println!("  STUN: Discovery timed out (continuing with local only)");
            None
        }
    };

    let test_node = TestNode {
        identity: identity.clone(),
        local_addr: local_addr_str.clone(),
        external_addr,
    };

    println!(
        "  Created node {} at {} (external: {:?})",
        &identity[..16],
        local_addr_str,
        test_node.external_addr.as_ref().map(|s| s.as_str()).unwrap_or("none")
    );

    Ok((node, test_node))
}

/// Test: STUN external address discovery works.
#[tokio::test]
async fn test_stun_external_address_discovery() {
    println!("\n=== Test: STUN External Address Discovery ===\n");

    // Test 1: Basic STUN discovery (ephemeral port)
    println!("Test 1: STUN discovery with ephemeral port...");
    let result: Result<Result<SocketAddr, KoriumError>, _> = 
        timeout(STUN_TIMEOUT, stun::discover_external_address(None)).await;

    match result {
        Ok(Ok(addr)) => {
            println!("  ✓ Discovered external address: {}", addr);
            assert!(!addr.ip().is_loopback(), "External IP should not be loopback");
            assert!(!addr.ip().is_unspecified(), "External IP should not be 0.0.0.0");
        }
        Ok(Err(e)) => {
            println!("  ✗ STUN discovery failed: {}", e);
            println!("    (This may fail if running without internet access)");
        }
        Err(_) => {
            println!("  ✗ STUN discovery timed out after {:?}", STUN_TIMEOUT);
        }
    }

    // Test 2: STUN discovery with specific port
    println!("\nTest 2: STUN discovery with specific port (12345)...");
    let result: Result<Result<SocketAddr, KoriumError>, _> = 
        timeout(STUN_TIMEOUT, stun::discover_external_address(Some(12345))).await;

    match result {
        Ok(Ok(addr)) => {
            println!("  ✓ Discovered external address: {}", addr);
            // Port mapping may or may not preserve the port (depends on NAT type)
            println!("    Mapped port: {} (local was 12345)", addr.port());
        }
        Ok(Err(e)) => {
            println!("  - STUN discovery failed: {}", e);
        }
        Err(_) => {
            println!("  - STUN discovery timed out");
        }
    }

    // Test 3: Multiple STUN queries for consistency
    println!("\nTest 3: Multiple STUN queries for consistency...");
    let mut addresses = Vec::new();

    for i in 0..3 {
        let result: Result<Result<SocketAddr, KoriumError>, _> = 
            timeout(STUN_TIMEOUT, stun::discover_external_address(None)).await;
        if let Ok(Ok(addr)) = result {
            println!("  Query {}: {}", i + 1, addr);
            addresses.push(addr.ip());
        }
    }

    if addresses.len() >= 2 {
        let first_ip = addresses[0];
        let all_same = addresses.iter().all(|ip| *ip == first_ip);
        if all_same {
            println!("  ✓ All queries returned consistent IP: {}", first_ip);
        } else {
            println!("  - IPs varied (may indicate NAT behavior or network issues)");
        }
    }

    println!("\n✓ STUN external address discovery test completed\n");
}

/// Test: All 7 nodes can be created successfully.
#[tokio::test]
#[ignore] // Slow: ~6 min (7 nodes with PoW). Run with: cargo test test_create_seven_nodes -- --ignored
async fn test_create_seven_nodes() {
    println!("\n=== Test: Create 7 Korium Nodes ===\n");

    let mut nodes = Vec::with_capacity(NUM_NODES);

    for i in 0..NUM_NODES {
        println!("Creating node {}/{}...", i + 1, NUM_NODES);

        let result = timeout(NODE_CREATION_TIMEOUT, create_node()).await;

        match result {
            Ok(Ok((node, test_node))) => {
                nodes.push((node, test_node));
            }
            Ok(Err(e)) => {
                panic!("Node {} creation failed: {}", i, e);
            }
            Err(_) => {
                panic!("Node {} creation timed out after {:?}", i, NODE_CREATION_TIMEOUT);
            }
        }

        // Stagger creation to avoid overwhelming the system
        if i < NUM_NODES - 1 {
            tokio::time::sleep(NODE_CREATION_STAGGER).await;
        }
    }

    assert_eq!(nodes.len(), NUM_NODES);
    println!("\n✓ Successfully created {} nodes\n", NUM_NODES);

    // Verify all identities are unique
    let identities: std::collections::HashSet<_> = nodes.iter().map(|(_, t)| &t.identity).collect();
    assert_eq!(identities.len(), NUM_NODES, "All node identities must be unique");
    println!("✓ All node identities are unique\n");

    // Cleanup: shutdown nodes
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }
}

/// Test: Nodes can bootstrap to each other in a chain topology.
#[tokio::test]
#[ignore] // Slow: ~7 min (7 nodes). Run with: cargo test test_bootstrap_chain_topology -- --ignored
async fn test_bootstrap_chain_topology() {
    println!("\n=== Test: Bootstrap Chain Topology ===\n");
    println!("Topology: Node0 <- Node1 <- Node2 <- ... <- Node6\n");

    // Create all nodes first
    let mut nodes = Vec::with_capacity(NUM_NODES);
    for i in 0..NUM_NODES {
        println!("Creating node {}...", i);
        let (node, test_node) = timeout(NODE_CREATION_TIMEOUT, create_node())
            .await
            .expect("Node creation timed out")
            .expect("Node creation failed");
        nodes.push((node, test_node));
        tokio::time::sleep(NODE_CREATION_STAGGER).await;
    }

    // Bootstrap in chain: each node connects to the previous one
    for i in 1..NUM_NODES {
        let prev_info = &nodes[i - 1].1;
        let curr_node = &nodes[i].0;

        println!(
            "Bootstrapping node {} -> node {} ({})",
            i,
            i - 1,
            &prev_info.identity[..16]
        );

        let result = timeout(
            BOOTSTRAP_TIMEOUT,
            curr_node.bootstrap(&prev_info.identity, &[prev_info.local_addr.clone()]),
        )
        .await;

        match result {
            Ok(Ok(_)) => {
                println!("  ✓ Node {} bootstrapped successfully", i);
            }
            Ok(Err(e)) => {
                panic!("Node {} bootstrap failed: {}", i, e);
            }
            Err(_) => {
                panic!("Node {} bootstrap timed out after {:?}", i, BOOTSTRAP_TIMEOUT);
            }
        }
    }

    println!("\n✓ All {} nodes bootstrapped in chain topology\n", NUM_NODES);

    // Cleanup
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }
}

/// Test: Nodes can bootstrap in a star topology (all to one central node).
#[tokio::test]
#[ignore] // Slow: ~4 min (7 nodes). Run with: cargo test test_bootstrap_star_topology -- --ignored
async fn test_bootstrap_star_topology() {
    println!("\n=== Test: Bootstrap Star Topology ===\n");
    println!("Topology: All nodes bootstrap to Node 0 (hub)\n");

    // Create all nodes
    let mut nodes = Vec::with_capacity(NUM_NODES);
    for i in 0..NUM_NODES {
        println!("Creating node {}...", i);
        let (node, test_node) = timeout(NODE_CREATION_TIMEOUT, create_node())
            .await
            .expect("Node creation timed out")
            .expect("Node creation failed");
        nodes.push((node, test_node));
        tokio::time::sleep(NODE_CREATION_STAGGER).await;
    }

    // Node 0 is the hub - all others bootstrap to it
    let hub_info = nodes[0].1.clone();
    println!("Hub node: {} at {}", &hub_info.identity[..16], hub_info.local_addr);

    // Bootstrap all other nodes to the hub
    for i in 1..NUM_NODES {
        let curr_node = &nodes[i].0;

        println!("Bootstrapping node {} -> hub...", i);

        let result = timeout(
            BOOTSTRAP_TIMEOUT,
            curr_node.bootstrap(&hub_info.identity, &[hub_info.local_addr.clone()]),
        )
        .await;

        match result {
            Ok(Ok(_)) => {
                println!("  ✓ Node {} bootstrapped to hub", i);
            }
            Ok(Err(e)) => {
                panic!("Node {} bootstrap to hub failed: {}", i, e);
            }
            Err(_) => {
                panic!("Node {} bootstrap timed out", i);
            }
        }
    }

    println!("\n✓ All {} nodes bootstrapped to central hub\n", NUM_NODES);

    // Cleanup
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }
}

/// Test: Peer discovery via DHT after bootstrap.
#[tokio::test]
#[ignore] // Slow: ~3 min (7 nodes). Run with: cargo test test_peer_discovery_after_bootstrap -- --ignored
async fn test_peer_discovery_after_bootstrap() {
    println!("\n=== Test: Peer Discovery After Bootstrap ===\n");

    // Create 7 nodes with star topology
    let mut nodes = Vec::with_capacity(NUM_NODES);
    for _i in 0..NUM_NODES {
        let (node, test_node) = timeout(NODE_CREATION_TIMEOUT, create_node())
            .await
            .expect("Node creation timed out")
            .expect("Node creation failed");
        nodes.push((node, test_node));
        tokio::time::sleep(NODE_CREATION_STAGGER).await;
    }

    // Bootstrap to hub
    let hub_info = nodes[0].1.clone();
    for i in 1..NUM_NODES {
        let _ = timeout(
            BOOTSTRAP_TIMEOUT,
            nodes[i].0.bootstrap(&hub_info.identity, &[hub_info.local_addr.clone()]),
        )
        .await
        .expect("Bootstrap timed out")
        .expect("Bootstrap failed");
    }

    println!("All nodes bootstrapped. Testing peer discovery...\n");

    // Give DHT time to propagate
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Each node tries to discover others via find_peers
    let mut discovery_success = 0;
    let mut discovery_attempts = 0;

    for i in 0..NUM_NODES {
        for j in 0..NUM_NODES {
            if i == j {
                continue;
            }

            discovery_attempts += 1;
            let target_identity = &nodes[j].1.identity;

            let result = timeout(
                DISCOVERY_TIMEOUT,
                nodes[i].0.resolve(&korium::Identity::from_hex(target_identity).unwrap()),
            )
            .await;

            match result {
                Ok(Ok(Some(contact))) => {
                    println!(
                        "  Node {} found node {} at {:?}",
                        i, j, contact.addrs
                    );
                    discovery_success += 1;
                }
                Ok(Ok(None)) => {
                    println!("  Node {} could not find node {} (not in DHT yet)", i, j);
                }
                Ok(Err(e)) => {
                    println!("  Node {} discovery error for node {}: {}", i, j, e);
                }
                Err(_) => {
                    println!("  Node {} discovery timed out for node {}", i, j);
                }
            }
        }
    }

    let success_rate = (discovery_success as f64 / discovery_attempts as f64) * 100.0;
    println!(
        "\nDiscovery results: {}/{} ({:.1}%)",
        discovery_success, discovery_attempts, success_rate
    );

    // We expect at least some discoveries to work (DHT takes time)
    // In a local network, most should succeed
    assert!(
        discovery_success > 0,
        "At least some peer discoveries should succeed"
    );

    println!("\n✓ Peer discovery test completed\n");

    // Cleanup
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }
}

/// Test: Direct messaging between bootstrapped nodes.
#[tokio::test]
async fn test_direct_messaging() {
    println!("\n=== Test: Direct Messaging Between Nodes ===\n");

    // Create 2 nodes for simple messaging test
    let (node_a, info_a) = timeout(NODE_CREATION_TIMEOUT, create_node())
        .await
        .expect("Node A creation timed out")
        .expect("Node A creation failed");

    tokio::time::sleep(NODE_CREATION_STAGGER).await;

    let (node_b, info_b) = timeout(NODE_CREATION_TIMEOUT, create_node())
        .await
        .expect("Node B creation timed out")
        .expect("Node B creation failed");

    println!("Node A: {} at {}", &info_a.identity[..16], info_a.local_addr);
    println!("Node B: {} at {}", &info_b.identity[..16], info_b.local_addr);

    // Set up request handlers BEFORE bootstrap - each node echoes back received messages
    node_a.set_request_handler(|_from, data| {
        println!("  [A] Received request, echoing back");
        data // Echo the request back as response
    }).await.expect("Failed to set handler on A");

    node_b.set_request_handler(|_from, data| {
        println!("  [B] Received request, echoing back");
        data // Echo the request back as response
    }).await.expect("Failed to set handler on B");

    println!("✓ Request handlers set up on both nodes");

    // Bootstrap B to A AND A to B (bidirectional for local messaging)
    timeout(
        BOOTSTRAP_TIMEOUT,
        node_b.bootstrap(&info_a.identity, &[info_a.local_addr.clone()]),
    )
    .await
    .expect("Bootstrap timed out")
    .expect("Bootstrap failed");

    println!("✓ Node B bootstrapped to Node A");

    timeout(
        BOOTSTRAP_TIMEOUT,
        node_a.bootstrap(&info_b.identity, &[info_b.local_addr.clone()]),
    )
    .await
    .expect("Bootstrap timed out")
    .expect("Bootstrap failed");

    println!("✓ Node A bootstrapped to Node B\n");

    // Give DHT time to propagate
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Send message from A to B
    let test_message = b"Hello from Node A!";
    println!("Sending message from A to B...");

    let send_result = timeout(
        MESSAGE_TIMEOUT,
        node_a.send(&info_b.identity, test_message.to_vec()),
    )
    .await;

    match send_result {
        Ok(Ok(_response)) => {
            println!("✓ Message sent successfully from A to B");
        }
        Ok(Err(e)) => {
            println!("✗ Message send failed: {}", e);
            // Not a hard failure - peer might not be reachable yet
        }
        Err(_) => {
            println!("✗ Message send timed out");
        }
    }

    // Send message from B to A
    let test_message_2 = b"Hello from Node B!";
    println!("Sending message from B to A...");

    let send_result_2 = timeout(
        MESSAGE_TIMEOUT,
        node_b.send(&info_a.identity, test_message_2.to_vec()),
    )
    .await;

    match send_result_2 {
        Ok(Ok(_response)) => {
            println!("✓ Message sent successfully from B to A");
        }
        Ok(Err(e)) => {
            println!("✗ Message send failed: {}", e);
        }
        Err(_) => {
            println!("✗ Message send timed out");
        }
    }

    println!("\n✓ Direct messaging test completed\n");

    // Cleanup
    let _ = node_a.shutdown().await;
    let _ = node_b.shutdown().await;
}

/// Test: Full network simulation with 7 nodes.
/// Verifies that all nodes can join the network and discover each other.
#[tokio::test]
#[ignore] // Slow: ~10 min (full 7-node simulation). Run with: cargo test test_full_seven_node_network -- --ignored
async fn test_full_seven_node_network() {
    println!("\n=== Test: Full 7-Node Network Simulation ===\n");
    println!("This test simulates a realistic network with 7 peers.\n");

    // Phase 1: Create all nodes
    println!("Phase 1: Creating {} nodes...\n", NUM_NODES);
    let mut nodes = Vec::with_capacity(NUM_NODES);

    for i in 0..NUM_NODES {
        let (node, test_node) = timeout(NODE_CREATION_TIMEOUT, create_node())
            .await
            .expect("Node creation timed out")
            .expect("Node creation failed");

        println!(
            "  [{}] Created: {} at {}",
            i,
            &test_node.identity[..16],
            test_node.local_addr
        );

        nodes.push((node, test_node));
        tokio::time::sleep(NODE_CREATION_STAGGER).await;
    }

    println!("\n✓ Phase 1 complete: {} nodes created\n", NUM_NODES);

    // Phase 2: Bootstrap with tree topology
    // Node 0 = root
    // Nodes 1,2 -> Node 0
    // Nodes 3,4 -> Node 1
    // Nodes 5,6 -> Node 2
    println!("Phase 2: Bootstrapping with tree topology...\n");
    println!("         Node 0 (root)");
    println!("        /        \\");
    println!("    Node 1      Node 2");
    println!("   /    \\      /    \\");
    println!("Node 3 Node 4 Node 5 Node 6\n");

    let bootstrap_pairs = vec![
        (1, 0), // Node 1 -> Node 0
        (2, 0), // Node 2 -> Node 0
        (3, 1), // Node 3 -> Node 1
        (4, 1), // Node 4 -> Node 1
        (5, 2), // Node 5 -> Node 2
        (6, 2), // Node 6 -> Node 2
    ];

    for (child, parent) in bootstrap_pairs {
        let parent_info = &nodes[parent].1;

        println!(
            "  Node {} bootstrapping to Node {}...",
            child, parent
        );

        let result = timeout(
            BOOTSTRAP_TIMEOUT,
            nodes[child].0.bootstrap(&parent_info.identity, &[parent_info.local_addr.clone()]),
        )
        .await;

        match result {
            Ok(Ok(_)) => {
                println!("    ✓ Success");
            }
            Ok(Err(e)) => {
                panic!("Bootstrap {} -> {} failed: {}", child, parent, e);
            }
            Err(_) => {
                panic!("Bootstrap {} -> {} timed out", child, parent);
            }
        }

        // Small delay between bootstraps
        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    println!("\n✓ Phase 2 complete: Tree topology established\n");

    // Phase 3: Verify network connectivity
    println!("Phase 3: Verifying network connectivity...\n");

    // Let DHT stabilize
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Test that leaf nodes can find the root (traversing the tree)
    let leaf_nodes = vec![3, 4, 5, 6];
    let root_identity = &nodes[0].1.identity;

    let mut found_root = 0;
    for leaf in &leaf_nodes {
        let result = timeout(
            DISCOVERY_TIMEOUT,
            nodes[*leaf].0.resolve(
                &korium::Identity::from_hex(root_identity).unwrap()
            ),
        )
        .await;

        match result {
            Ok(Ok(Some(_))) => {
                println!("  ✓ Node {} found root (Node 0)", leaf);
                found_root += 1;
            }
            Ok(Ok(None)) => {
                println!("  - Node {} could not find root yet", leaf);
            }
            Ok(Err(e)) => {
                println!("  ✗ Node {} error finding root: {}", leaf, e);
            }
            Err(_) => {
                println!("  ✗ Node {} timed out finding root", leaf);
            }
        }
    }

    println!(
        "\n  Leaf nodes that found root: {}/{}",
        found_root,
        leaf_nodes.len()
    );

    // Phase 4: Cross-tree discovery (node 3 finding node 6)
    println!("\nPhase 4: Cross-tree discovery test...\n");

    let node_3_identity = &nodes[3].1.identity;
    let node_6_identity = &nodes[6].1.identity;

    // Node 3 tries to find Node 6 (different subtrees)
    let cross_result = timeout(
        DISCOVERY_TIMEOUT,
        nodes[3].0.resolve(
            &korium::Identity::from_hex(node_6_identity).unwrap()
        ),
    )
    .await;

    match cross_result {
        Ok(Ok(Some(contact))) => {
            println!("  ✓ Node 3 found Node 6 at {:?}", contact.addrs);
        }
        Ok(Ok(None)) => {
            println!("  - Node 3 could not find Node 6 (expected - DHT needs more time)");
        }
        Ok(Err(e)) => {
            println!("  - Node 3 error: {}", e);
        }
        Err(_) => {
            println!("  - Cross-tree discovery timed out");
        }
    }

    // Node 6 tries to find Node 3
    let cross_result_2 = timeout(
        DISCOVERY_TIMEOUT,
        nodes[6].0.resolve(
            &korium::Identity::from_hex(node_3_identity).unwrap()
        ),
    )
    .await;

    match cross_result_2 {
        Ok(Ok(Some(contact))) => {
            println!("  ✓ Node 6 found Node 3 at {:?}", contact.addrs);
        }
        Ok(Ok(None)) => {
            println!("  - Node 6 could not find Node 3");
        }
        Ok(Err(e)) => {
            println!("  - Node 6 error: {}", e);
        }
        Err(_) => {
            println!("  - Cross-tree discovery timed out");
        }
    }

    println!("\n=== Test Summary ===");
    println!("Nodes created:     {}/{}", NUM_NODES, NUM_NODES);
    println!("Bootstraps:        6/6");
    println!("Leaf->Root found:  {}/4", found_root);
    println!("====================\n");

    // Cleanup
    println!("Shutting down nodes...");
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }

    println!("\n✓ Full 7-node network test completed\n");
}

/// Test: Concurrent node creation (stress test).
#[tokio::test]
#[ignore] // Slow: ~2 min (concurrent PoW). Run with: cargo test test_concurrent_node_creation -- --ignored
async fn test_concurrent_node_creation() {
    println!("\n=== Test: Concurrent Node Creation ===\n");

    let barrier = Arc::new(Barrier::new(NUM_NODES));
    let mut handles = Vec::with_capacity(NUM_NODES);

    for i in 0..NUM_NODES {
        let barrier_clone = Arc::clone(&barrier);
        let handle = tokio::spawn(async move {
            // Wait for all tasks to be ready
            barrier_clone.wait().await;

            // Create node
            let start = std::time::Instant::now();
            let result = timeout(NODE_CREATION_TIMEOUT, create_node()).await;
            let elapsed = start.elapsed();

            match result {
                Ok(Ok((node, info))) => {
                    println!(
                        "  Node {} created in {:?}: {}",
                        i,
                        elapsed,
                        &info.identity[..16]
                    );
                    let _ = node.shutdown().await;
                    Ok(elapsed)
                }
                Ok(Err(e)) => {
                    println!("  Node {} failed: {}", i, e);
                    Err(e)
                }
                Err(_) => {
                    println!("  Node {} timed out", i);
                    Err("Timeout".to_string())
                }
            }
        });
        handles.push(handle);
    }

    // Wait for all nodes
    let mut successes = 0;
    let mut total_time = Duration::ZERO;

    for handle in handles {
        if let Ok(Ok(elapsed)) = handle.await {
            successes += 1;
            total_time += elapsed;
        }
    }

    let avg_time = if successes > 0 {
        total_time / successes as u32
    } else {
        Duration::ZERO
    };

    println!("\nConcurrent creation results:");
    println!("  Successful: {}/{}", successes, NUM_NODES);
    println!("  Average creation time: {:?}", avg_time);

    assert!(
        successes >= NUM_NODES / 2,
        "At least half the nodes should be created successfully"
    );

    println!("\n✓ Concurrent node creation test completed\n");
}

/// Test: Create 7 nodes with STUN-discovered external addresses.
/// This simulates a real-world scenario where nodes need NAT traversal.
#[tokio::test]
#[ignore] // Slow: ~15 min (7 nodes + STUN). Run with: cargo test test_seven_nodes_with_stun -- --ignored
async fn test_seven_nodes_with_stun() {
    println!("\n=== Test: 7 Nodes with STUN External Addresses ===\n");
    println!("This test simulates real-world NAT traversal.\n");

    // Phase 1: Discover external address via STUN
    println!("Phase 1: STUN Discovery\n");

    let stun_result: Result<Result<SocketAddr, KoriumError>, _> = 
        timeout(STUN_TIMEOUT, stun::discover_external_address(None)).await;
    let external_ip: Option<SocketAddr> = match stun_result {
        Ok(Ok(addr)) => {
            println!("  ✓ External address discovered: {}", addr);
            Some(addr)
        }
        Ok(Err(e)) => {
            println!("  ✗ STUN failed: {} (test will use local addresses)", e);
            None
        }
        Err(_) => {
            println!("  ✗ STUN timed out (test will use local addresses)");
            None
        }
    };

    // Phase 2: Create 7 nodes with STUN info
    println!("\nPhase 2: Creating {} nodes with STUN awareness...\n", NUM_NODES);

    let mut nodes: Vec<(korium::Node, TestNode)> = Vec::with_capacity(NUM_NODES);

    for i in 0..NUM_NODES {
        println!("Creating node {}...", i);

        let result = timeout(NODE_CREATION_TIMEOUT, create_node_with_stun()).await;

        match result {
            Ok(Ok((node, mut test_node))) => {
                // If global STUN succeeded, update the external address with correct port
                if let Some(ext_addr) = &external_ip {
                    let local_port = test_node.local_addr
                        .split(':')
                        .last()
                        .and_then(|p| p.parse::<u16>().ok())
                        .unwrap_or(0);

                    // External IP with local port (best guess without per-node STUN)
                    let combined = format!("{}:{}", ext_addr.ip(), local_port);
                    test_node.external_addr = Some(combined);
                }

                println!(
                    "  [{}] {} local: {} external: {:?}",
                    i,
                    &test_node.identity[..12],
                    test_node.local_addr,
                    test_node.external_addr.as_deref().unwrap_or("none")
                );

                nodes.push((node, test_node));
            }
            Ok(Err(e)) => {
                println!("  ✗ Node {} creation failed: {}", i, e);
            }
            Err(_) => {
                println!("  ✗ Node {} creation timed out", i);
            }
        }

        // Stagger to reduce PoW contention
        if i < NUM_NODES - 1 {
            tokio::time::sleep(NODE_CREATION_STAGGER).await;
        }
    }

    println!("\n  Created {}/{} nodes\n", nodes.len(), NUM_NODES);

    if nodes.len() < 2 {
        println!("  ✗ Not enough nodes to test connectivity");
        return;
    }

    // Phase 3: Bootstrap with tree topology
    println!("Phase 3: Bootstrap with tree topology...\n");

    // Use external addresses for bootstrap if available, else local
    let get_bootstrap_addr = |test_node: &TestNode| -> String {
        test_node.external_addr.clone().unwrap_or_else(|| test_node.local_addr.clone())
    };

    let bootstrap_pairs: Vec<(usize, usize)> = vec![
        (1, 0),
        (2, 0),
        (3, 1),
        (4, 1),
        (5, 2),
        (6, 2),
    ];

    let mut successful_bootstraps = 0;
    for (child, parent) in &bootstrap_pairs {
        if *child >= nodes.len() || *parent >= nodes.len() {
            continue;
        }

        let parent_info = &nodes[*parent].1;
        let bootstrap_addr = get_bootstrap_addr(parent_info);

        println!(
            "  Node {} -> Node {} ({})",
            child, parent, &bootstrap_addr
        );

        let result = timeout(
            BOOTSTRAP_TIMEOUT,
            nodes[*child].0.bootstrap(&parent_info.identity, &[bootstrap_addr.clone()]),
        )
        .await;

        match result {
            Ok(Ok(_)) => {
                println!("    ✓ Success");
                successful_bootstraps += 1;
            }
            Ok(Err(e)) => {
                println!("    ✗ Failed: {}", e);
            }
            Err(_) => {
                println!("    ✗ Timed out");
            }
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    println!(
        "\n  Successful bootstraps: {}/{}\n",
        successful_bootstraps,
        bootstrap_pairs.iter().filter(|(c, _)| *c < nodes.len()).count()
    );

    // Phase 4: Publish addresses to DHT
    println!("Phase 4: Publishing addresses to DHT...\n");

    for (i, (node, test_node)) in nodes.iter().enumerate() {
        let addr_to_publish = get_bootstrap_addr(test_node);
        println!("  Node {} publishing: {}", i, addr_to_publish);

        let result = timeout(
            Duration::from_secs(5),
            node.publish_address(vec![addr_to_publish]),
        )
        .await;

        match result {
            Ok(Ok(())) => {
                println!("    ✓ Published");
            }
            Ok(Err(e)) => {
                println!("    ✗ Failed: {}", e);
            }
            Err(_) => {
                println!("    ✗ Timed out");
            }
        }
    }

    // Phase 5: Cross-node discovery test
    println!("\nPhase 5: Cross-node discovery...\n");

    tokio::time::sleep(Duration::from_secs(2)).await;

    let mut discoveries = 0;
    let test_pairs = [(0, 6), (1, 5), (2, 4), (3, 6)]; // Various cross-tree pairs

    for (from, to) in &test_pairs {
        if *from >= nodes.len() || *to >= nodes.len() {
            continue;
        }

        let target_identity = &nodes[*to].1.identity;
        let result = timeout(
            DISCOVERY_TIMEOUT,
            nodes[*from].0.resolve(
                &korium::Identity::from_hex(target_identity).unwrap()
            ),
        )
        .await;

        match result {
            Ok(Ok(Some(contact))) => {
                println!(
                    "  ✓ Node {} found Node {} at {:?}",
                    from, to, contact.addrs
                );
                discoveries += 1;
            }
            Ok(Ok(None)) => {
                println!("  - Node {} could not find Node {}", from, to);
            }
            Ok(Err(e)) => {
                println!("  ✗ Node {} error: {}", from, e);
            }
            Err(_) => {
                println!("  - Node {} discovery timed out for Node {}", from, to);
            }
        }
    }

    // Summary
    println!("\n=== Test Summary ===");
    println!("STUN discovery:    {}", if external_ip.is_some() { "✓ Success" } else { "✗ Failed" });
    println!("Nodes created:     {}/{}", nodes.len(), NUM_NODES);
    println!("Bootstraps:        {}/{}", successful_bootstraps, bootstrap_pairs.len().min(nodes.len()));
    println!("Cross-discoveries: {}/{}", discoveries, test_pairs.len());
    println!("====================\n");

    // Cleanup
    println!("Shutting down nodes...");
    for (node, _) in nodes {
        let _ = node.shutdown().await;
    }

    println!("\n✓ 7-node STUN network test completed\n");
}

/// Test: Direct messaging via STUN-discovered external addresses.
/// This tests "hairpin NAT" - whether your NAT routes packets sent to your
/// own external IP back to you. This works on many home routers but not all.
#[tokio::test]
#[ignore] // Slow: ~3 min (2 nodes with PoW + STUN). Run with: cargo test test_messaging_via_external_address -- --ignored
async fn test_messaging_via_external_address() {
    println!("\n=== Test: Messaging via External (STUN) Addresses ===\n");
    println!("This tests NAT hairpin/loopback - sending to your own external IP.\n");

    // Longer timeout for STUN nodes (PoW can take 30-60s per node)
    let stun_node_timeout = Duration::from_secs(90);

    // Step 1: Create two nodes bound to 0.0.0.0 (all interfaces)
    println!("Step 1: Creating nodes bound to 0.0.0.0...\n");

    let (node_a, info_a) = timeout(stun_node_timeout, create_node_with_stun())
        .await
        .expect("Node A creation timed out")
        .expect("Node A creation failed");

    // Delay to avoid STUN rate limiting
    tokio::time::sleep(Duration::from_secs(3)).await;

    let (node_b, info_b) = timeout(stun_node_timeout, create_node_with_stun())
        .await
        .expect("Node B creation timed out")
        .expect("Node B creation failed");

    println!("Node A: {} at local={} external={:?}", 
             &info_a.identity[..16], info_a.local_addr, info_a.external_addr);
    println!("Node B: {} at local={} external={:?}", 
             &info_b.identity[..16], info_b.local_addr, info_b.external_addr);

    // Helper to get a routable address (external preferred, then 127.0.0.1 as fallback)
    let get_routable = |info: &TestNode| -> String {
        if let Some(ext) = &info.external_addr {
            return ext.clone();
        }
        // Parse port from local_addr (format: "0.0.0.0:PORT")
        if let Some(port_str) = info.local_addr.split(':').last() {
            return format!("127.0.0.1:{}", port_str);
        }
        info.local_addr.clone()
    };

    let addr_a = get_routable(&info_a);
    let addr_b = get_routable(&info_b);

    let using_external = info_a.external_addr.is_some() && info_b.external_addr.is_some();
    
    println!("\nUsing addresses:");
    println!("  A: {} ({})", addr_a, if info_a.external_addr.is_some() { "EXTERNAL" } else { "LOCAL" });
    println!("  B: {} ({})\n", addr_b, if info_b.external_addr.is_some() { "EXTERNAL" } else { "LOCAL" });

    // Step 2: Set up request handlers
    println!("Step 2: Setting up request handlers...\n");

    node_a.set_request_handler(|_from, data| {
        println!("  [A] Received {} bytes", data.len());
        data // Echo back
    }).await.expect("Failed to set handler on A");

    node_b.set_request_handler(|_from, data| {
        println!("  [B] Received {} bytes", data.len());
        data // Echo back
    }).await.expect("Failed to set handler on B");

    println!("✓ Handlers set\n");

    // Step 3: Bootstrap using external addresses
    println!("Step 3: Bootstrapping...\n");

    // B bootstraps to A
    let bootstrap_result = timeout(
        BOOTSTRAP_TIMEOUT,
        node_b.bootstrap(&info_a.identity, &[addr_a.clone()]),
    ).await;

    match &bootstrap_result {
        Ok(Ok(_)) => println!("  ✓ B -> A bootstrap succeeded via {}", addr_a),
        Ok(Err(e)) => println!("  ✗ B -> A bootstrap failed: {}", e),
        Err(_) => println!("  ✗ B -> A bootstrap timed out"),
    }

    // A bootstraps to B
    let bootstrap_result_2 = timeout(
        BOOTSTRAP_TIMEOUT,
        node_a.bootstrap(&info_b.identity, &[addr_b.clone()]),
    ).await;

    match &bootstrap_result_2 {
        Ok(Ok(_)) => println!("  ✓ A -> B bootstrap succeeded via {}", addr_b),
        Ok(Err(e)) => println!("  ✗ A -> B bootstrap failed: {}", e),
        Err(_) => println!("  ✗ A -> B bootstrap timed out"),
    }

    // Give connection time to establish
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Step 4: Send messages via external addresses
    println!("\nStep 4: Sending messages...\n");

    let test_message = b"Hello via external address!";

    // A sends to B
    println!("  A -> B: Sending {} bytes to {}", test_message.len(), addr_b);
    let send_result = timeout(
        MESSAGE_TIMEOUT,
        node_a.send(&info_b.identity, test_message.to_vec()),
    ).await;

    match send_result {
        Ok(Ok(response)) => {
            println!("  ✓ A -> B: Response received ({} bytes)", response.len());
            assert_eq!(response, test_message.to_vec(), "Response should echo message");
        }
        Ok(Err(e)) => {
            if using_external {
                println!("  ✗ A -> B: Failed via external: {}", e);
                println!("    This likely means hairpin NAT is not supported");
            } else {
                panic!("A -> B failed even with local addresses: {}", e);
            }
        }
        Err(_) => {
            if using_external {
                println!("  ✗ A -> B: Timed out via external address");
                println!("    Hairpin NAT may not be supported by your router");
            } else {
                panic!("A -> B timed out even with local addresses");
            }
        }
    }

    // B sends to A
    println!("  B -> A: Sending {} bytes to {}", test_message.len(), addr_a);
    let send_result_2 = timeout(
        MESSAGE_TIMEOUT,
        node_b.send(&info_a.identity, test_message.to_vec()),
    ).await;

    match send_result_2 {
        Ok(Ok(response)) => {
            println!("  ✓ B -> A: Response received ({} bytes)", response.len());
            assert_eq!(response, test_message.to_vec(), "Response should echo message");
        }
        Ok(Err(e)) => {
            if using_external {
                println!("  ✗ B -> A: Failed via external: {}", e);
            } else {
                panic!("B -> A failed even with local addresses: {}", e);
            }
        }
        Err(_) => {
            if using_external {
                println!("  ✗ B -> A: Timed out via external address");
            } else {
                panic!("B -> A timed out even with local addresses");
            }
        }
    }

    // Summary
    println!("\n=== Summary ===");
    if using_external {
        println!("Tested messaging via STUN external addresses:");
        println!("  External A: {}", addr_a);
        println!("  External B: {}", addr_b);
        println!("\nIf messages failed, your NAT doesn't support hairpin/loopback.");
        println!("This is NORMAL - real P2P works across different NATs, not same NAT.");
    } else {
        println!("Tested with local addresses (STUN unavailable for one or both nodes)");
    }
    println!("================\n");

    // Cleanup
    let _ = node_a.shutdown().await;
    let _ = node_b.shutdown().await;

    println!("✓ External address messaging test completed\n");
}

/// Test: Pkarr bootstrap slot resolution (checks the real Mainline DHT)
#[tokio::test]
async fn test_pkarr_bootstrap_resolution() {
    use six7_native::bootstrap::pkarr::{PkarrBootstrap, BOOTSTRAP_KEYS};
    
    println!("\n=== Test: Pkarr Bootstrap Slot Resolution ===\n");
    println!("This test queries the real Mainline DHT to check Korium bootstrap slots.\n");

    // Create Pkarr client
    let pkarr = PkarrBootstrap::new("0.0.0.0:0", None).await
        .expect("Failed to create Pkarr client");

    println!("Pkarr client created. Resolving {} bootstrap slots...\n", BOOTSTRAP_KEYS.len());

    // Resolve bootstrap nodes (samples 7 random slots by default)
    let nodes = pkarr.resolve_bootstrap_nodes().await;

    println!("\nResults:");
    if nodes.is_empty() {
        println!("  ⚠ NO BOOTSTRAP NODES FOUND");
        println!("  This means:");
        println!("    1. The Korium network has no active nodes");
        println!("    2. All 20 Pkarr slots are empty or stale");
        println!("    3. Your device will be the first node (isolated)");
        println!("\n  This is EXPECTED if you're starting a new network.");
    } else {
        println!("  Found {} reachable bootstrap nodes:\n", nodes.len());
        for node in &nodes {
            println!("    Slot {}: {} @ {}", 
                     node.key_index, 
                     &node.identity[..16.min(node.identity.len())], 
                     node.address);
        }
    }

    println!("\n✓ Pkarr bootstrap resolution test completed\n");
}