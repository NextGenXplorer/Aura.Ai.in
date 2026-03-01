package com.aura.mobile.aura_mobile.assistant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class ReminderDatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "AuraReminders.db"
        private const val DATABASE_VERSION = 1

        const val TABLE_REMINDERS = "reminders"
        const val COLUMN_ID = "id"
        const val COLUMN_TITLE = "title"
        const val COLUMN_DESCRIPTION = "description"
        const val COLUMN_DATETIME = "eventDateTime"
        const val COLUMN_PRE_REMINDER = "preReminderEnabled"
        const val COLUMN_CREATED_AT = "createdAt"
    }

    override fun onCreate(db: SQLiteDatabase) {
        val createTable = ("CREATE TABLE " + TABLE_REMINDERS + "("
                + COLUMN_ID + " INTEGER PRIMARY KEY AUTOINCREMENT,"
                + COLUMN_TITLE + " TEXT,"
                + COLUMN_DESCRIPTION + " TEXT,"
                + COLUMN_DATETIME + " INTEGER,"
                + COLUMN_PRE_REMINDER + " INTEGER,"
                + COLUMN_CREATED_AT + " INTEGER" + ")")
        db.execSQL(createTable)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS " + TABLE_REMINDERS)
        onCreate(db)
    }
}
