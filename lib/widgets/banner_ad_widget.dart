import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import '../services/database_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    DatabaseService.subscriptionVersion.addListener(_onPlanChanged);
    _syncAdForPlan();
  }

  void _onPlanChanged() {
    _syncAdForPlan();
    if (mounted) setState(() {});
  }

  void _syncAdForPlan() {
    final isFree = DatabaseService.subscriptionVersion.value == 'Free';
    if (!isFree) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      return;
    }
    if (_ad != null) return;

    _ad = BannerAd(
      adUnitId: 'ca-app-pub-3193820644001678/9448428184', // iOS banner ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || DatabaseService.subscriptionVersion.value != 'Free') {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (identical(_ad, ad)) _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    DatabaseService.subscriptionVersion.removeListener(_onPlanChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DatabaseService.subscriptionVersion.value != 'Free') {
      return const SizedBox.shrink();
    }
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
