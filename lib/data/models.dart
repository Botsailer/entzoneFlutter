// Catalog types, mirroring the MovieBox H5 API's shapes.
//
// Parsing is deliberately forgiving: this is an unofficial third-party API
// whose fields come and go, so every accessor has a defined answer for junk.

int _int(Object? v) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

String _str(Object? v) => v == null ? '' : v.toString();

String? _strOrNull(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

class ImageInfo {
  const ImageInfo({
    required this.url,
    this.width,
    this.height,
    this.blurHash,
    this.avgHueDark,
    this.avgHueLight,
  });

  final String url;
  final int? width;
  final int? height;
  final String? blurHash;
  final String? avgHueDark;
  final String? avgHueLight;

  static ImageInfo? from(Object? j) {
    if (j is! Map) return null;
    final url = _str(j['url']);
    if (url.isEmpty) return null;
    return ImageInfo(
      url: url,
      width: j['width'] == null ? null : _int(j['width']),
      height: j['height'] == null ? null : _int(j['height']),
      blurHash: _strOrNull(j['blurHash']),
      avgHueDark: _strOrNull(j['avgHueDark']),
      avgHueLight: _strOrNull(j['avgHueLight']),
    );
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'width': width,
    'height': height,
    'blurHash': blurHash,
    'avgHueDark': avgHueDark,
  };
}

/// 0 = all, 1 = movie, 2 = series.
class Subject {
  const Subject({
    required this.subjectId,
    required this.subjectType,
    required this.title,
    required this.detailPath,
    this.description,
    this.releaseDate,
    this.duration,
    this.genre,
    this.cover,
    this.countryName,
    this.imdbRatingValue,
    this.subtitles,
    this.corner,
    this.season,
    this.isPornographic = false,
    this.webHighRisk = false,
    this.trailerUrl,
    this.trailerHeight,
    this.trailerPoster,
  });

  final String subjectId;
  final int subjectType;
  final String title;
  final String detailPath;
  final String? description;
  final String? releaseDate;

  /// Seconds.
  final int? duration;
  final String? genre;
  final ImageInfo? cover;
  final String? countryName;
  final String? imdbRatingValue;
  final String? subtitles;
  final String? corner;
  final int? season;

  /// The catalog flags adult / high-risk entries; both are filtered everywhere.
  final bool isPornographic;
  final bool webHighRisk;

  final String? trailerUrl;
  final int? trailerHeight;
  final String? trailerPoster;

  bool get isSeries => subjectType == 2;

  /// Titles arrive decorated: "Movie Name [Hindi][CAM]". Strip the tags for
  /// display but never for the API — detailPath is what the server knows.
  String get cleanTitle =>
      title.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();

  String get year => (releaseDate != null && releaseDate!.length >= 4)
      ? releaseDate!.substring(0, 4)
      : '';

  String get typeLabel => subjectType == 2 ? 'series' : 'movie';

  /// The API returns "0.0" for "no rating", which is not the same as zero.
  String? get rating {
    final r = imdbRatingValue;
    if (r == null || r.isEmpty || r == '0' || r == '0.0') return null;
    return r;
  }

  List<String> get genres => (genre ?? '')
      .split(RegExp(r'[,/]'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  static Subject? from(Object? j) {
    if (j is! Map) return null;
    final id = _str(j['subjectId']);
    if (id.isEmpty) return null;
    final trailer = j['trailer'];
    final addr = trailer is Map ? trailer['videoAddress'] : null;
    return Subject(
      subjectId: id,
      subjectType: _int(j['subjectType']),
      title: _str(j['title']),
      detailPath: _str(j['detailPath']),
      description: _strOrNull(j['description']),
      releaseDate: _strOrNull(j['releaseDate']),
      duration: j['duration'] == null ? null : _int(j['duration']),
      genre: _strOrNull(j['genre']),
      cover: ImageInfo.from(j['cover']),
      countryName: _strOrNull(j['countryName']),
      imdbRatingValue: _strOrNull(j['imdbRatingValue']),
      subtitles: _strOrNull(j['subtitles']),
      corner: _strOrNull(j['corner']),
      season: j['season'] == null ? null : _int(j['season']),
      isPornographic: j['isPornographic'] == true,
      webHighRisk: j['webHighRisk'] == true,
      trailerUrl: addr is Map ? _strOrNull(addr['url']) : null,
      trailerHeight: addr is Map && addr['height'] != null
          ? _int(addr['height'])
          : null,
      trailerPoster: trailer is Map && trailer['cover'] is Map
          ? _strOrNull((trailer['cover'] as Map)['url'])
          : null,
    );
  }

  /// The fields worth persisting into history and downloads — keeps stored
  /// records small and makes an offline detail page possible.
  Map<String, Object?> toJson() => {
    'subjectId': subjectId,
    'subjectType': subjectType,
    'title': title,
    'detailPath': detailPath,
    if (description != null)
      'description': description!.length > 600
          ? description!.substring(0, 600)
          : description,
    'releaseDate': releaseDate,
    'duration': duration,
    'genre': genre,
    'countryName': countryName,
    'imdbRatingValue': imdbRatingValue,
    'corner': corner,
    'cover': cover?.toJson(),
  };

  factory Subject.fromJson(Map<String, Object?> j) => Subject.from(j)!;
}

/// Drop the entries the catalog flags. Called on every list the app shows.
List<Subject> safeSubjects(Iterable<Subject?> list) => list
    .whereType<Subject>()
    .where((s) => !s.isPornographic && !s.webHighRisk)
    .toList();

class BannerItem {
  const BannerItem({
    required this.title,
    required this.image,
    required this.subject,
  });

  final String title;
  final ImageInfo image;
  final Subject subject;

  static BannerItem? from(Object? j) {
    if (j is! Map) return null;
    final img = ImageInfo.from(j['image']);
    final subj = Subject.from(j['subject']);
    if (img == null || subj == null) return null;
    if (subj.isPornographic || subj.webHighRisk) return null;
    return BannerItem(title: _str(j['title']), image: img, subject: subj);
  }
}

class Section {
  const Section({
    required this.type,
    required this.position,
    required this.title,
    required this.subjects,
    this.banner = const [],
  });

  final String type;
  final int position;
  final String title;
  final List<Subject> subjects;
  final List<BannerItem> banner;

  /// Section titles arrive with emoji decoration the type ramp has no room for.
  String get cleanTitle => title
      .replaceAll(
        RegExp(
          r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
          unicode: true,
        ),
        '',
      )
      .trim();

  static Section from(Map j) {
    final bannerMap = j['banner'];
    return Section(
      type: _str(j['type']),
      position: _int(j['position']),
      title: _str(j['title']),
      subjects: safeSubjects(
        (j['subjects'] as List? ?? const []).map(Subject.from),
      ),
      banner: bannerMap is Map
          ? (bannerMap['items'] as List? ?? const [])
                .map(BannerItem.from)
                .whereType<BannerItem>()
                .toList()
          : const [],
    );
  }
}

class Feed {
  const Feed(this.sections);
  final List<Section> sections;

  static Feed from(Object? j) {
    if (j is! Map) return const Feed([]);
    return Feed(
      ((j['operatingList'] as List?) ?? const [])
          .whereType<Map>()
          .map(Section.from)
          .toList(),
    );
  }

  List<BannerItem> get bannerItems {
    for (final s in sections) {
      if (s.type == 'BANNER' && s.banner.isNotEmpty) return s.banner;
    }
    return const [];
  }

  /// Subject sections, de-duplicated — the API sometimes repeats one.
  List<Section> get subjectSections {
    final seen = <String>{};
    return sections
        .where(
          (s) =>
              (s.type == 'SUBJECTS_MOVIE' || s.type == 'APPOINTMENT_LIST') &&
              s.subjects.isNotEmpty,
        )
        .where((s) => seen.add(s.title))
        .toList();
  }
}

class Staff {
  const Staff({
    required this.staffId,
    required this.staffType,
    required this.name,
    this.character,
    this.avatarUrl,
  });

  final String staffId;

  /// 1 = cast, 2 = director.
  final int staffType;
  final String name;
  final String? character;
  final String? avatarUrl;

  bool get isDirector => staffType == 2;

  static Staff? from(Object? j) {
    if (j is! Map) return null;
    final name = _str(j['name']);
    if (name.isEmpty) return null;
    return Staff(
      staffId: _str(j['staffId']),
      staffType: _int(j['staffType']),
      name: name,
      character: _strOrNull(j['character']),
      avatarUrl: _strOrNull(j['avatarUrl']),
    );
  }

  Map<String, Object?> toJson() => {
    'staffId': staffId,
    'staffType': staffType,
    'name': name,
    'character': character,
    'avatarUrl': avatarUrl,
  };
}

class SeasonResource {
  const SeasonResource({required this.se, required this.maxEp});
  final int se;
  final int maxEp;

  static SeasonResource? from(Object? j) {
    if (j is! Map) return null;
    final se = _int(j['se']);
    if (se <= 0) return null;
    return SeasonResource(se: se, maxEp: _int(j['maxEp']));
  }

  Map<String, Object?> toJson() => {'se': se, 'maxEp': maxEp};
}

class DetailData {
  const DetailData({
    required this.subject,
    this.stars = const [],
    this.seasons = const [],
  });

  final Subject subject;
  final List<Staff> stars;
  final List<SeasonResource> seasons;

  List<Staff> get cast => stars.where((s) => !s.isDirector).toList();
  List<Staff> get directors => stars.where((s) => s.isDirector).toList();

  static DetailData? from(Object? j) {
    if (j is! Map) return null;
    final subj = Subject.from(j['subject']);
    if (subj == null) return null;
    final res = j['resource'];
    return DetailData(
      subject: subj,
      stars: (j['stars'] as List? ?? const [])
          .map(Staff.from)
          .whereType<Staff>()
          .toList(),
      seasons: res is Map
          ? (res['seasons'] as List? ?? const [])
                .map(SeasonResource.from)
                .whereType<SeasonResource>()
                .toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'subject': subject.toJson(),
    'stars': stars.map((s) => s.toJson()).toList(),
    'resource': {'seasons': seasons.map((s) => s.toJson()).toList()},
  };
}

class Pager {
  const Pager({
    required this.hasMore,
    required this.page,
    required this.totalCount,
  });
  final bool hasMore;
  final int page;
  final int totalCount;

  static Pager from(Object? j) {
    if (j is! Map) return const Pager(hasMore: false, page: 1, totalCount: 0);
    return Pager(
      hasMore: j['hasMore'] == true,
      page: _int(j['page']),
      totalCount: _int(j['totalCount']),
    );
  }
}

class PagedSubjects {
  const PagedSubjects({required this.pager, required this.items});
  final Pager pager;
  final List<Subject> items;

  static PagedSubjects from(Object? j) {
    if (j is! Map) {
      return const PagedSubjects(
        pager: Pager(hasMore: false, page: 1, totalCount: 0),
        items: [],
      );
    }
    return PagedSubjects(
      pager: Pager.from(j['pager']),
      items: safeSubjects((j['items'] as List? ?? const []).map(Subject.from)),
    );
  }
}

/// channelId: 1 = movies, 2 = TV, 1006 = anime.
class FilterQuery {
  const FilterQuery({
    required this.channelId,
    this.page = 1,
    this.perPage = 24,
    this.sort = 'Hottest',
    this.genre,
    this.country,
    this.classify,
    this.year,
  });

  final int channelId;
  final int page;
  final int perPage;
  final String sort;
  final String? genre;
  final String? country;

  /// e.g. "Hindi dub".
  final String? classify;
  final String? year;

  FilterQuery copyWith({
    int? channelId,
    int? page,
    int? perPage,
    String? sort,
    Object? genre = _keep,
    Object? country = _keep,
    Object? classify = _keep,
    Object? year = _keep,
  }) => FilterQuery(
    channelId: channelId ?? this.channelId,
    page: page ?? this.page,
    perPage: perPage ?? this.perPage,
    sort: sort ?? this.sort,
    genre: genre == _keep ? this.genre : genre as String?,
    country: country == _keep ? this.country : country as String?,
    classify: classify == _keep ? this.classify : classify as String?,
    year: year == _keep ? this.year : year as String?,
  );

  static const _keep = Object();

  Map<String, Object?> toBody() => {
    'channelId': channelId,
    'page': page,
    'perPage': perPage,
    'sort': sort,
    if (genre != null && genre!.isNotEmpty) 'genre': genre,
    if (country != null && country!.isNotEmpty) 'country': country,
    if (classify != null && classify!.isNotEmpty) 'classify': classify,
    if (year != null && year!.isNotEmpty) 'year': year,
  };

  String get cacheKey =>
      toBody().entries.map((e) => '${e.key}=${e.value}').join('&');
}

class Channel {
  static const movie = 1;
  static const tv = 2;
  static const anime = 1006;
}

/// One playable MP4 rendition.
class PlayStream {
  const PlayStream({
    required this.url,
    required this.resolution,
    required this.height,
    required this.duration,
    required this.codec,
    this.size,
  });

  final String url;
  final String resolution;
  final int height;

  /// Seconds.
  final int duration;
  final String codec;

  /// Bytes.
  final int? size;

  String get label =>
      height > 0 ? '${height}p' : (resolution.isEmpty ? 'auto' : resolution);
}

class PlayResult {
  const PlayResult({
    required this.streams,
    required this.referer,
    required this.hasResource,
    required this.limited,
    required this.vipLocked,
  });

  /// Best quality first.
  final List<PlayStream> streams;

  /// MUST be sent as a header with every media request — the CDN answers 429
  /// without it. This is not optional and not a nicety.
  final String referer;

  /// Headers used by the working browser proxy for each CDN request.
  Map<String, String> get mediaHeaders => {
    'Referer': referer,
    'User-Agent': 'Mozilla/5.0',
  };

  final bool hasResource;
  final bool limited;
  final bool vipLocked;
}

/// Popular search terms + top lists, for the search start screen.
class SearchHome {
  const SearchHome({required this.everyoneSearch, required this.hot});

  final List<String> everyoneSearch;
  final List<({String category, String name, List<Subject> items})> hot;

  static SearchHome from(Object? j) {
    if (j is! Map) return const SearchHome(everyoneSearch: [], hot: []);
    return SearchHome(
      everyoneSearch: (j['everyoneSearch'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _str(e['title']))
          .where((t) => t.isNotEmpty)
          .toList(),
      hot: (j['hot'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => (
              category: _str(e['category']),
              name: _str(e['name']),
              items: safeSubjects(
                (e['items'] as List? ?? const []).map(Subject.from),
              ),
            ),
          )
          .where((e) => e.items.isNotEmpty)
          .toList(),
    );
  }
}

/// Thrown by the API layer. Carries the status so the retry/refresh rules can
/// read it, and a message the interface can actually show someone.
class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}
