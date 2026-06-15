import 'package:flutter/material.dart';

// ===================================================================
//  Billzify color palette - Pure black & white (clean)
//  Sab kuch monochrome. Status badges (green/amber) sirf info ke liye.
// ===================================================================

class AppColors {
  // ---- Primary / accent (BLACK - buttons, active items, icons) ----
  static const Color primary = Color(0xFF18181B);
  static const Color accent = Color(0xFF18181B);     // black (lavender hata diya)
  static const Color accentSoft = Color(0xFFF0F0F2); // light grey (initials circle)

  // ---- Surfaces ----
  static const Color background = Color(0xFFF5F5F7);
  static const Color card = Color(0xFFFFFFFF);

  // ---- Text ----
  static const Color textPrimary = Color(0xFF18181B);
  static const Color textSecondary = Color(0xFF6B6B72);

  // ---- Status (sirf payment info ke liye) ----
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFE7F6EC);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSoft = Color(0xFFFAF0DD);

  // ---- Lines ----
  static const Color border = Color(0xFFEAEAEE);
}