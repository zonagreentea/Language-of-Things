// LoT / LTP™ v1.0
// languageofthings.l — initial commit seed

DEVICE node_0 {

    // 1-bit temporal stream interface
    signal Out(t) ∈ {0,1}
    signal In(t)  ∈ {0,1}

    // discrete clock tick
    clock t = tick

    // relational state per tick
    R(t) = (In(t), Out(t))

    // 4-state relation map (interpretation layer)
    if (In(t) == 0 && Out(t) == 0) state = IDLE
    if (In(t) == 0 && Out(t) == 1) state = EMISSION
    if (In(t) == 1 && Out(t) == 0) state = DIVERGENCE
    if (In(t) == 1 && Out(t) == 1) state = COUPLED

    // temporal window (no persistent memory beyond this)
    window W = R(t-n ... t)

    // derived properties (logic layer)
    SYNC = correlation(W)
    STABILITY = variance(W)

    // interaction rule (minimal)
    if (STABILITY > 0.8) interaction = LOCKED
    else if (SYNC > 0.5) interaction = NEGOTIATING
    else interaction = FREE

}

// LoT does not transmit messages.
// It transmits time-based binary behavior.
// Meaning is computed, not sent.