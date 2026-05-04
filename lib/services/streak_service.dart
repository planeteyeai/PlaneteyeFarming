import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STREAK SERVICE
//  Tracks how many consecutive days the farmer has opened the app.
//
//  Rules:
//   • Open on day N   → if last open was day N-1, streak++; if day N, no-op;
//                        if older, streak resets to 1.
//   • First ever open → streak = 1.
//   • Persisted in SharedPreferences so it survives app restarts.
// ═══════════════════════════════════════════════════════════════════════════

class StreakService {
  static const _kStreak     = 'streak_count';
  static const _kLastDate   = 'streak_last_date';    // 'yyyy-MM-dd'
  static const _kLongest    = 'streak_longest';

  // ── Singleton ────────────────────────────────────────────────────────────
  StreakService._();
  static final StreakService instance = StreakService._();

  // ── In-memory cache (set on first load) ──────────────────────────────────
  int _streak  = 0;
  int _longest = 0;
  bool _loaded = false;

  int get currentStreak => _streak;
  int get longestStreak  => _longest;

  // Whether this open is a NEW day (streak just ticked up or reset).
  // Used by the UI to decide whether to show the streak toast.
  bool _isNewDayOpen = false;
  bool get isNewDayOpen => _isNewDayOpen;

  // ── Load persisted values without recording today ─────────────────────────
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _streak  = prefs.getInt(_kStreak)  ?? 0;
    _longest = prefs.getInt(_kLongest) ?? 0;
    _loaded  = true;
  }

  // ── Record today's open and update the streak ─────────────────────────────
  Future<void> recordOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final today     = _dateKey(DateTime.now());
    final lastDate  = prefs.getString(_kLastDate) ?? '';

    _isNewDayOpen = false;

    if (lastDate == today) {
      // Already recorded today — just cache and return.
      _streak  = prefs.getInt(_kStreak)  ?? 1;
      _longest = prefs.getInt(_kLongest) ?? _streak;
      _loaded  = true;
      return;
    }

    _isNewDayOpen = true;

    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));

    if (lastDate == yesterday) {
      // Consecutive day → increment.
      _streak = (prefs.getInt(_kStreak) ?? 0) + 1;
    } else {
      // Gap of ≥1 day → reset.
      _streak = 1;
    }

    if (_streak > _longest) _longest = _streak;

    await prefs.setInt(_kStreak,   _streak);
    await prefs.setInt(_kLongest,  _longest);
    await prefs.setString(_kLastDate, today);
    _loaded = true;
  }

  // ── Days since last open (0 = today, 1 = yesterday, …) ───────────────────
  Future<int> daysSinceLastOpen() async {
    final prefs    = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_kLastDate);
    if (lastDate == null || lastDate.isEmpty) return 999;
    final last = DateTime.tryParse(lastDate);
    if (last == null) return 999;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
  }

  // ── Reminder messages (used by notification / in-app alert) ──────────────
  /// Returns a reminder message appropriate to how many days the user has
  /// missed, or null if the user opened the app today (no reminder needed).
  Future<String?> reminderMessage() async {
    final days = await daysSinceLastOpen();
    if (days == 0) return null; // opened today — no reminder
    return _reminderFor(days, _streak);
  }

  static String _reminderFor(int daysMissed, int currentStreak) {
    // Rotate through 5 messages based on daysMissed so repeated alerts
    // feel fresh.  Streak context makes each one personal.
    final List<String> messages;

    if (daysMissed == 1) {
      messages = [
        '🌿 Your farm misses you! Come check on your crops before the day ends.',
        '🔥 Don\'t break your streak! Open CropEye today to keep it alive.',
        '🌾 Your fields are waiting. One tap keeps your ${currentStreak}-day streak going!',
        '👀 Quick check on your farm? Your streak resets at midnight!',
        '🚜 Your crops are growing — are you watching? Check in now!',
      ];
    } else if (daysMissed == 2) {
      messages = [
        '😟 You\'ve missed 2 days! Your streak is gone, but you can start fresh today.',
        '🌱 A new streak starts with one visit. Your farm needs you — open CropEye!',
        '🌧️ 2 days away from your fields? Come back and build that streak again!',
        '🪴 Crops don\'t wait. Your streak reset — let\'s build a new one today!',
        '📉 2-day absence detected. Jump back in — your fields are depending on you!',
      ];
    } else if (daysMissed <= 5) {
      messages = [
        '😬 $daysMissed days away! Your farm could be struggling — come check the crop health.',
        '🔴 Streak broken for $daysMissed days. Start fresh — one visit today resets the clock!',
        '🌿 Your crops haven\'t been checked in $daysMissed days. Time to get back in the field!',
        '⚠️ $daysMissed-day gap detected! A true farmer never stays away this long.',
        '🌾 Build your comeback streak! $daysMissed days gone — one open = Day 1!',
      ];
    } else {
      messages = [
        '🚨 $daysMissed days since your last visit! Your farm needs attention — open CropEye now.',
        '😮 Wow, $daysMissed days away? Your crops can\'t wait any longer. Come back!',
        '🌾 $daysMissed days missed! A lot can change on a farm. Check in before it\'s too late.',
        '⚡ Big comeback time! $daysMissed days away — open CropEye and start a new streak!',
        '🌱 The farm never sleeps. $daysMissed days have passed — your crops need a check-up!',
      ];
    }

    return messages[daysMissed % messages.length];
  }

  // ── Streak emoji (fun visual for UI) ─────────────────────────────────────
  static String streakEmoji(int streak) {
    if (streak >= 365) return '🏆';
    if (streak >= 100) return '💎';
    if (streak >= 30)  return '🌟';
    if (streak >= 14)  return '🔥';
    if (streak >= 7)   return '⚡';
    if (streak >= 3)   return '🌿';
    if (streak >= 1)   return '🌱';
    return '💤';
  }

  // ── Streak label ─────────────────────────────────────────────────────────
  static String streakLabel(int streak) {
    if (streak >= 365) return 'Legend';
    if (streak >= 100) return 'Diamond';
    if (streak >= 30)  return 'On Fire';
    if (streak >= 14)  return 'Hot Streak';
    if (streak >= 7)   return 'Weekly Pro';
    if (streak >= 3)   return 'Building';
    if (streak >= 1)   return 'Started';
    return 'No Streak';
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
