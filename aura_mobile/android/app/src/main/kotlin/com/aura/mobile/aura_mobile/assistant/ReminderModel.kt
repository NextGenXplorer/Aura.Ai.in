package com.aura.mobile.aura_mobile.assistant

data class ReminderModel(
    val id: Int = 0,
    val title: String,
    val description: String = "",
    val eventDateTime: Long,
    val preReminderEnabled: Boolean = false,
    val createdAt: Long = System.currentTimeMillis()
)
