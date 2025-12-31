// ignore_for_file: sized_box_for_whitespace

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/database_service.dart';

class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});
  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nativeAd = NativeAd(
      adUnitId: 'ca-app-pub-3193820644001678/5478211822', // iOS native banner ID
      factoryId: 'listTile', // Must match a registered factory
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, error) { ad.dispose(); },
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show ads to free users
    final plan = DatabaseService.getSetting<String>('subscriptionPlan', 'Free') ?? 'Free';
    if (plan != 'Free') return const SizedBox.shrink();
    if (!_loaded || _nativeAd == null) return const SizedBox.shrink();
    return Container(
      height: 72, // Adjust as needed
      child: AdWidget(ad: _nativeAd!),
    );
  }
}

// To use NativeAdWidget, you must register a native ad factory in your platform code.
// See the google_mobile_ads documentation for details:
// https://pub.dev/packages/google_mobile_ads#native-ads
