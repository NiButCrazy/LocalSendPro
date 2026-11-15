import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('WindowTitleBar');

const double kWindowTitleBarHeight = 32;

/// Reads the setting and delegates to the pure layout widget.
class WindowTitleBarWrapper extends StatelessWidget {
  final Widget child;

  const WindowTitleBarWrapper({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final framelessWindow = context.ref.watch(settingsProvider.select((settings) => settings.framelessWindow));
    return WindowTitleBarArea(
      framelessWindow: framelessWindow,
      child: child,
    );
  }
}

/// Keeps the Navigator at the same position in the tree while the bar toggles.
class WindowTitleBarArea extends StatelessWidget {
  final bool framelessWindow;
  final Widget child;

  const WindowTitleBarArea({
    required this.framelessWindow,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!checkPlatformSupportsFramelessWindow()) {
      return child;
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        // The placeholder keeps this list at two children. Returning `child`
        // directly when disabled would move the Navigator and remount it.
        if (framelessWindow) const WindowTitleBar() else const SizedBox.shrink(),
        Expanded(
          key: const ValueKey('window-title-bar-content'),
          // Keep this wrapper stable across toggles so the Navigator is not remounted.
          child: ColoredBox(
            color: framelessWindow ? theme.cardColorWithElevation : Colors.transparent,
            child: ClipRRect(
              borderRadius: framelessWindow ? const BorderRadius.vertical(top: Radius.circular(12)) : BorderRadius.zero,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_refreshMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      if (mounted && isMaximized != _isMaximized) {
        setState(() => _isMaximized = isMaximized);
      }
    } catch (e) {
      _logger.warning('Failed to read the maximize state', e);
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  @override
  void onWindowRestore() {
    unawaited(_refreshMaximized());
  }

  Future<void> _minimize() async {
    try {
      await windowManager.minimize();
    } catch (e) {
      _logger.warning('Failed to minimize the window', e);
    }
  }

  Future<void> _toggleMaximize() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      if (isMaximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (e) {
      _logger.warning('Failed to toggle the maximize state', e);
    }
  }

  Future<void> _close() async {
    try {
      // Goes through the native WM_CLOSE path so WindowWatcher.onWindowClose
      // can apply minimizeToTray / backgroundMode. Never call exit(0) here.
      await windowManager.close();
    } catch (e) {
      _logger.warning('Failed to close the window', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    return Material(
      // Matches the NavigationRail background so the rail looks continuous.
      // Without the rail (narrow layout) fall back to the page background.
      color: isNarrow ? theme.scaffoldBackgroundColor : theme.cardColorWithElevation,
      child: SizedBox(
        height: kWindowTitleBarHeight,
        child: Row(
          // Windows caption buttons stay on the right even in RTL locales.
          textDirection: TextDirection.ltr,
          children: [
            const Expanded(
              child: DragToMoveArea(
                child: SizedBox.expand(),
              ),
            ),
            _WindowTitleBarButton(
              icon: Icons.remove,
              onPressed: () => unawaited(_minimize()),
            ),
            _WindowTitleBarButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              onPressed: () => unawaited(_toggleMaximize()),
            ),
            _WindowTitleBarButton(
              icon: Icons.close,
              isCloseButton: true,
              onPressed: () => unawaited(_close()),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowTitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isCloseButton;

  const _WindowTitleBarButton({
    required this.icon,
    required this.onPressed,
    this.isCloseButton = false,
  });

  @override
  State<_WindowTitleBarButton> createState() => _WindowTitleBarButtonState();
}

class _WindowTitleBarButtonState extends State<_WindowTitleBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hoverColor = widget.isCloseButton
        ? const Color(0xffC42B1C) // Windows close-button red
        : colorScheme.onSurface.withValues(alpha: 0.08);
    final iconColor = widget.isCloseButton && _hovered ? Colors.white : colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: kWindowTitleBarHeight,
          color: _hovered ? hoverColor : Colors.transparent,
          child: Icon(widget.icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
