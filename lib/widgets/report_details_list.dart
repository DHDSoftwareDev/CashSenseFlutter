// ignore_for_file: use_super_parameters

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReportDetailsList extends StatelessWidget {
  final List<dynamic> slices; // List<_PieSlice> or similar
  final double total;
  final void Function(dynamic slice)? onRowTap;
  const ReportDetailsList({Key? key, required this.slices, required this.total, this.onRowTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
  // Use the small body text for report detail list rows to match other
  // report cards (uniform 12px bodySmall style).
  final baseStyle = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    // Render as a ListView.separated so rows have dividers and the list can scroll
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: slices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final s = slices[idx];
        final percentStr = total > 0 ? ((s.value / total * 100).toStringAsFixed(1) + '%') : '0.0%';
        return InkWell(
          onTap: onRowTap != null ? () => onRowTap!(s) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.label,
                    style: baseStyle,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  NumberFormat.currency(symbol: '\$').format(s.value),
                  style: baseStyle.copyWith(fontWeight: FontWeight.w500),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 12),
                Text(
                  percentStr,
                  style: baseStyle.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}