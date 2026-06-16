import 'package:flutter/material.dart';

/// Constrains content width on wide (web) viewports so it doesn't stretch
/// full-bleed, and centres it. Scrolls vertically.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 640, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: child,
        ),
      ),
    );
  }
}
