package com.aura.mobile.aura_mobile.brain;

oneway interface IAuraBrainCallback {
    void onEvent(String requestId, String eventJson);
}
