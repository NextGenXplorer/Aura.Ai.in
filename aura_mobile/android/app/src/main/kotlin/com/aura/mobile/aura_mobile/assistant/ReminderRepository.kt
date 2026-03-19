package com.aura.mobile.aura_mobile.assistant

import android.content.ContentValues
import android.content.Context

/**
 * Repository for reading/writing reminders to SQLite.
 *
 * NOTE: We intentionally do NOT call db.close() here.
 * SQLiteOpenHelper manages the connection lifecycle. Manually closing
 * after each operation causes "attempt to reopen an already-closed object"
 * crashes on concurrent reads/writes from BootReceiver + Service.
 */
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
        return db.insert(ReminderDatabaseHelper.TABLE_REMINDERS, null, values)
    }

    fun getReminderById(id: Int): ReminderModel? {
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            ReminderDatabaseHelper.TABLE_REMINDERS, null,
            "${ReminderDatabaseHelper.COLUMN_ID}=?", arrayOf(id.toString()),
            null, null, null
        )
        var reminder: ReminderModel? = null
        cursor?.use {
            if (it.moveToFirst()) {
                reminder = ReminderModel(
                    id = id,
                    title = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_TITLE)),
                    description = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DESCRIPTION)),
                    eventDateTime = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DATETIME)),
                    preReminderEnabled = it.getInt(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_PRE_REMINDER)) == 1,
                    createdAt = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_CREATED_AT))
                )
            }
        }
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
        cursor?.use {
            while (it.moveToNext()) {
                list.add(
                    ReminderModel(
                        id = it.getInt(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_ID)),
                        title = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_TITLE)),
                        description = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DESCRIPTION)),
                        eventDateTime = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DATETIME)),
                        preReminderEnabled = it.getInt(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_PRE_REMINDER)) == 1,
                        createdAt = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_CREATED_AT))
                    )
                )
            }
        }
        return list
    }

    fun deleteReminder(id: Int) {
        val db = dbHelper.writableDatabase
        db.delete(ReminderDatabaseHelper.TABLE_REMINDERS, "${ReminderDatabaseHelper.COLUMN_ID}=?", arrayOf(id.toString()))
    }

    fun getAllReminders(): List<ReminderModel> {
        val list = mutableListOf<ReminderModel>()
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            ReminderDatabaseHelper.TABLE_REMINDERS, null,
            null, null, null, null,
            "${ReminderDatabaseHelper.COLUMN_DATETIME} ASC"
        )
        cursor?.use {
            while (it.moveToNext()) {
                list.add(
                    ReminderModel(
                        id = it.getInt(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_ID)),
                        title = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_TITLE)),
                        description = it.getString(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DESCRIPTION)),
                        eventDateTime = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_DATETIME)),
                        preReminderEnabled = it.getInt(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_PRE_REMINDER)) == 1,
                        createdAt = it.getLong(it.getColumnIndexOrThrow(ReminderDatabaseHelper.COLUMN_CREATED_AT))
                    )
                )
            }
        }
        return list
    }
}
