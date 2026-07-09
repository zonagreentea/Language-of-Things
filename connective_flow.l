// LoT / LTP™ v1.1 TERNARY
// connective_flow.l — automatic multi-medium failover + recovery orchestration

SYSTEM CONNECTIVE_FLOW {

    // --------------------------------------------------
    // MULTI-MEDIUM POOL
    // --------------------------------------------------

    MEDIA available {
        wifi:       { priority = 1, latency = 10ms, bandwidth = high, reliability = 0.95 }
        bluetooth:  { priority = 2, latency = 50ms, bandwidth = low, reliability = 0.85 }
        cable:      { priority = 3, latency = 1ms, bandwidth = high, reliability = 0.99 }
        mesh:       { priority = 4, latency = 50ms, bandwidth = low, reliability = 0.80 }
        lte:        { priority = 5, latency = 100ms, bandwidth = medium, reliability = 0.90 }
    }

    current_medium = wifi  // start with primary
    flow_state = ACTIVE    // ACTIVE, PAUSED, SWITCHING, LOST

    // --------------------------------------------------
    // CONNECTIVE FLOW STATE MACHINE
    // --------------------------------------------------

    FLOW_STATE_MACHINE {

        ACTIVE: [H=1, medium operational]
            on Health(t)→0 goto DISCONNECTED
            on error_spike goto DEGRADED
            on signal_loss goto DEGRADED

        DEGRADED: [H=2, current medium struggling]
            on recovery goto ACTIVE
            on persistent_failure goto SWITCHING

        SWITCHING: [H=2, medium transition in progress]
            on switch_success goto ACTIVE
            on switch_fail_retry goto SWITCHING
            on all_mediums_fail goto LOST

        DISCONNECTED: [H=0, connection suddenly lost]
            on trigger_failover goto SWITCHING

        LOST: [H=0, no medium available]
            on manual_intervention goto SWITCHING
            on any_medium_available goto SWITCHING

    }

    // --------------------------------------------------
    // FAILOVER TRIGGER DETECTION
    // --------------------------------------------------

    TRIGGER failover_event {

        IF Health(t) == 0 THEN {
            // Connection lost detected
            reason = CONNECTION_LOST
            event_severity = CRITICAL
            trigger_flow_switch()
        }

        ELSE IF error_rate > threshold THEN {
            // Too many errors on current medium
            reason = ERROR_THRESHOLD_EXCEEDED
            event_severity = HIGH
            trigger_flow_degrade()
        }

        ELSE IF latency > threshold THEN {
            // Latency degradation detected
            reason = LATENCY_SPIKE
            event_severity = MEDIUM
            trigger_flow_degrade()
        }

        ELSE IF signal_strength < threshold THEN {
            // Signal degradation (for wireless)
            reason = SIGNAL_DEGRADATION
            event_severity = MEDIUM
            trigger_flow_degrade()
        }

        ELSE IF packet_loss > threshold THEN {
            // High packet loss detected
            reason = PACKET_LOSS_HIGH
            event_severity = HIGH
            trigger_flow_switch()
        }

    }

    // --------------------------------------------------
    // FLOW DEGRADATION (PREVENTIVE)
    // --------------------------------------------------

    FUNCTION trigger_flow_degrade() {

        // lower expectations, increase error correction
        Health(t) = 2  // PAUSED/DEGRADED

        reduce_throughput()
        increase_error_correction()
        increase_retry_attempts()

        // monitor for recovery
        degradation_timer = start_timer(30s)

        IF signal_recovers THEN {
            stop_timer(degradation_timer)
            Health(t) = 1  // back to NORMAL
            restore_throughput()
        }

        ELSE IF degradation_timer expires THEN {
            // not recovering, time to switch
            trigger_flow_switch()
        }

    }

    // --------------------------------------------------
    // FLOW SWITCH (CORRECTIVE)
    // --------------------------------------------------

    FUNCTION trigger_flow_switch() {

        flow_state = SWITCHING
        Health(t) = 2  // PAUSED

        // save current state
        cache_state = preserve(R(t), W, last_valid_state, timestamp)

        emit event("flow_switching", {
            from_medium: current_medium,
            reason: failover_reason,
            timestamp: now()
        })

        // find next available medium
        next_medium = select_next_medium(current_medium)

        IF next_medium == null THEN {
            // no other medium available
            flow_state = LOST
            Health(t) = 0  // LOST
            emit event("flow_lost", { timestamp: now() })
            attempt_manual_recovery()
            RETURN
        }

        // attempt switch
        IF try_switch_medium(next_medium) THEN {

            // switch successful
            current_medium = next_medium
            flow_state = ACTIVE
            Health(t) = 1  // NORMAL

            // validate state on new medium
            IF validate_cached_state() THEN {
                emit event("flow_resumed", {
                    on_medium: current_medium,
                    timestamp: now()
                })
                resume_processing()
            } ELSE {
                // validation failed, try next
                trigger_flow_switch()
            }

        } ELSE {

            // switch failed, try next option
            flow_state = SWITCHING
            Health(t) = 2  // stay paused
            trigger_flow_switch()  // recursive attempt

        }

    }

    // --------------------------------------------------
    // MEDIUM SELECTION STRATEGY
    // --------------------------------------------------

    FUNCTION select_next_medium(current) {

        // strategy: try next in priority order that's available
        // weighted by reliability and latency

        available_list = sort(MEDIA by priority)

        FOR each medium IN available_list {

            IF medium != current AND is_available(medium) THEN {

                // quick probe: can we reach the peer on this medium?
                IF probe_medium(medium, timeout=500ms) THEN {
                    RETURN medium
                }

            }

        }

        RETURN null  // no medium available

    }

    // --------------------------------------------------
    // MEDIUM SWITCH LOGIC
    // --------------------------------------------------

    FUNCTION try_switch_medium(new_medium) {

        emit event("medium_switch_attempt", {
            from: current_medium,
            to: new_medium,
            timestamp: now()
        })

        // close current medium gracefully
        close_transport(current_medium, graceful=true)

        // initialize new medium
        IF NOT initialize_transport(new_medium) THEN {
            emit event("medium_init_failed", { medium: new_medium })
            RETURN false
        }

        // send probe packet on new medium
        probe_count = 0
        MAX_PROBES = 3

        LOOP {

            send_probe_packet(new_medium)

            IF receive_ack_within(timeout=200ms) THEN {
                emit event("medium_probe_success", { medium: new_medium })
                RETURN true
            }

            probe_count += 1

            IF probe_count > MAX_PROBES THEN {
                close_transport(new_medium)
                emit event("medium_probe_exhausted", { medium: new_medium })
                RETURN false
            }

        }

    }

    // --------------------------------------------------
    // STATE PRESERVATION ON SWITCH
    // --------------------------------------------------

    FUNCTION preserve_state {

        cache_state = {
            current_state: R(t),
            window: W,
            sync: SYNC,
            stability: STABILITY,
            health: Health(t),
            last_valid: last_valid_state,
            timestamp: now(),
            medium_from: current_medium,
            hash: checksum(R(t) + W)  // for validation
        }

        IF time_since_cache() > max_cache_lifetime THEN {
            // cache stale, may need to discard
            Health(t) = 2  // PAUSED, may need manual intervention
            emit event("cache_stale", { age: time_since_cache() })
        }

    }

    // --------------------------------------------------
    // STATE VALIDATION AFTER SWITCH
    // --------------------------------------------------

    FUNCTION validate_cached_state {

        // verify state consistency on new medium

        IF cache_state == null THEN RETURN false

        // send state query on new medium
        send_state_query(new_medium)

        IF receive_state_ack_within(timeout=500ms) THEN {

            // verify remote state hash matches cache
            IF remote_hash == cache_state.hash THEN {

                flow_state = ACTIVE
                Health(t) = 1  // NORMAL
                emit event("state_validated", { medium: new_medium })
                resume_from_cache()
                RETURN true

            } ELSE {

                // state mismatch
                Health(t) = 2  // PAUSED
                emit event("state_mismatch", {
                    expected: cache_state.hash,
                    received: remote_hash
                })
                RETURN false

            }

        } ELSE {

            // state query timeout
            Health(t) = 2  // PAUSED
            emit event("state_query_timeout", { medium: new_medium })
            RETURN false

        }

    }

    // --------------------------------------------------
    // PRIORITY & FAILBACK ORCHESTRATION
    // --------------------------------------------------

    PRIORITY_MONITOR {

        // continuously monitor if primary medium is back
        monitor_interval = 5s

        IF current_medium != wifi AND is_available(wifi) THEN {

            // primary is back, evaluate failback
            evaluate_failback_to_primary()

        }

    }

    FUNCTION evaluate_failback_to_primary {

        // criteria: is primary medium stable enough to return?

        IF signal_stable_for(5s) AND
           error_rate_low AND
           latency_acceptable AND
           reliability_high THEN {

            trigger_flow_failback()

        }

    }

    FUNCTION trigger_flow_failback {

        // graceful transition back to primary medium
        emit event("failback_initiated", { to_medium: wifi })

        flow_state = SWITCHING
        Health(t) = 2  // PAUSED

        IF try_switch_medium(wifi) THEN {

            current_medium = wifi
            flow_state = ACTIVE
            Health(t) = 1  // NORMAL

            emit event("failback_success", { to_medium: wifi })

        } ELSE {

            // failback failed, stay on current
            flow_state = ACTIVE
            Health(t) = 1

            emit event("failback_failed", { attempted: wifi })

        }

    }

    // --------------------------------------------------
    // FLOW TELEMETRY & LOGGING
    // --------------------------------------------------

    TELEMETRY {

        track {
            flow_state_transitions,
            medium_switches,
            switch_duration,
            state_validation_results,
            cache_hit_rate,
            failover_success_rate,
            medium_reliability_per_session
        }

    }

    // --------------------------------------------------
    // FLOW RECOVERY POLICY
    // --------------------------------------------------

    RECOVERY_POLICY {

        max_switch_attempts = 5
        max_cache_age = 30s
        degradation_timeout = 30s
        probe_timeout = 500ms
        state_validation_timeout = 500ms
        failback_stability_window = 5s
        failback_check_interval = 5s

    }

    // --------------------------------------------------
    // CORE INVARIANT
    // --------------------------------------------------

    INVARIANT {

        R(t) = (In(t), Out(t), Health(t)) always valid regardless of medium
        connective flow is transparent to upper layers
        state is preserved and validated across medium changes
        failover is automatic on detected disconnect or degradation
        failback to primary is opportunistic but safe
        no data is lost during flow switch (cached and validated)
        flow state is always observable via Health(t)
        all transitions are logged for debugging

    }

}
