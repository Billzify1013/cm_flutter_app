// Shared pieces for the OTA Messages screens (list + chat).
// Look matches the web inbox: Figtree font, soft avatars, channel tags with logos.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_service.dart';
import '../core/error_util.dart';

/// Chat API paths (same API the web inbox uses).
class ChatApi {
  static const String bootstrap = '/chat/api/bootstrap/';
  static const String conversations = '/chat/api/conversations/';
  static String messages(int id) => '/chat/api/conversations/$id/messages/';
  static String read(int id) => '/chat/api/conversations/$id/read/';
  static String send(int id) => '/chat/api/conversations/$id/send/';
  static const String quickReplies = '/chat/api/quick-replies/';
  static String quickReply(int id) => '/chat/api/quick-replies/$id/';

  /// Menu state for the dashboard button: {visible, enabled, unread}.
  static Future<Map<String, dynamic>> menuState() async {
    try {
      final res = await ApiService.instance.getData(bootstrap);
      final d = Map<String, dynamic>.from(res.data as Map);
      debugPrint('CHAT MENU: can_chat=${d['can_chat']} enabled=${d['enabled']}');
      return {
        'visible': d['can_chat'] == true,
        'enabled': d['enabled'] == true,
        'unread': (d['unread_total'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('CHAT MENU ERROR: $e');
      return {'visible': false, 'enabled': false, 'unread': 0};
    }
  }
}

/// Server message from an error (400/403 bodies carry {"message": ...}).
String chatError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String && (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  }
  return friendlyError(e);
}

/// Figtree everywhere on the chat screens (same font as the web inbox).
ThemeData chatTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    textTheme: GoogleFonts.figtreeTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.figtreeTextTheme(base.primaryTextTheme),
    colorScheme: base.colorScheme.copyWith(primary: ChatColors.ink),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: ChatColors.ink),
  );
}

class ChatColors {
  static const Color ink = Color(0xFF1D2238);       // titles, selected chips
  static const Color ink2 = Color(0xFF50566E);      // body text
  static const Color ink3 = Color(0xFF9297AB);      // times, hints
  static const Color line = Color(0xFFE7E8EF);      // borders
  static const Color field = Color(0xFFF3F3F8);     // search box
  static const Color thread = Color(0xFFF6F6FA);    // chat background
  static const Color out = Color(0xFF18181B);       // our replies (black)
  static const Color failed = Color(0xFFE6E6EC);    // not delivered (grey, not red)
  static const Color live = Color(0xFF22A06B);      // "Live" dot
}

// ------------------------------------------------------------ channels
class ChannelInfo {
  final String label;
  final Color fg;     // text colour of the tag
  final Color bg;     // soft background of the tag / avatar
  final String? logo; // asset in assets/images/
  const ChannelInfo(this.label, this.fg, this.bg, [this.logo]);

  /// Matches however the name is written: "Expedia", "Expedia Affiliate Network", "BOOKING.COM" ...
  static ChannelInfo of(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.contains('airbnb')) {
      return const ChannelInfo('Airbnb', Color(0xFFC2384C), Color(0xFFFCEBEE), 'assets/images/airbnb.png');
    }
    if (n.contains('booking')) {
      return const ChannelInfo('Booking.com', Color(0xFF1F4FA0), Color(0xFFE9EFFA), 'assets/images/bcom.png');
    }
    if (n.contains('expedia')) {
      return const ChannelInfo('Expedia', Color(0xFF9A6F0B), Color(0xFFFBF1D9), 'assets/images/expedia.png');
    }
    if (n.contains('agoda')) {
      return const ChannelInfo('Agoda', Color(0xFF6B3FA0), Color(0xFFF1EAF9), 'assets/images/agoda.png');
    }
    if (n.contains('goibibo')) {
      return const ChannelInfo('Goibibo', Color(0xFFC9382E), Color(0xFFFBEAE8), 'assets/images/goibibos.png');
    }
    if (n.contains('makemytrip') || n.contains('mmt')) {
      return const ChannelInfo('MakeMyTrip', Color(0xFFC9382E), Color(0xFFFBEAE8), 'assets/images/mmtshort.png');
    }
    if (n.contains('whatsapp')) {
      return const ChannelInfo('WhatsApp', Color(0xFF1E7A4D), Color(0xFFE7F5EE));
    }
    final label = n.isEmpty ? 'Channel' : '${n[0].toUpperCase()}${n.substring(1)}';
    return ChannelInfo(label, ChatColors.ink2, const Color(0xFFEFF0F4));
  }
}

