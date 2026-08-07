package com.aura.mobile.aura_mobile.brain;

import com.aura.mobile.aura_mobile.brain.IAuraBrainCallback;

interface IAuraBrainService {
    int getProtocolVersion();
    String getStatusJson();
    String getCapabilitiesJson();
    void startRequest(String requestJson, IAuraBrainCallback callback);
    void cancelRequest(String requestId);
}
