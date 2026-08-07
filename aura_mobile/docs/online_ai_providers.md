# Aura online AI providers

Last reviewed: 2026-07-25

Aura supports two explicit chat backends:

1. **Offline LiteRT** — existing downloaded `.task`, `.litertlm`, and `.tflite` models. Prompts remain on-device.
2. **Online OpenAI-compatible APIs** — OpenRouter, Groq, or NVIDIA NIM using a key supplied by the user.

Aura never silently falls back from offline to online. Selecting an online model is an explicit privacy decision. The existing Aura orchestrator, persona, conversation context, document context, memory policy, automation detection, streaming UI, voice flow, and tool-dispatch logic continue to use the common `LLMService` interface.

## Security and privacy

API keys are stored by `flutter_secure_storage`, backed by Android Keystore and Apple Keychain where supported. Keys are not placed in SharedPreferences, source code, logs, request diagnostics, or chat history. A rooted or otherwise compromised device can still defeat client-side protections.

When an online model is active, the provider receives the current user prompt and the system context assembled by Aura. That context can include recent conversation, an active persona, memories, or document excerpts when the user enabled those Aura features. Provider terms and retention policies apply. Aura Brain Protocol V1 remains LiteRT-only and never uses these online providers. Aura retains a separate last-local model record for Brain, so selecting an online chat model cannot redirect Brain to the network or make an installed local model appear unconfigured.

Do not ship developer-owned production keys inside the app. For a public app, use user-owned keys as implemented here or place provider credentials behind a server-side gateway with authentication, quotas, abuse controls, and key rotation.

## Supported providers

| Provider | Base URL | Model discovery | Notes |
|---|---|---|---|
| OpenRouter | `https://openrouter.ai/api/v1` | `GET /models` | Models ending in `:free` are explicitly shown as free, but quotas and availability change. |
| Groq | `https://api.groq.com/openai/v1` | `GET /models` | Developer free-tier rate limits are model/account-specific. |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` | `GET /models` | Hosted evaluation access and credits can change. |

All three use bearer authentication and OpenAI-compatible `POST /chat/completions` streaming. Aura frames complete SSE events (including multi-line `data:` fields), handles provider error events and HTTP-200 error payloads, and requires both response content and a recognized `[DONE]` or `finish_reason` completion. Authentication failures, rate limits, timeouts, unavailable models, malformed/incomplete streams, and cancellation are mapped to safe user-facing errors. A user cancellation is terminal and is never automatically retried.

Official references:

- OpenRouter models API: <https://openrouter.ai/docs/api-reference/list-available-models>
- OpenRouter free router: <https://openrouter.ai/docs/guides/routing/routers/free>
- OpenRouter keys: <https://openrouter.ai/keys>
- Groq models: <https://console.groq.com/docs/models>
- Groq rate limits: <https://console.groq.com/docs/rate-limits>
- Groq keys: <https://console.groq.com/keys>
- NVIDIA NIM LLM API: <https://docs.api.nvidia.com/nim/reference/llm-apis>
- NVIDIA API catalog: <https://build.nvidia.com/>

## Model selection

The settings screen always reads the provider's live model catalog rather than relying on a frozen list. This matters because free models are frequently renamed, removed, repriced, or rate-limited.

Aura filters the live catalog to text-chat-capable entries before sorting. Embedding, reranking, moderation/safety, speech/audio, transcription, and image-generation specialists are not selectable through the chat adapter. Unknown capabilities default to unsupported: the vision badge appears only when provider metadata explicitly advertises image input. Online tool calling remains disabled until Aura's OpenAI-compatible adapter sends native tool schemas and consumes native tool-call deltas; provider catalog claims alone never enable executable tool handling.

Aura then sorts eligible models with a transparent recommendation score:

- larger context windows score higher;
- explicitly zero-cost/OpenRouter `:free` models receive a bonus;
- confirmed vision capability receives a smaller bonus;
- larger general-purpose instruct models receive a quality bonus.

The score is a convenience, not a factual benchmark. For OpenRouter, **Free only** is enabled initially. Groq and NVIDIA models are not labelled permanently free because access depends on the current account program and rate limits.

Recommended selection strategy:

- **Best privacy/no network:** keep a downloaded LiteRT model active.
- **General free online chat:** choose the first suitable OpenRouter `:free` instruct model, avoiding safety/embedding specialists.
- **Lowest latency:** use a Groq-hosted general-purpose instruct model that appears in the account catalog.
- **NVIDIA ecosystem/model evaluation:** choose a general-purpose instruct NIM exposed to the account.
- **Images:** choose a catalog entry marked Vision; otherwise Aura rejects image upload before sending it.
- **Aura device tools:** deterministic/rule-based Aura automation remains available, but online model-emitted native tool calls are disabled until the adapter implements provider tool schemas and deltas.

Before production release, evaluate selected models using Aura-specific prompts for conversation, summarization, document grounding, latency, output quality, and provider quota behavior. If native online tool calling is added later, separately evaluate schema compliance and argument validation. Do not call one model universally “best”; availability, cost, privacy, language, and latency requirements differ.

## User workflow

1. Open **Model Manager → Configure** or drawer **Online AI Providers**.
2. Choose OpenRouter, Groq, or NVIDIA NIM.
3. Tap **Get key**, create a provider key, return to Aura, and paste it.
4. Tap **Save & load models**. Aura validates a newly entered candidate key through the provider model endpoint before replacing any previously saved key.
5. Review the filtered live chat-model list and tap **Use**.
6. Chat normally. Aura's existing workflow now streams through that online model.
7. Return to Model Manager and select any downloaded local model to go offline again. Local files are never deleted by an online switch, and Aura does not forcibly unload LiteRT during that transition because Aura Brain may be using the local runtime.
8. Use the stop button during online generation to cancel the HTTP stream.

Deleting the active provider key clears that online selection and restores the retained local selection when it is still usable. It does not delete offline model files. Active backend, local identity/path, and online identity are persisted in one versioned selection snapshot; legacy preference keys are mirrored only for compatibility.

## Implementation map

- `ProviderApiKeyStore`: secure key CRUD.
- `LLMSelectionStore`: versioned, atomic active/local/online selection snapshot plus legacy-key migration.
- `OpenAICompatibleLLMService`: filtered model discovery, multimodal requests, framed SSE streaming, provider errors, cancellation.
- `LLMRouter`: explicit backend selection and atomic persistence; delegates the stable `LLMService` API.
- `ModelSelectorNotifier`: restores local or online selection and retains existing local download behavior.
- `OnlineProviderSettingsScreen`: candidate-key validation, secure key management, live chat catalog, recommendation display, selection.
- `ChatNotifier`: same orchestrator flow plus token-scoped cancellation without hidden retry.

Adding another OpenAI-compatible provider requires a reviewed provider enum entry with its HTTPS base URL/key page and confirmation that its `/models` and `/chat/completions` schemas match the adapter. Providers with incompatible authentication, streaming, or message formats should receive a separate adapter rather than provider-specific conditionals scattered through Aura.