/// Small square OTA logo (falls back to the first letter if the file is missing).
class ChannelLogo extends StatelessWidget {
  final String? channel;
  final double size;
  const ChannelLogo(this.channel, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final info = ChannelInfo.of(channel);
    Widget letter() => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: info.fg, borderRadius: BorderRadius.circular(size * 0.25)),
      child: Text(info.label[0],
          style: TextStyle(color: Colors.white, fontSize: size * 0.6, fontWeight: FontWeight.w700)),
    );
    if (info.logo == null) return letter();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.asset(
        info.logo!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, error, ___) {
          debugPrint('CHAT LOGO ERROR (${info.logo}): $error');
          return letter();
        },
      ),
    );
  }
}

/// Soft pill with the OTA logo and name, e.g. [logo] Expedia
class ChannelTag extends StatelessWidget {
  final String? channel;
  const ChannelTag(this.channel, {super.key});

  @override
  Widget build(BuildContext context) {
    final info = ChannelInfo.of(channel);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
      decoration: BoxDecoration(color: info.bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ChannelLogo(channel, size: 16),
        const SizedBox(width: 6),
        Text(info.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: info.fg)),
      ]),
    );
  }
}

/// Plain grey pill (listing name, dates) used in the chat header.
class GreyChip extends StatelessWidget {
  final String text;
  final double maxWidth;
  const GreyChip(this.text, {super.key, this.maxWidth = 160});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFEFF0F4), borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ChatColors.ink2)),
    );
  }
}

/// Round avatar with the guest's initials, tinted with the channel colour.
class GuestAvatar extends StatelessWidget {
  final String name;
  final String? channel;
  final double size;
  const GuestAvatar({super.key, required this.name, this.channel, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final info = ChannelInfo.of(channel);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: info.bg),
      child: Text(initialsOf(name),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.34, color: info.fg)),
    );
  }
}

/// Small round unread counter (black, like the selected chips).
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ChatColors.ink, borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count',
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2)),
    );
  }
}

String guestNameOf(Map c) {
  final n = (c['guest_name'] ?? '').toString().trim();
  return n.isNotEmpty ? n : '${ChannelInfo.of(c['channel']?.toString()).label} guest';
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'G';
  final a = parts[0][0];
  final b = parts.length > 1 ? parts[1][0] : '';
  return (a + b).toUpperCase();
}

// ---------------------------------------------------------------- dates
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime? parseTs(dynamic iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso.toString())?.toLocal();
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String fmtTime(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String fmtListTime(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (sameDay(d, now)) return fmtTime(d);
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return fmtShortDate(d);
}

String dayLabel(DateTime d) {
  final now = DateTime.now();
  if (sameDay(d, now)) return 'Today';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]}, ${fmtShortDate(d)}';
  return d.year == now.year ? base : '$base ${d.year}';
}

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------- stay
const Map<String, String> stayStatusLabels = {
  'in_house': 'In-house',
  'upcoming': 'Upcoming',
  'checked_out': 'Checked out',
  'cancelled': 'Cancelled',
  'no_show': 'No-show',
};

/// "20 Jan – 21 Jan, 1 night"
String stayText(Map stay) {
  final ci = DateTime.tryParse('${stay['check_in']}');
  final co = DateTime.tryParse('${stay['check_out']}');
  var t = '';
  if (ci != null && co != null) t = '${fmtShortDate(ci)} – ${fmtShortDate(co)}';
  final nights = (stay['nights'] as num?)?.toInt() ?? 0;
  if (nights > 0) t += ', $nights ${nights == 1 ? 'night' : 'nights'}';
  return t;
}

/// "20 Jan – 21 Jan" (short, for the chat header)
String stayDatesShort(Map stay) {
  final ci = DateTime.tryParse('${stay['check_in']}');
  final co = DateTime.tryParse('${stay['check_out']}');
  if (ci == null || co == null) return '';
  return '${fmtShortDate(ci)} – ${fmtShortDate(co)}';
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = stayStatusLabels[status];
    if (label == null) return const SizedBox.shrink();
    Color bg;
    Color fg;
    switch (status) {
      case 'in_house':
        bg = const Color(0xFFE7F5EE);
        fg = const Color(0xFF1E7A4D);
        break;
      case 'upcoming':
        bg = const Color(0xFFEEEDFB);
        fg = const Color(0xFF4A43C9);
        break;
      case 'checked_out':
        bg = const Color(0xFFF0F1F5);
        fg = ChatColors.ink3;
        break;
      default: // cancelled / no-show: muted, not alarming
        bg = const Color(0xFFF3EFE7);
        fg = const Color(0xFF7A6A4F);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class ChatEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const ChatEmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: ChatColors.field, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: ChatColors.ink2, size: 30),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ChatColors.ink)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: ChatColors.ink3, height: 1.4)),
          ],
        ),
      ),
    );
  }
}