import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ===================================================================
//  ChannelAvatar
//  channel_name (string) -> logo (agar hai) warna short naam (jaise "MA")
//  Logo na mile to apne aap text pe fall back karta hai (crash nahi).
//
//  Logos: assets/images/ me rakho. Naam neeche logoAsset() me mapped hain.
// ===================================================================

class ChannelAvatar extends StatelessWidget {
  final String channel;
  final double size;
  const ChannelAvatar({super.key, required this.channel, this.size = 44});

  static String? logoAsset(String channel) {
    final c = channel.toLowerCase();
    if (c.contains('expedia')) return 'assets/images/expedia.png';
    if (c.contains('agoda')) return 'assets/images/agoda.png';
    if (c.contains('booking-engine') || c.contains('engine')) return null;
    if (c.contains('booking.com') || (c.contains('booking') && !c.contains('engine')))
      return 'assets/images/bcom.png';
    if (c.contains('makemytrip') ||
        c.contains('make my trip') ||
        c.contains('mmt')) {
      return 'assets/images/mmtshort.png';
    }
    if (c.contains('cleartrip')) return 'assets/images/cleartrip.png';
    if (c.contains('goibibo')) return 'assets/images/goibibos.png';
    if (c.contains('billzify') || c.contains('sales')) {
      return 'assets/images/blogo1.png';
    }
    if (c.contains('hotels')) return 'assets/images/hotels.png';
    return null;
  }

  static String shortName(String ch) {
    ch = ch.trim();
    if (ch.isEmpty) return '?';
    final words = ch.split(RegExp(r'[\s\-_.]+'));
    if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    return ch.length >= 2 ? ch.substring(0, 2).toUpperCase() : ch.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final asset = logoAsset(channel);
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      child: asset != null
          ? ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Padding(
          padding: EdgeInsets.all(size * 0.16),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      )
          : _fallback(),
    );
  }

  Widget _fallback() => Text(
    shortName(channel),
    style: TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
      fontSize: size * 0.3,
    ),
  );
}