// LoT / LTP™ Portable Runtime Definition
// install.l — minimal bootstrap specification

SYSTEM LoT_RUNTIME {

    // ----------------------------------------
    // CORE DEVICE EXECUTION MODEL
    // ----------------------------------------

    DEVICE runtime_node {

        signal Out(t) ∈ {0,1}
        signal In(t)  ∈ {0,1}

        clock t = tick

        // ----------------------------------------
        // SIGNAL INTERFACE LAYER
        // ----------------------------------------

        emit Out(t) to MEDIUM
        receive In(t) from MEDIUM

        // ----------------------------------------
        // RELATIONAL CORE
        // ----------------------------------------

        R(t) = (In(t), Out(t))

        STATE =
            if (In(t) == 0 && Out(t) == 0) IDLE
            if (In(t) == 0 && Out(t) == 1) EMIT
            if (In(t) == 1 && Out(t) == 0) DIVERGE
            if (In(t) == 1 && Out(t) == 1) COUPLE

        // ----------------------------------------
        // TEMPORAL WINDOW ENGINE
        // ----------------------------------------

        window W = R(t-n ... t)

        SYNC = correlation(W)
        STABILITY = variance(W)

        // ----------------------------------------
        // RUNTIME BOOTSTRAP LOGIC
        // ----------------------------------------

        if (SYSTEM_BOOT == true) {

            initialize clock_sync

            initialize medium_interface

            enable signal_io Out, In

            enable window_engine W

            set mode = ACTIVE

        }

        // ----------------------------------------
        // INTERACTION POLICY
        // ----------------------------------------

        if (STABILITY > 0.8) interaction_state = LOCKED
        else if (SYNC > 0.5) interaction_state = NEGOTIATING
        else interaction_state = FREE

    }

    // ----------------------------------------
    // MEDIUM ABSTRACTION LAYER
    // ----------------------------------------

    MEDIUM supports {
        transport ∈ {wifi, bluetooth, cable, mesh}
        data_type = binary_stream
        unit = 1-bit per tick
    }

    // ----------------------------------------
    // CORE PRINCIPLE
    // ----------------------------------------

    PRINCIPLE {
        "No messages exist"
        "Only temporal binary behavior"
        "Meaning is derived from relational state over time"
    }

}