// LoT / LTP™ v1.1
// api_gateway.l — universal API bridge layer
// REST/WebSocket/gRPC → Binary Stream Adapter

SYSTEM API_GATEWAY {

    // ==================================================
    // PROTOCOL ADAPTERS
    // ==================================================

    ADAPTER_REST {
        
        port = 8080
        path_prefix = "/api/v1"
        ssl = true
        
        // Device status query
        ENDPOINT GET /device/{id}/status {
            
            QUERY_MAPPING {
                device_id = path_param("id")
                device = lookup_device(device_id)
            }
            
            LOT_TRANSLATION {
                // read current R(t) from interpreter
                A(t) = device.In(t)
                B(t) = device.Out(t)
                R(t) = (A(t), B(t))
                W = device.window
                SYNC = correlate(A over W, B over W)
                STABILITY = variance(W)
            }
            
            RESPONSE {
                return {
                    status: state_name(SYNC, STABILITY),
                    device_id: device_id,
                    relation: R(t),
                    state_int: binary_to_int(R(t)),
                    sync: SYNC,
                    stability: STABILITY,
                    health: device.Health(t),
                    medium: device.current_medium,
                    timestamp: now(),
                    window_size: len(W),
                }
            }
            
            HTTP_STATUS {
                IF state == LOCKED: return 200
                ELSE IF state == NEGOTIATING: return 202
                ELSE IF state == UNLOCKED: return 503
                ELSE: return 500
            }
        }
        
        // Device action/control
        ENDPOINT POST /device/{id}/action {
            
            PAYLOAD {
                action: string,    // "pulse", "toggle", "hold", "release"
                duration: number,  // milliseconds (optional)
                force: boolean,    // force even if UNLOCKED
            }
            
            ACTION_MAPPING {
                IF action == "pulse":
                    Out(t+1) = 1
                    schedule Out(t+2) = 0
                    
                ELSE IF action == "toggle":
                    Out(t+1) = NOT Out(t)
                    
                ELSE IF action == "hold":
                    Out(t+1) = 1
                    hold_until = now() + duration
                    
                ELSE IF action == "release":
                    Out(t+1) = 0
            }
            
            SAFETY_CHECK {
                IF state != LOCKED AND NOT force:
                    return {
                        error: "device_not_locked",
                        http_status: 409,
                        advice: "device must be LOCKED or use force=true"
                    }
            }
            
            RESPONSE {
                return {
                    action: action,
                    device_id: device_id,
                    applied: true,
                    next_state: R(t+1),
                    expected_response: await_In_t(timeout=1s),
                    timestamp: now(),
                }
            }
        }
        
        // Bulk device query
        ENDPOINT GET /devices {
            
            QUERY {
                filter: optional,  // "locked", "negotiating", "lost"
                medium: optional,  // filter by transport medium
                limit: default 100,
            }
            
            LOT_FILTER {
                devices = [
                    device for device in all_devices
                    if (filter == null OR filter == state_name(device.SYNC, device.STABILITY))
                    AND (medium == null OR medium == device.current_medium)
                ]
            }
            
            RESPONSE {
                return {
                    count: len(devices),
                    devices: [
                        {
                            id: device.id,
                            state: state_name(device.SYNC, device.STABILITY),
                            sync: device.SYNC,
                            stability: device.STABILITY,
                            health: device.Health(t),
                            medium: device.current_medium,
                        }
                        for device in devices
                    ]
                }
            }
        }
        
        // System health
        ENDPOINT GET /health {
            
            SYSTEM_STATUS {
                active_devices = count(devices where Health(t) == 1)
                degraded_devices = count(devices where Health(t) == 2)
                lost_devices = count(devices where Health(t) == 0)
                
                avg_sync = mean([d.SYNC for d in devices])
                avg_stability = mean([d.STABILITY for d in devices])
            }
            
            RESPONSE {
                return {
                    status: IF avg_sync > 0.75 THEN "healthy" ELSE "degraded",
                    timestamp: now(),
                    devices: {
                        active: active_devices,
                        degraded: degraded_devices,
                        lost: lost_devices,
                    },
                    metrics: {
                        avg_sync: avg_sync,
                        avg_stability: avg_stability,
                        uptime_seconds: since_boot(),
                    }
                }
            }
        }
        
        // Metrics export
        ENDPOINT GET /metrics {
            
            METRICS_EXPORT {
                format: "json" OR "prometheus"
                
                IF format == "prometheus":
                    return format_prometheus([
                        "lot_device_sync{id=...}",
                        "lot_device_stability{id=...}",
                        "lot_failover_events_total",
                        "lot_medium_switch_duration_ms",
                        "lot_api_request_duration_ms",
                    ])
                ELSE:
                    return format_json(telemetry.export())
            }
        }
        
        // Failover trigger (manual)
        ENDPOINT POST /device/{id}/failover {
            
            TRIGGER {
                device = lookup_device(path_param("id"))
                device.trigger_failover()
            }
            
            RESPONSE {
                return {
                    device_id: path_param("id"),
                    failover_triggered: true,
                    from_medium: device.current_medium,
                    timestamp: now(),
                }
            }
        }
    }

    ADAPTER_WEBSOCKET {
        
        port = 8081
        path_prefix = "/ws/v1"
        ssl = true
        
        // Real-time device stream
        ENDPOINT WS /stream/{id} {
            
            ON_CONNECT {
                device_id = path_param("id")
                device = lookup_device(device_id)
                subscriber_id = uuid()
                
                device.add_subscriber(subscriber_id)
                
                send {
                    type: "connected",
                    device_id: device_id,
                    subscriber_id: subscriber_id,
                    timestamp: now(),
                }
            }
            
            ON_MESSAGE {
                msg = parse_json(frame.data)
                
                IF msg.type == "subscribe":
                    device.add_subscriber(subscriber_id, {
                        interval: msg.interval_ms,
                        filters: msg.filters,
                    })
                
                ELSE IF msg.type == "unsubscribe":
                    device.remove_subscriber(subscriber_id)
                
                ELSE IF msg.type == "action":
                    // receive action from client
                    execute_action(device, msg.action)
            }
            
            ON_TICK {
                // emit R(t) for each subscriber
                FOR each subscriber IN device.subscribers:
                    send {
                        type: "tick",
                        device_id: device_id,
                        relation: R(t),
                        sync: SYNC,
                        stability: STABILITY,
                        health: Health(t),
                        timestamp: now(),
                    }
            }
            
            HEARTBEAT {
                every 5s send {
                    type: "ping",
                    timestamp: now(),
                }
            }
            
            ON_DISCONNECT {
                device.remove_subscriber(subscriber_id)
                
                send {
                    type: "disconnected",
                    device_id: device_id,
                    timestamp: now(),
                }
            }
        }
        
        // Broadcast stream (all devices)
        ENDPOINT WS /stream/broadcast {
            
            ON_CONNECT {
                broadcast_subscriber_id = uuid()
                global_broadcast.add_subscriber(broadcast_subscriber_id)
                
                send {
                    type: "connected_broadcast",
                    subscriber_id: broadcast_subscriber_id,
                }
            }
            
            ON_TICK {
                send {
                    type: "broadcast",
                    devices: [
                        {
                            id: device.id,
                            relation: R(t),
                            sync: device.SYNC,
                            state: state_name(device.SYNC, device.STABILITY),
                        }
                        for device in all_devices
                    ],
                    timestamp: now(),
                }
            }
        }
    }

    ADAPTER_GRPC {
        
        port = 50051
        ssl = true
        // (protobuf service definition in separate .proto file)
        
        SERVICE DeviceStream {
            
            rpc GetStatus(DeviceId) returns (DeviceStatus)
            rpc SendAction(ActionRequest) returns (ActionResponse)
            rpc StreamDevice(DeviceId) returns (stream Tick)
            rpc StreamBroadcast(Empty) returns (stream BroadcastTick)
            rpc TriggerFailover(DeviceId) returns (FailoverResponse)
        }
    }

    // ==================================================
    // CROSS-PROTOCOL UTILITIES
    // ==================================================

    FUNCTION state_name(SYNC, STABILITY) -> string {
        IF SYNC > 0.80 AND STABILITY > 0.75:
            RETURN "LOCKED"
        ELSE IF SYNC > 0.50:
            RETURN "NEGOTIATING"
        ELSE:
            RETURN "UNLOCKED"
    }

    FUNCTION binary_to_int(R(t)) -> int {
        // convert (A, B) to 0-3
        RETURN (A(t) << 1) | B(t)
    }

    FUNCTION await_In_t(timeout) -> binary {
        // wait for device to respond to our Out(t)
        start = now()
        LOOP {
            IF In(t) changed:
                RETURN In(t)
            IF now() - start > timeout:
                RETURN null
        }
    }

    // ==================================================
    // REQUEST/RESPONSE MAPPING
    // ==================================================

    CONTENT_TYPE_HANDLING {
        
        accept: "application/json" -> encode_json()
        accept: "application/xml"  -> encode_xml()
        accept: "text/plain"       -> encode_text()
        accept: "text/csv"         -> encode_csv()
        accept: "application/protobuf" -> encode_protobuf()
        
        default: "application/json"
    }

    ERROR_HANDLING {
        
        error_device_not_found -> {
            http: 404,
            body: { error: "device_not_found", device_id: id }
        }
        
        error_state_mismatch -> {
            http: 409,
            body: { error: "state_mismatch", expected: s1, received: s2 }
        }
        
        error_timeout -> {
            http: 504,
            body: { error: "timeout", operation: op }
        }
        
        error_unauthorized -> {
            http: 401,
            body: { error: "unauthorized" }
        }
        
        error_rate_limited -> {
            http: 429,
            body: { error: "rate_limited", retry_after: seconds }
        }
    }

    // ==================================================
    // AUTHENTICATION & AUTHORIZATION
    // ==================================================

    AUTH {
        
        strategy: "api_key" OR "jwt" OR "oauth2" OR "none"
        
        validate_request(request) {
            IF auth_strategy == "none":
                RETURN true
            
            token = extract_auth_header(request)
            IF token == null:
                RETURN false
            
            RETURN validate_token(token)
        }
    }

    // ==================================================
    // RATE LIMITING
    // ==================================================

    RATE_LIMIT {
        
        global_limit = 1000 requests/second
        per_peer_limit = 100 requests/second
        per_device_limit = 50 requests/second
        
        STRATEGY: "token_bucket"
        
        check_limit(request) {
            peer_id = request.remote_addr
            device_id = request.device_id
            
            IF token_count(global) < 1:
                REJECT with 429
            
            IF token_count(peer_id) < 1:
                REJECT with 429
            
            IF token_count(device_id) < 1:
                REJECT with 429
            
            decrement_tokens()
            ALLOW request
        }
    }

    // ==================================================
    // INVARIANT
    // ==================================================

    INVARIANT {
        
        properties = [
            "All API responses preserve R(t) integrity",
            "WebSocket streams never lose ticks (buffered)",
            "HTTP request/response pairs are stateless",
            "gRPC streams maintain device synchronization",
            "Failover is transparent to API clients",
            "API state matches interpreter state exactly",
        ]
    }

}

