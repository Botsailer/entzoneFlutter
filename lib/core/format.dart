// Formatting, in the product's own voice: lowercase, compact, and never
// padded with words the user does not need.

/// "1:24:18" or "24:18".
String formatTime(num seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = s ~/ 3600;
  final m = (s ~/ 60) % 60;
  final sec = s % 60;
  two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// "2h 14m" · "47m". Used for a runtime, never for a countdown.
String formatDuration(num? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = ((total % 3600) / 60).round();
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// "1h 25m left" · "25m left" · "under a minute left".
String formatLeft(num seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds : 0;
  if (s < 60) return 'under a minute left';
  final h = s ~/ 3600;
  final m = ((s % 3600) / 60).round();
  return h > 0 ? '${h}h ${m}m left' : '${m}m left';
}

/// "1.4 gb" · "740 mb" · "12 kb".
String formatBytes(num? bytes) {
  final b = bytes ?? 0;
  if (b <= 0) return '—';
  if (b < 1024) return '$b b';
  if (b < 1024 * 1024) return '${(b / 1024).round()} kb';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).round()} mb';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} gb';
}

/// "2.4 mb/s".
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '';
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).round()} kb/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} mb/s';
}

/// "4m" · "1h 12m" · "2d". A countdown, so it stays short.
String formatEta(Duration? d) {
  if (d == null) return '';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d';
}

/// "just now" · "12m ago" · "3d ago" · a date.
String timeAgo(int ms) {
  final s = ((DateTime.now().millisecondsSinceEpoch - ms) / 1000).clamp(0, double.infinity);
  if (s < 60) return 'just now';
  if (s < 3600) return '${(s / 60).floor()}m ago';
  if (s < 86400) return '${(s / 3600).floor()}h ago';
  if (s < 7 * 86400) return '${(s / 86400).floor()}d ago';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day}/${d.month}/${d.year}';
}

/// Join metadata with the world's own separator.
String meta(List<String?> parts) =>
    parts.where((p) => p != null && p.isNotEmpty).join('  ·  ');
