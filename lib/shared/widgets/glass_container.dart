// lib/shared/widgets/glass_container.dart

import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget? child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurAmount;
  final Color backgroundColor;
  final BoxBorder? border;

  const GlassContainer({
    super.key,
    this.child,
    this.borderRadius = 16.0,
    this.padding,
    this.blurAmount = 8.0, // Slightly reduced blur for a less transparent look
    this.backgroundColor = const Color(
      0xFF5E7191,
    ), // Use our new light navy blue
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor.withOpacity(
              0.4,
            ), // Adjust opacity for the glassy effect
            borderRadius: BorderRadius.circular(borderRadius),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
