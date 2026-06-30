// LoT / LTP™ v1.0
// interpreter.l — universal temporal stream interpreter

INTERPRETER LOT_CORE {

    // --------------------------------------------------
    // INPUT MODEL
    // --------------------------------------------------

    input Stream A(t) ∈ {0,1}
    input Stream B(t) ∈ {0,1}

    clock t = tick

    // --------------------------------------------------
    // SAMPLING LAYER
    // --------------------------------------------------

    SAMPLE {

        A_t = read(A, t)
        B_t = read(B, t)

        R(t) = (A_t, B_t)

    }

    // --------------------------------------------------
    // TEMPORAL MEMORY (bounded only)
    // --------------------------------------------------

    window W = R(t-n ... t)

    // no persistent memory outside W

    // --------------------------------------------------
    // CORE INTERPRETATION ENGINE
    // --------------------------------------------------

    COMPUTE {

        SYNC = correlate(A over W, B over W)
        STABILITY = variance(W)
        ALIGNMENT = match_ratio(W)

    }

    // --------------------------------------------------
    // STATE RESOLUTION (meaning layer)
    // --------------------------------------------------

    RESOLVE {

        IF SYNC > 0.8 AND ALIGNMENT > 0.8 THEN
            state = LOCKED
            meaning = ENABLED

        ELSE IF SYNC > 0.5 THEN
            state = NEGOTIATING
            meaning = PARTIAL

        ELSE
            state = UNLOCKED
            meaning = DISABLED

    }

    // --------------------------------------------------
    // OUTPUT LAYER (what runtimes consume)
    // --------------------------------------------------

    OUTPUT {

        emit state
        emit meaning
        emit SYNC
        emit STABILITY
        emit R(t)

    }

    // --------------------------------------------------
    // SOFTWARE DEVICE COMPATIBILITY
    // --------------------------------------------------

    DEVICE_RULE {

        IF process_emits_bitstream AND process_reads_bitstream THEN
            interpret_as_device(process)

    }

    // --------------------------------------------------
    // CORE INVARIANT
    // --------------------------------------------------

    INVARIANT {

        interpretation is time-based
        no global memory exists
        meaning is derived only from W
        all devices are equal producers of streams

    }

}