// LoT / LTP™ v1.1
// software_device_identifiers.l — device identity and registration system
// Extends software_device.l with connectable identifier framework

MODULE SOFTWARE_DEVICE_IDENTIFIERS {

    // --------------------------------------------------
    // DEVICE IDENTIFIER SYSTEM
    // --------------------------------------------------

    DEVICE_IDENTITY {

        // Unique device reference
        device_id:      string      // global unique identifier (UUID)
        type:           string      // "software" | "hardware" | "hybrid"
        name:           string      // human-readable name
        category:       string      // "worker" | "server" | "client" | "gateway" | "sensor" | "actuator"
        version:        string      // semantic version
        
        // Registration metadata
        registered_at:  timestamp
        registered_by:  string      // process or system that registered it
        capabilities:   array       // ["emit", "receive", "state_preservation", "failover"]
        
    }

    // --------------------------------------------------
    // SOFTWARE DEVICE REFERENCE TYPES
    // --------------------------------------------------

    REFERENCE_TYPE process_id {
        // Traditional OS process identifier
        pid:            integer
        platform:       string      // "linux" | "windows" | "macos" | "embedded"
        binary_path:    string
    }

    REFERENCE_TYPE service_endpoint {
        // Network-addressable service
        protocol:       string      // "http" | "grpc" | "ws" | "custom"
        host:           string
        port:           integer
        path:           string      // optional path prefix
        tls:            boolean
    }

    REFERENCE_TYPE message_queue {
        // Async messaging system
        broker:         string      // "redis" | "rabbitmq" | "kafka" | "nats"
        queue_name:     string
        topic:          string      // optional for pub/sub
        channel:        string      // optional routing key
    }

    REFERENCE_TYPE container {
        // Container runtime
        runtime:        string      // "docker" | "podman" | "kubernetes"
        container_id:   string
        pod_namespace:  string      // for kubernetes
        pod_name:       string      // for kubernetes
    }

    REFERENCE_TYPE thread {
        // In-process thread
        thread_id:      integer
        process_id:     integer     // parent process
        name:           string      // thread name
    }

    REFERENCE_TYPE function_callback {
        // Direct function reference
        module:         string
        function_name:  string
        language:       string      // "python" | "javascript" | "go" | "rust" | "c++"
        context:        object      // closure/environment
    }

    // --------------------------------------------------
    // DEVICE REGISTRY
    // --------------------------------------------------

    DEVICE_REGISTRY {

        devices: map[device_id -> DEVICE_IDENTITY]
        references: map[device_id -> array<REFERENCE>]
        connections: map[(device_id_a, device_id_b) -> CONNECTION_STATE]
        
        // --------------------------------------------------
        // REGISTRATION
        // --------------------------------------------------

        FUNCTION register_device(identity, reference_list) -> device_id {

            device_id = generate_uuid()

            identity.device_id = device_id
            identity.registered_at = now()

            devices[device_id] = identity
            references[device_id] = reference_list

            emit event("device_registered", {
                device_id: device_id,
                name: identity.name,
                type: identity.type,
                references: reference_list.count,
                timestamp: now()
            })

            RETURN device_id

        }

        // --------------------------------------------------
        // LOOKUP & RESOLUTION
        // --------------------------------------------------

        FUNCTION resolve_device(identifier) -> DEVICE_IDENTITY {

            // identifier can be:
            // - device_id directly
            // - pid (process_id)
            // - host:port (service_endpoint)
            // - container_id
            // - function_name
            
            // First, try direct lookup
            IF identifier in devices:
                RETURN devices[identifier]

            // Otherwise, search references
            FOR each (device_id, ref_list) IN references {

                FOR each ref IN ref_list {

                    IF ref matches identifier THEN {
                        RETURN devices[device_id]
                    }

                }

            }

            RETURN null  // not found

        }

        FUNCTION list_devices(filter) -> array<DEVICE_IDENTITY> {

            // filter options: type, category, capabilities, registered_by
            
            result = []

            FOR each (device_id, identity) IN devices {

                matches = true

                IF filter.type != null AND identity.type != filter.type:
                    matches = false

                IF filter.category != null AND identity.category != filter.category:
                    matches = false

                IF filter.capabilities != null:
                    for each cap IN filter.capabilities:
                        IF cap NOT IN identity.capabilities:
                            matches = false

                IF matches:
                    result.append(identity)

            }

            RETURN result

        }

        // --------------------------------------------------
        // DEREGISTRATION
        // --------------------------------------------------

        FUNCTION deregister_device(device_id) {

            IF device_id NOT IN devices:
                RETURN false

            // close all connections
            FOR each (a, b) IN connections {
                IF a == device_id OR b == device_id:
                    close_connection(a, b)
            }

            delete devices[device_id]
            delete references[device_id]

            emit event("device_deregistered", {
                device_id: device_id,
                timestamp: now()
            })

            RETURN true

        }

    }

    // --------------------------------------------------
    // CONNECTION ESTABLISHMENT
    // --------------------------------------------------

    CONNECTION_STATE {
        device_a_id:    string
        device_b_id:    string
        state:          string      // "connecting" | "active" | "paused" | "error" | "closed"
        established_at: timestamp
        last_heartbeat: timestamp
        health:         float       // 0.0 to 1.0
        medium:         string      // communication medium used
    }

    FUNCTION connect_devices(device_id_a, device_id_b, options) -> CONNECTION_STATE {

        // Resolve device identities
        device_a = resolve_device(device_id_a)
        device_b = resolve_device(device_id_b)

        IF device_a == null OR device_b == null:
            RETURN error("one_or_both_devices_not_found")

        // Validate capabilities
        IF "receive" NOT IN device_a.capabilities:
            RETURN error("device_a_cannot_receive")

        IF "emit" NOT IN device_b.capabilities:
            RETURN error("device_b_cannot_emit")

        // Determine best medium
        medium = select_medium(device_a, device_b, options.preferred_media)

        IF medium == null:
            RETURN error("no_suitable_medium_found")

        // Establish connection
        connection = CONNECTION_STATE {
            device_a_id: device_a.device_id,
            device_b_id: device_b.device_id,
            state: "connecting",
            established_at: null,
            last_heartbeat: now(),
            health: 0.5,
            medium: medium,
        }

        // Create bidirectional stream pipes
        IF establish_stream_pipe(device_a, device_b, medium) THEN {

            connection.state = "active"
            connection.established_at = now()
            connection.health = 1.0

            connections[(device_a.device_id, device_b.device_id)] = connection

            emit event("devices_connected", {
                device_a_id: device_a.device_id,
                device_b_id: device_b.device_id,
                medium: medium,
                timestamp: now()
            })

            RETURN connection

        } ELSE {

            emit event("connection_failed", {
                device_a_id: device_a.device_id,
                device_b_id: device_b.device_id,
                medium: medium,
                timestamp: now()
            })

            RETURN error("stream_pipe_establishment_failed")

        }

    }

    // --------------------------------------------------
    // MEDIUM SELECTION STRATEGY
    // --------------------------------------------------

    FUNCTION select_medium(device_a, device_b, preferred) -> string {

        // Analyze device types and references to determine best medium

        available_media = []

        // Process-to-process: direct IPC
        IF is_process_type(device_a.ref) AND is_process_type(device_b.ref):
            IF same_machine(device_a.ref, device_b.ref):
                available_media.append({
                    medium: "ipc_pipe",
                    priority: 1,
                    latency: 1,
                })

        // Function-to-function: direct callback
        IF is_function_type(device_a.ref) AND is_function_type(device_b.ref):
            available_media.append({
                medium: "function_callback",
                priority: 0,
                latency: 0.1,
            })

        // Thread-to-thread: shared memory
        IF is_thread_type(device_a.ref) AND is_thread_type(device_b.ref):
            IF same_process(device_a.ref, device_b.ref):
                available_media.append({
                    medium: "shared_memory",
                    priority: 0.5,
                    latency: 0.5,
                })

        // Service-to-service: REST/gRPC
        IF is_service_type(device_a.ref) AND is_service_type(device_b.ref):
            available_media.append({
                medium: "rest_api",
                priority: 2,
                latency: 10,
            })
            available_media.append({
                medium: "grpc_stream",
                priority: 2,
                latency: 5,
            })

        // Container-to-container: docker network / k8s
        IF is_container_type(device_a.ref) AND is_container_type(device_b.ref):
            available_media.append({
                medium: "container_network",
                priority: 3,
                latency: 2,
            })

        // Message queue: async broker
        IF has_capability(device_a, "async") OR has_capability(device_b, "async"):
            available_media.append({
                medium: "message_broker",
                priority: 4,
                latency: 50,
            })

        // Generic fallback: TCP/WebSocket
        available_media.append({
            medium: "websocket",
            priority: 5,
            latency: 10,
        })

        // Respect preferred media if specified
        IF preferred != null:
            FOR each m IN available_media:
                IF m.medium == preferred:
                    RETURN preferred

        // Otherwise, select by priority (lower = better)
        IF available_media.count > 0:
            best = min(available_media by priority)
            RETURN best.medium

        RETURN null

    }

    // --------------------------------------------------
    // BIDIRECTIONAL STREAM ESTABLISHMENT
    // --------------------------------------------------

    FUNCTION establish_stream_pipe(device_a, device_b, medium) -> boolean {

        // Create the actual communication channel

        SWITCH medium {

            CASE "ipc_pipe":
                RETURN establish_ipc_pipe(device_a.ref, device_b.ref)

            CASE "shared_memory":
                RETURN establish_shared_memory(device_a.ref, device_b.ref)

            CASE "function_callback":
                RETURN establish_function_callback(device_a.ref, device_b.ref)

            CASE "rest_api":
                RETURN establish_rest_api(device_a.ref, device_b.ref)

            CASE "grpc_stream":
                RETURN establish_grpc_stream(device_a.ref, device_b.ref)

            CASE "container_network":
                RETURN establish_container_network(device_a.ref, device_b.ref)

            CASE "message_broker":
                RETURN establish_message_broker(device_a.ref, device_b.ref)

            CASE "websocket":
                RETURN establish_websocket(device_a.ref, device_b.ref)

            DEFAULT:
                RETURN false

        }

    }

    // --------------------------------------------------
    // SOFT DEVICE IDENTIFIER PATTERNS (EXAMPLES)
    // --------------------------------------------------

    EXAMPLES {

        // Python async worker
        worker_device = DEVICE_IDENTITY {
            name: "task_worker_001",
            type: "software",
            category: "worker",
            capabilities: ["emit", "receive", "state_preservation"],
        }

        worker_ref = REFERENCE_TYPE.function_callback {
            module: "tasks.workers",
            function_name: "process_task",
            language: "python",
        }

        register_device(worker_device, [worker_ref])

        // ---

        // HTTP microservice
        api_device = DEVICE_IDENTITY {
            name: "user_service",
            type: "software",
            category: "server",
            capabilities: ["emit", "receive", "failover"],
        }

        api_ref = REFERENCE_TYPE.service_endpoint {
            protocol: "http",
            host: "localhost",
            port: 3000,
            path: "/api/v1",
            tls: false,
        }

        register_device(api_device, [api_ref])

        // ---

        // Docker container
        container_device = DEVICE_IDENTITY {
            name: "redis_cache",
            type: "software",
            category: "server",
            capabilities: ["receive", "failover"],
        }

        container_ref = REFERENCE_TYPE.container {
            runtime: "docker",
            container_id: "abc123def456",
        }

        register_device(container_device, [container_ref])

        // ---

        // Message queue subscriber
        queue_device = DEVICE_IDENTITY {
            name: "event_processor",
            type: "software",
            category: "worker",
            capabilities: ["emit", "receive"],
        }

        queue_ref = REFERENCE_TYPE.message_queue {
            broker: "kafka",
            topic: "events",
            queue_name: "event_processor",
        }

        register_device(queue_device, [queue_ref])

    }

    // --------------------------------------------------
    // INVARIANT
    // --------------------------------------------------

    INVARIANT {

        properties = [
            "All software devices must have a unique device_id",
            "All software devices must have at least one REFERENCE_TYPE",
            "Each device must declare its capabilities",
            "Connections preserve R(t) stream integrity across medium changes",
            "Device registry is authoritative source of truth",
            "Software devices are equivalent to hardware devices at LoT layer",
            "Identifier resolution must be deterministic and fast",
        ]

    }

}
