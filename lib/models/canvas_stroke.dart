import 'dart:ui';

class CanvasStroke {
  final String strokeId;
  final String fromPeerId;
  final int colorValue;
  final double width;
  final List<Offset> points;

  const CanvasStroke({
    required this.strokeId,
    required this.fromPeerId,
    required this.colorValue,
    required this.width,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
    'strokeId': strokeId,
    'fromPeerId': fromPeerId,
    'color': colorValue,
    'width': width,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
  };

  static CanvasStroke? tryFromJson(Map<String, dynamic> json) {
    try {
      final id = (json['strokeId'] as String?)?.trim();
      final fromPeerId = (json['fromPeerId'] as String?)?.trim();
      final color = json['color'];
      final width = json['width'];
      final pts = json['points'];
      if (id == null || id.isEmpty) return null;
      if (fromPeerId == null || fromPeerId.isEmpty) return null;
      if (color is! int) return null;
      final w = (width is num) ? width.toDouble() : 3.0;
      if (pts is! List) return null;
      final out = <Offset>[];
      for (final e in pts) {
        if (e is List && e.length == 2) {
          final dx = e[0];
          final dy = e[1];
          if (dx is num && dy is num) {
            out.add(Offset(dx.toDouble(), dy.toDouble()));
          }
        }
      }
      if (out.isEmpty) return null;
      return CanvasStroke(
        strokeId: id,
        fromPeerId: fromPeerId,
        colorValue: color,
        width: w,
        points: out,
      );
    } catch (_) {
      return null;
    }
  }
}