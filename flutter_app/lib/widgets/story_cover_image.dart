import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/starter_cover_resolver.dart';

/// Renders a story cover from either a private remote URL or a bundled
/// `asset:` marker. The bundled asset is also used when a previously signed
/// private URL has expired or cannot be reached, so starter lessons never
/// lose their artwork while storage is being repaired.
class StoryCoverImage extends StatelessWidget {
  const StoryCoverImage({
    super.key,
    required this.title,
    this.source,
    this.fit = BoxFit.cover,
    this.fallbackIcon = CupertinoIcons.book_fill,
  });

  final String title;
  final String? source;
  final BoxFit fit;
  final IconData? fallbackIcon;

  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: fallbackIcon == null
          ? null
          : Center(child: Icon(fallbackIcon, color: Colors.white, size: 34)),
    );
  }

  Widget _asset(String path) {
    return Image.asset(path, fit: fit, errorBuilder: (_, _, _) => _fallback());
  }

  Widget _resolvedAssetFallback() {
    final local = StarterCoverResolver.resolve(title: title);
    if (local != null && local.startsWith('asset:')) {
      return _asset(local.substring('asset:'.length));
    }
    return _fallback();
  }

  @override
  Widget build(BuildContext context) {
    final value = source?.trim() ?? '';
    if (value.startsWith('asset:')) {
      return _asset(value.substring('asset:'.length));
    }
    if (value.isNotEmpty) {
      return Image.network(
        value,
        fit: fit,
        errorBuilder: (_, _, _) => _resolvedAssetFallback(),
      );
    }
    return _resolvedAssetFallback();
  }
}
