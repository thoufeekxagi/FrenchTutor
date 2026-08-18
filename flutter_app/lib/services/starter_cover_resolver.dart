/// Resolves the bundled artwork for the pre-generated starter library.
///
/// Starter assets are local by design. Sync strips the `asset:` marker before
/// sending rows to Supabase, so a newly hydrated starter row can legitimately
/// have a null cover while its private upload is being repaired. Keeping this
/// lookup independent from the starter seeding service lets every local store
/// restore the immediate bundled image without coupling storage to the UI.
class StarterCoverResolver {
  const StarterCoverResolver._();

  static const _coversByTitle = <String, String>{
    'le marché du matin': 'assets/starter_covers/market.png',
    'à la gare': 'assets/starter_covers/station.png',
    'la lanterne du jardin': 'assets/starter_covers/lantern.png',
    'le moineau et la tablette': 'assets/starter_covers/sparrow.png',
    'le petit bateau en papier': 'assets/starter_covers/boat.png',
    'une visite au marché': 'assets/starter_covers/market.png',
    'mon dernier voyage': 'assets/starter_covers/station.png',
    'un soir tranquille': 'assets/starter_covers/lantern.png',
    'mon projet de demain': 'assets/starter_covers/sparrow.png',
    'un voyage imaginaire': 'assets/starter_covers/boat.png',
    'au marché': 'assets/starter_covers/market.png',
    'dans le jardin': 'assets/starter_covers/lantern.png',
    'une rencontre surprenante': 'assets/starter_covers/sparrow.png',
    'au bord de l’eau': 'assets/starter_covers/boat.png',
  };

  /// Returns the existing URL first. A known starter title only falls back to
  /// its bundled asset when the remote/local cover is absent.
  static String? resolve({required String title, String? coverUrl}) {
    if (coverUrl != null && coverUrl.trim().isNotEmpty) return coverUrl;
    final normalized = title.trim().toLowerCase();
    final asset = _coversByTitle[normalized];
    return asset == null ? coverUrl : 'asset:$asset';
  }
}
