import 'dart:async';

import 'package:flutter/material.dart';

class RotatingWidget extends StatefulWidget {
  final Duration duration;
  final bool spinning;
  final bool reverse;
  final Widget child;

  const RotatingWidget({
    required this.duration,
    this.spinning = true,
    this.reverse = false,
    required this.child,
    super.key,
  });

  @override
  State<RotatingWidget> createState() => RotatingWidgetState();
}

class RotatingWidgetState extends State<RotatingWidget> with WidgetsBindingObserver {
  static const _fps = 30;
  static const _tickDuration = 1000 ~/ _fps; // in milliseconds
  static const _maxRadians = 6.28; // 360 degrees in radians
  double _angle = 0; // in radians
  double _anglePerTick = 0;
  Timer? _timer;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateAnglePerTick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode is disabled while the app is hidden in the tray (see _TickerModeWatcher in main.dart).
    // Reading it here registers a dependency, so this method runs again when the mode changes.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant RotatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration || oldWidget.reverse != widget.reverse) {
      _updateAnglePerTick();
    }
    if (oldWidget.spinning != widget.spinning) {
      _syncTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Frames are not scheduled while the window is hidden, so the TickerMode change might not
        // reach this widget in time. Stop the timer immediately instead of keeping it at 30 fps.
        _cancelTimer();
        break;
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        _syncTimer();
        break;
    }
  }

  void _updateAnglePerTick() {
    _anglePerTick = _maxRadians / (widget.duration.inMilliseconds / _tickDuration);
    if (widget.reverse) {
      _anglePerTick = -_anglePerTick;
    }
  }

  void _syncTimer() {
    if (!mounted || !widget.spinning || !_tickerEnabled) {
      _cancelTimer();
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: _tickDuration), (_) {
      setState(() {
        _angle = (_angle + _anglePerTick) % _maxRadians;
      });
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _angle,
      child: widget.child,
    );
  }
}
