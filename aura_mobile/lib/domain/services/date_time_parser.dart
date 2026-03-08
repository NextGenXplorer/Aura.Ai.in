import 'package:flutter/material.dart';

class DateTimeParser {
  /// Parses natural language date/time from text
  /// Returns a map with 'date' and 'time' keys if found
  Map<String, dynamic> parse(String text) {
    final lowerText = text.toLowerCase();
    DateTime? eventDate;
    TimeOfDay? eventTime;

    // Extract Date
    eventDate = _extractDate(lowerText);

    // Extract Time
    eventTime = _extractTime(lowerText);

    return {
      'date': eventDate,
      'time': eventTime,
    };
  }

  /// Parses text for a specific reminder `DateTime`, handling relative times ("in 5 minutes")
  /// and intelligent date/time merging (e.g. rolling over to tomorrow if time has passed).
  DateTime? parseReminderTime(String text) {
    final lowerText = text.toLowerCase();
    final now = DateTime.now();
    
    // 1. Check relative time (in X minutes/hours/days)
    final minMatch = RegExp(r'in\s+(\d+)\s*(min|minute|minutes)\b').firstMatch(lowerText);
    final hrMatch = RegExp(r'in\s+(\d+)\s*(hr|hour|hours)\b').firstMatch(lowerText);
    final dayMatch = RegExp(r'in\s+(\d+)\s*(day|days)\b').firstMatch(lowerText);
    
    if (minMatch != null) {
      return now.add(Duration(minutes: int.parse(minMatch.group(1)!)));
    } else if (hrMatch != null) {
      return now.add(Duration(hours: int.parse(hrMatch.group(1)!)));
    } else if (dayMatch != null) {
      return now.add(Duration(days: int.parse(dayMatch.group(1)!)));
    }

    // 2. Exact Time & Date parsing
    final parsed = parse(text);
    final eventDate = parsed['date'] as DateTime?;
    final eventTime = parsed['time'] as TimeOfDay?;
    
    if (eventDate == null && eventTime == null) {
      return null;
    }
    
    var finalDate = eventDate ?? DateTime(now.year, now.month, now.day);
    var finalHour = eventTime?.hour ?? 9; // Default 9 AM if no time specified
    var finalMinute = eventTime?.minute ?? 0;
    
    var scheduledTime = DateTime(finalDate.year, finalDate.month, finalDate.day, finalHour, finalMinute);
    
    // If only time was specified and it has already passed today, assume tomorrow
    if (eventDate == null && eventTime != null && scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    
    return scheduledTime;
  }

  DateTime? _extractDate(String text) {
    final now = DateTime.now();

    // Tomorrow
    if (text.contains('tomorrow')) {
      return DateTime(now.year, now.month, now.day + 1);
    }

    // Today
    if (text.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }

    // Next Monday, Tuesday, etc.
    final weekdayMatch = RegExp(r'next (monday|tuesday|wednesday|thursday|friday|saturday|sunday)').firstMatch(text);
    if (weekdayMatch != null) {
      return _getNextWeekday(weekdayMatch.group(1)!);
    }

    // Specific date: "March 20", "20 March", "20/3", "3/20"
    final monthDayMatch = RegExp(r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})').firstMatch(text);
    if (monthDayMatch != null) {
      final month = _monthNameToNumber(monthDayMatch.group(1)!);
      final day = int.parse(monthDayMatch.group(2)!);
      return DateTime(now.year, month, day);
    }

    // Day Month format: "20 March"
    final dayMonthMatch = RegExp(r'(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december)').firstMatch(text);
    if (dayMonthMatch != null) {
      final day = int.parse(dayMonthMatch.group(1)!);
      final month = _monthNameToNumber(dayMonthMatch.group(2)!);
      return DateTime(now.year, month, day);
    }

    // Slash format: "20/3" or "3/20"
    final slashMatch = RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(text);
    if (slashMatch != null) {
      final first = int.parse(slashMatch.group(1)!);
      final second = int.parse(slashMatch.group(2)!);
      // Assume day/month if first > 12, else month/day
      if (first > 12) {
        return DateTime(now.year, second, first);
      } else {
        return DateTime(now.year, first, second);
      }
    }

    return null;
  }

  TimeOfDay? _extractTime(String text) {
    // 10 AM, 3 PM, 10:30 AM, etc.
    final timeMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', caseSensitive: false).firstMatch(text);
    if (timeMatch != null) {
      int hour = int.parse(timeMatch.group(1)!);
      final minute = timeMatch.group(2) != null ? int.parse(timeMatch.group(2)!) : 0;
      final period = timeMatch.group(3)!.toLowerCase();

      if (period == 'pm' && hour != 12) {
        hour += 12;
      } else if (period == 'am' && hour == 12) {
        hour = 0;
      }

      return TimeOfDay(hour: hour, minute: minute);
    }

    // 24-hour format: "14:30", "09:00"
    final time24Match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    if (time24Match != null) {
      final hour = int.parse(time24Match.group(1)!);
      final minute = int.parse(time24Match.group(2)!);
      if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }

    return null;
  }

  DateTime _getNextWeekday(String weekday) {
    final now = DateTime.now();
    final targetWeekday = _weekdayNameToNumber(weekday);
    int daysUntilTarget = (targetWeekday - now.weekday + 7) % 7;
    if (daysUntilTarget == 0) daysUntilTarget = 7; // Next week, not today
    return now.add(Duration(days: daysUntilTarget));
  }

  int _weekdayNameToNumber(String name) {
    const weekdays = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    return weekdays[name.toLowerCase()] ?? 1;
  }

  int _monthNameToNumber(String name) {
    const months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };
    return months[name.toLowerCase()] ?? 1;
  }
}
