import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Booking card me room category dikhane wala chhota tag.
/// Lamba naam ho to 2 line tak wrap hota hai, dates ko push nahi karta.
class RoomCategoryTag extends StatelessWidget {
  final String room;
  const RoomCategoryTag(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.king_bed_outlined,
              size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              room,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}