// lib/shared/models/daily_step_entry.dart

class DailyStepEntry {
  final DateTime date; // sin componente de hora, fecha local
  final int steps;

  const DailyStepEntry({required this.date, required this.steps});
}
