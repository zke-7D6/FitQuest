class NotificationService {
  static Future<void> init() async {}
  static Future<void> scheduleAllReminders() async {}

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}

  static Future<void> questAccepted(String questName) async {}
  static Future<void> questCompleted(String questName, int xp) async {}
  static Future<void> stepGoalReached(int steps) async {}
  static Future<void> highActivityWarning(int steps) async {}
  static Future<void> extremeActivityWarning(int steps) async {}
  static Future<void> cancelAll() async {}
}