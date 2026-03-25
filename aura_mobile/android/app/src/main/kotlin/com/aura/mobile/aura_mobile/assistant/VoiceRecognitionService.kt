package com.aura.mobile.aura_mobile.assistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

class VoiceRecognitionService(
    private val context: Context,
    private val onResult: (String) -> Unit,
    private val onPartialResult: ((String) -> Unit)? = null,
    private val onError: (String) -> Unit,
    private val onTimeout: () -> Unit
) {

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening = false
    private val handler = Handler(Looper.getMainLooper())
    private val stopListeningRunnable = Runnable { stopListening() }

    init {
        initRecognizer()
    }

    private fun initRecognizer() {
        if (SpeechRecognizer.isRecognitionAvailable(context)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                
                override fun onBeginningOfSpeech() {
                    // Cancel the initial "no speech detected" timeout.
                    // We let the Android SpeechRecognizer's internal silence timeouts handle the stop.
                    handler.removeCallbacks(stopListeningRunnable)
                }

                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    isListening = false
                }

                override fun onError(error: Int) {
                    isListening = false
                    android.util.Log.d("VoiceRecognition", "Error code: $error")

                    // Handle specific errors differently for better UX
                    when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                            // User didn't say anything or too quiet - just retry
                            onTimeout()
                        }

                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> {
                            // Network issue - inform user but still retry
                            onError("network")
                        }

                        SpeechRecognizer.ERROR_AUDIO -> {
                            // Microphone problem - serious issue
                            onError("microphone")
                        }

                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                            // Permission denied - critical
                            onError("permission")
                        }

                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                            // Service busy - retry should work
                            onTimeout()
                        }

                        SpeechRecognizer.ERROR_SERVER -> {
                            // Google's server issue - retry
                            onError("server")
                        }

                        else -> {
                            // Unknown error - retry anyway
                            onTimeout()
                        }
                    }
                }

                override fun onResults(results: Bundle?) {
                    isListening = false
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (!matches.isNullOrEmpty()) {
                        onResult(matches[0])
                    } else {
                        onError("No results")
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (!matches.isNullOrEmpty()) {
                        onPartialResult?.invoke(matches[0])
                    }
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        } else {
            onError("Speech Recognition not available")
        }
    }

    fun startListening() {
        if (!isListening) {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3) // Get top 3 results for better accuracy
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)

                // ═══ IMPROVED TIMEOUTS FOR BETTER USER EXPERIENCE ═══

                // Complete silence: 10 seconds (was 5s - TOO SHORT!)
                // User can pause to think without being cut off
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 10000L)

                // Possibly complete silence: 8 seconds (was 5s)
                // More patient with natural pauses
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 8000L)

                // Minimum listening duration: 30 seconds (was 15s)
                // Allow longer, more complex requests
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 30000L)

                // Prefer on-device recognition when available (faster, more private)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)

                // Get confidence scores to filter out uncertain results
                putExtra(RecognizerIntent.EXTRA_CONFIDENCE_SCORES, true)
            }
            try {
                speechRecognizer?.startListening(intent)
                isListening = true

                // Auto stop after 20 seconds if absolutely no speech detected
                // (was 8s - TOO IMPATIENT!)
                // This only triggers if user says NOTHING at all
                handler.removeCallbacks(stopListeningRunnable)
                handler.postDelayed(stopListeningRunnable, 20000)
            } catch (e: Exception) {
                onError("Failed to start listening: ${e.message}")
            }
        }
    }

    fun stopListening() {
        if (isListening) {
            try {
                speechRecognizer?.stopListening()
            } catch (ignore: Exception) {}
            isListening = false
        }
    }

    fun destroy() {
        handler.removeCallbacks(stopListeningRunnable)
        try {
            speechRecognizer?.destroy()
        } catch (ignore: Exception) {}
    }
}
