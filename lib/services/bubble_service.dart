import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

class BubbleState {
  final String bubbleId;
  final Position center;

  BubbleState({required this.bubbleId, required this.center});
}

class BubbleService {
  final double radiusM;

  BubbleService({required this.radiusM});

  BubbleState? _state;
  BubbleState? get state => _state;

  StreamSubscription<Position>? _sub;

  /// Creates a new bubble centered on the best available position.
  /// Works on Android/iOS/Desktop/Web.
  Future<BubbleState> createBubble() async {
    // 1) Ensure services ON (Web returns false if browser location is blocked)
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are OFF (or blocked in browser).');
    }

    // 2) Ensure permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied forever. Enable it in settings.');
    }

    // Helper to create/return state
    BubbleState done(Position pos) {
      _state = BubbleState(bubbleId: const Uuid().v4(), center: pos);
      return _state!;
    }

    // 3) Best-effort: last known first (NOT supported on web)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return done(last);
    } on UnsupportedError {
      // Web: getLastKnownPosition is not supported -> ignore
    } catch (_) {
      // Ignore any other platform-specific failures
    }

    // 4) Try current position (bounded)
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      return done(pos);
    } on TimeoutException {
      // fall through to stream fallback
    } catch (_) {
      // fall through to stream fallback
    }

    // 5) Final fallback: listen briefly to the stream (bounded)
    try {
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      final pos = await Geolocator.getPositionStream(locationSettings: settings)
          .first
          .timeout(const Duration(seconds: 8));

      return done(pos);
    } on TimeoutException {
      throw TimeoutException(
        'Timed out creating bubble (GPS). '
            'On mobile: go outside / enable High accuracy / disable battery saver. '
            'On web: allow Location permission in the browser and reload.',
      );
    }
  }

  /// Start monitoring distance from the bubble center.
  Future<void> startMonitoring({
    required void Function(Position pos, double distM) onUpdate,
    required Future<void> Function(Position pos, double distM) onExit,
  }) async {
    final st = _state;
    if (st == null) throw Exception('No bubble. Call createBubble() first.');

    await _sub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (pos) async {
        final dist = Geolocator.distanceBetween(
          st.center.latitude,
          st.center.longitude,
          pos.latitude,
          pos.longitude,
        );

        onUpdate(pos, dist);

        if (dist > radiusM) {
          await onExit(pos, dist);
        }
      },
      onError: (e) {
        // If the stream errors (browser blocked / sensor off), don't crash.
        // You can optionally surface a snack from caller, but we keep service silent.
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _state = null;
  }
}