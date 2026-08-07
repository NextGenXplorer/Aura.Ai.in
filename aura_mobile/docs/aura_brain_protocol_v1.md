# Aura Brain Protocol V1

Aura Brain is a bound Android Binder service owned by the standalone Aura app. It accepts only ephemeral, local-only requests from explicitly approved, same-signature Quilonix apps. It is not an HTTP, WebSocket, broadcast, clipboard, file-transfer, or deep-link prompt interface.

## Android contract

| Item | Value |
|---|---|
| Aura package ID | `com.aura.mobile.aura_mobile` |
| Service component | `com.aura.mobile.aura_mobile/.brain.AuraBrainService` |
| Service class | `com.aura.mobile.aura_mobile.brain.AuraBrainService` |
| Signature permission | `com.aura.mobile.aura_mobile.permission.USE_AURA_BRAIN` |
| AIDL package | `com.aura.mobile.aura_mobile.brain` |
| Protocol version | `1` |
| MethodChannel | `com.aura.mobile.aura_mobile/brain/v1` |
| Initially allowed external package | `com.quilonix.quilonix` |

The client must declare the signature permission and be signed with the same signing identity as Aura. Aura additionally resolves the Binder caller UID, checks that one of its packages is explicitly allowlisted, and compares that package signature with Aura. `clientId` is metadata and is never used as authentication.

The allowed-package configuration is intentionally centralized in `AuraBrainAllowedClients` in `AuraBrainCallerValidator.kt`. Adding a future Quilonix app requires an explicit code review and allowlist change.

## AIDL API

```aidl
interface IAuraBrainService {
    int getProtocolVersion();
    String getStatusJson();
    String getCapabilitiesJson();
    void startRequest(String requestJson, IAuraBrainCallback callback);
    void cancelRequest(String requestId);
}

oneway interface IAuraBrainCallback {
    void onEvent(String requestId, String eventJson);
}
```

Callback delivery is asynchronous. Inference never runs on a Binder thread. A client must retain its callback Binder until a terminal event is received.
## Capabilities, tasks, and status

V1 capabilities are `healthCheck`, `summarizePage`, `streaming`, `cancellation`, and `localOnly`.

Only these task names are accepted:

- `healthCheck`: verifies Binder, permission, caller validation, Flutter bridge, streaming, and cancellation. It does not require a model.
- `summarizePage`: summarizes user-approved webpage text using Aura's selected local model.

Status values are `starting`, `needsSetup`, `ready`, `busy`, `unavailable`, and `error`.

```json
{
  "protocolVersion": 1,
  "status": "ready",
  "modelInstalled": true,
  "modelLoaded": false,
  "busy": false,
  "activeRequestId": null,
  "message": "A local model is installed and will load on request."
}
```

Status reflects Aura's selected model metadata/file validation and live `LLMService` state. `ready` can have `modelLoaded: false`; the model is then loaded lazily for `summarizePage`. `needsSetup` means no valid selected local model. `busy` means an external or in-process local generation owns the runtime.

## Request schema

All fields shown for `summarizePage` are required and type-checked. Text is line-ending normalized and trimmed. For `healthCheck`, `page` is omitted, but `protocolVersion`, `requestId`, `clientId`, `task`, `prompt`, and `privacy` remain required.

```json
{
  "protocolVersion": 1,
  "requestId": "unique-request-id",
  "clientId": "scope",
  "task": "summarizePage",
  "prompt": "Summarize this webpage clearly and concisely.",
  "page": {
    "title": "Page title",
    "url": "https://example.com",
    "selectedText": "",
    "visibleText": "User-approved visible page text"
  },
  "privacy": {
    "retention": "ephemeral",
    "allowMemory": false,
    "localOnly": true
  }
}
```
Privacy is invariant in V1: `retention` must be `ephemeral`, `allowMemory` must be `false`, and `localOnly` must be `true`. Any other value is rejected. A summary request must contain nonblank `selectedText` or `visibleText`. Only `http` and `https` page URLs with an authority are accepted.

Limits:

| Field | Maximum |
|---|---:|
| Serialized UTF-8 request | 131,072 bytes (128 KiB) |
| `requestId` | 200 characters |
| `clientId` | 200 characters |
| `prompt` | 4,000 characters |
| `page.title` | 500 characters |
| `page.url` | 4,096 characters |
| `page.selectedText` | 8,000 characters |
| `page.visibleText` | 32,000 characters |

Example health check:

```json
{
  "protocolVersion": 1,
  "requestId": "health-001",
  "clientId": "scope",
  "task": "healthCheck",
  "prompt": "",
  "privacy": {
    "retention": "ephemeral",
    "allowMemory": false,
    "localOnly": true
  }
}
```

