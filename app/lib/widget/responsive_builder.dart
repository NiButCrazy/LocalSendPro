import 'package:flutter/material.dart';

/// Width below which the layout switches from the navigation rail to the bottom bar.
const double kMobileBreakpoint = 700;

class SizingInformation {
  final bool isMobile;
  final bool isTabletOrDesktop;
  final bool isDesktop;

  const SizingInformation(double width)
    : isMobile = width < kMobileBreakpoint,
      isTabletOrDesktop = width >= kMobileBreakpoint,
      isDesktop = width >= 800;
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(SizingInformation sizingInformation) builder;

  const ResponsiveBuilder({required this.builder});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return builder(SizingInformation(width));
  }
}
