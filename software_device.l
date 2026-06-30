// LoT / LTP™ v1.0
// software_device.l — software process as LoT participant

MODULE SOFTWARE_DEVICE {

    // --------------------------------------------------
    // DEVICE ABSTRACTION
    // --------------------------------------------------

    DEVICE process_node {

        type ∈ {software, hardware}

        signal Out(t) ∈ {0,1}
        signal In(t)  ∈ {0,1}

        clock t = tick

        // software devices are just processes emitting streams
        EMIT Out(t) from PROCESS_STATE
        RECEIVE In(t) from MEDIUM

    }

    // --------------------------------------------------
    // PROCESS-BASED BEHAVIOR
    // --------------------------------------------------

    PROCESS_STATE {

        // any software system can be mapped here:
        // - event loop
        // - async function
        // - server tick
        // - UI frame
        // - background worker

        Out(t) = f(local_state, inputs, timers)

    }

    // --------------------------------------------------
    // IDENTITY IS NON-DISTINCT
    // --------------------------------------------------

    PRINCIPLE {

        "hardware and software are identical at stream level"
        "only difference is emission source"
        "all devices reduce to binary time-series emitters"

    }

    // --------------------------------------------------
    // INTEGRATION RULE
    // --------------------------------------------------

    RULE {

        IF process_can_emit_bitstream AND process_can_read_bitstream THEN
            process_is_device = TRUE

    }

}