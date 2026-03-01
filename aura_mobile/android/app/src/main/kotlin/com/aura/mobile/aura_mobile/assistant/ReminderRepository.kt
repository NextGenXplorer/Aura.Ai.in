package com.aura.mobile.aura_mobile.assistant

import android.content.ContentValues
import android.content.Context

class ReminderRepository(context: Context) {
    private val dbHelper = ReminderDatabaseHelper(context)

    fun addReminder(reminder: ReminderModel): Long {
        val db = dbHelper.writableDatabase
        val values = ContentValues().apply {
            put(ReminderDatabaseHelper.COLUMN_TITLE, reminder.title)
            put(ReminderDatabaseHelper.COLUMN_DESCRIPTION, reminder.description)
            put(ReminderDatabaseHelper.COLUMN_DATETIME, reminder.eventDateTime)
            put(ReminderDatabaseHelper.COLUMN_PRE_REMINDER, if (reminder.preReminderEnabled) 1 else 0)
            put(ReminderDatabaseHelper.COLUMN_CREATED_AT, reminder.createdAt)
        }
        val id = db.insert(ReminderDatabaseHelper.TABLE_REMINDERS, null, values)
        db.close()
        return id
    }

    fun getReminderById(id: Int): ReminderModel? {
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            ReminderDatabaseHelper.TABLE_REMINDERS, null,
            "${ReminderDatabaseHelper.COLUMN_ID}=?", arrayOf(id.toString()),
            null, null, null
        )
        var reminder: ReminderModel? = null
        if (cursor != null && cursor.moveToFirst()) {
            val titleIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_TITLE)
            val descIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DESCRIPTION)
            val dtIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DATETIME)
            val preIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_PRE_REMINDER)
            val createdIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_CREATED_AT)

            reminder = ReminderModel(
                id = id,
                title = cursor.getString(titleIdx),
                description = cursor.getString(descIdx),
                eventDateTime = cursor.getLong(dtIdx),
                preReminderEnabled = cursor.getInt(preIdx) == 1,
                createdAt = cursor.getLong(createdIdx)
            )
        }
        cursor?.close()
        db.close()
        return reminder
    }

    fun getAllUpcomingReminders(): List<ReminderModel> {
        val list = mutableListOf<ReminderModel>()
        val db = dbHelper.readableDatabase
        val now = System.currentTimeMillis()
        val cursor = db.query(
            ReminderDatabaseHelper.TABLE_REMINDERS, null,
            "${ReminderDatabaseHelper.COLUMN_DATETIME} >= ?", arrayOf(now.toString()),
            null, null, "${ReminderDatabaseHelper.COLUMN_DATETIME} ASC"
        )
        
        if (cursor != null && cursor.moveToFirst()) {
            val idIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_ID)
            val titleIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_TITLE)
            val descIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DESCRIPTION)
            val dtIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DATETIME)
            val preIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_PRE_REMINDER)
            val createdIdx = cursor.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_CREATED_AT)

            do {
                list.add(
                    ReminderModel(
                        id = cursor.getInt(idIdx),
                        title = cursor.getString(titleIdx),
                        description = cursor.getString(descIdx),
                        eventDateTime = cursor.getLong(dtIdx),
                        preReminderEnabled = cursor.getInt(preIdx) == 1,
                        createdAt = cursor.getLong(createdIdx)
                    )
                )
            } while (cursor.moveToNext())
        }
        cursor?.close()
        db.close()
        return list
    }

    fun deleteReminder(id: Int) {
        val db = dbHelper.writableDatabase
        db.delete(ReminderDatabaseHelper.TABLE_REMINDERS, "${ReminderDatabaseHelper.COLUMN_ID}=?", arrayOf(id.toString()))
        db.close()
    }
}