## Event schema

Event types are `accepted`, `started`, `token`, `completed`, `cancelled`, and `error`. `completed`, `cancelled`, and `error` are terminal. Clients must ignore any event after the first terminal event.

```json
{
  "protocolVersion": 1,
  "requestId": "unique-request-id",
  "type": "token",
  "content": "generated token or chunk",
  "errorCode": null,
  "message": null
}
```
A successful health check streams:

```json
{"protocolVersion":1,"requestId":"health-001","type":"accepted","content":null,"errorCode":null,"message":null}
{"protocolVersion":1,"requestId":"health-001","type":"started","content":null,"errorCode":null,"message":null}
{"protocolVersion":1,"requestId":"health-001","type":"token","content":"AURA_BRAIN_CONNECTED","errorCode":null,"message":null}
{"protocolVersion":1,"requestId":"health-001","type":"completed","content":null,"errorCode":null,"message":null}
```

Calling `cancelRequest("health-001")` during the artificial health-check delay emits one `cancelled` event and releases the callback. Cancelling generation cancels the Dart stream subscription, closes the LiteRT session in its `finally` block, clears request context, and does not emit `completed` afterward.

Stable V1 error codes:

- `invalidRequest`
- `unsupportedProtocol`
- `unsupportedTask`
- `unauthorizedClient`
- `contextTooLarge`
- `needsSetup`
- `brainBusy`
- `modelUnavailable`
- `localInferenceFailed`
- `requestCancelled`
- `serviceUnavailable`
- `internalError`

Client-visible errors never contain stack traces, model paths, database details, signing material, or prompt/page content.

## Lifecycle and concurrency

The service exists only while trusted clients are bound; it is not an always-running or foreground service. It uses Aura's visual Flutter engine when available. Otherwise it starts the root-library `@pragma('vm:entry-point')` wrapper `auraBrainMain`, which delegates to a dedicated headless entrypoint that creates no `MaterialApp` and initializes no overlay, clipboard monitor, voice assistant, proactive engine, automation, device-control, notification, memory, RAG, or chat-history service. Automatic Android plugin registration is disabled for this engine; it registers only `flutter_gemma`, `large_file_handler`, `background_downloader`, `path_provider`, and `shared_preferences`, which are required for local model inference and selected-model state.

Protocol V1 allows one active external request. A second request receives `brainBusy`. LiteRT model loads are deduplicated inside an engine, generations are serialized, and a process-wide exclusive lock prevents the UI and headless engines from simultaneously loading separate native model copies. The headless engine is destroyed when the bound service ends. Callback Binder death and service unbind cancel generation and clear callback/request state.
`summarizePage` calls the existing local `LLMService.chat` stream directly with a fixed trusted summarization instruction. It does not call Aura's general orchestrator, history persistence, context builder, memory/document providers, tools, automation, or any network/cloud fallback. Request objects are released after a terminal event.

## Opening model setup

There is no prompt-bearing setup URI. Scope should launch Aura's exported activity explicitly with only this action and destination:

```kotlin
val intent = Intent().apply {
    component = ComponentName(
        "com.aura.mobile.aura_mobile",
        "com.aura.mobile.aura_mobile.MainActivity",
    )
    action = "com.aura.mobile.aura_mobile.action.OPEN_BRAIN_SETUP"
    putExtra("destination", "modelSetup")
}
startActivity(intent)
```

Aura rejects this setup action if the destination differs or if the Intent carries URI/ClipData. The action has no manifest intent filter; callers must use the explicit component. No prompt, page content, URL, or request identifier may be placed in this Intent.

## Version compatibility

Clients must call `getProtocolVersion()` before sending requests. A V1 client must not send a request when the returned version is not `1`. Aura rejects each request whose embedded `protocolVersion` is not exactly `1` with `unsupportedProtocol`. Future protocol versions must use explicit compatibility handling rather than silently changing V1 schemas or semantics.

## Connector checklist

1. Compile matching AIDL files under package `com.aura.mobile.aura_mobile.brain`.
2. Declare `com.aura.mobile.aura_mobile.permission.USE_AURA_BRAIN` in the Scope manifest.
3. Sign Scope with the same signing identity as the installed Aura build.
4. Bind using the explicit Aura service component; there is no service intent filter.
5. Query protocol, capabilities, and status.
6. Retain one callback Binder per request and handle Binder death/disconnection.
7. Treat all callbacks as asynchronous and concatenate `token` chunks in arrival order.
8. Stop on the first terminal event and release the callback.
9. Use globally unique request IDs and call `cancelRequest` when the Page Assistant is dismissed.
10. If status is `needsSetup`, launch the explicit setup Intent above without attaching page data.
