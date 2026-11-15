// Unit tests for the parts of depressedzone that have no screen: the catalog
// model parsing (which must survive whatever the unofficial API returns), the
// next-episode chain, and the watched-state rule.

import 'package:depressedzone/data/models.dart';
import 'package:depressedzone/data/playback.dart';
import 'package:depressedzone/data/progress.dart';
import 'package:depressedzone/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Subject parsing', () {
    test('strips bracket tags from the display title but keeps detailPath', () {
      final s = Subject.from({
        'subjectId': '42',
        'subjectType': 1,
        'title': 'Some Film [Hindi][CAM]',
        'detailPath': 'some-film-2024',
      })!;
      expect(s.cleanTitle, 'Some Film');
      expect(s.title, 'Some Film [Hindi][CAM]');
      expect(s.detailPath, 'some-film-2024');
    });

    test('treats "0.0" as no rating', () {
      Subject make(String r) => Subject.from({
            'subjectId': '1',
            'title': 't',
            'detailPath': 'p',
            'imdbRatingValue': r,
          })!;
      expect(make('0.0').rating, isNull);
      expect(make('0').rating, isNull);
      expect(make('7.4').rating, '7.4');
    });

    test('survives junk and missing fields', () {
      expect(Subject.from(null), isNull);
      expect(Subject.from({'title': 'no id'}), isNull);
      final s = Subject.from({'subjectId': '9', 'duration': '5400'})!;
      expect(s.duration, 5400);
      expect(s.year, '');
      expect(s.genres, isEmpty);
    });

    test('filters flagged entries out of every list', () {
      final list = [
        Subject.from({'subjectId': '1', 'title': 'ok', 'detailPath': 'a'}),
        Subject.from({'subjectId': '2', 'title': 'x', 'detailPath': 'b', 'isPornographic': true}),
        Subject.from({'subjectId': '3', 'title': 'y', 'detailPath': 'c', 'webHighRisk': true}),
      ];
      expect(safeSubjects(list).map((s) => s.subjectId), ['1']);
    });
  });

  group('Feed', () {
    test('de-duplicates repeated sections by title', () {
      final feed = Feed.from({
        'operatingList': [
          {
            'type': 'SUBJECTS_MOVIE',
            'title': 'Trending',
            'subjects': [
              {'subjectId': '1', 'title': 'a', 'detailPath': 'a'}
            ]
          },
          {
            'type': 'SUBJECTS_MOVIE',
            'title': 'Trending',
            'subjects': [
              {'subjectId': '2', 'title': 'b', 'detailPath': 'b'}
            ]
          },
        ]
      });
      expect(feed.subjectSections.length, 1);
    });

    test('strips emoji from section titles', () {
      final s = Section.from({'type': 'SUBJECTS_MOVIE', 'title': '🔥 Hot Now', 'subjects': []});
      expect(s.cleanTitle, 'Hot Now');
    });
  });

  group('next episode', () {
    final seasons = [
      const SeasonResource(se: 1, maxEp: 3),
      const SeasonResource(se: 2, maxEp: 2),
    ];

    test('advances within a season', () {
      expect(nextEpisodeRef(seasons, const EpisodeRef(1, 1)), const EpisodeRef(1, 2));
    });

    test('rolls into the next season', () {
      expect(nextEpisodeRef(seasons, const EpisodeRef(1, 3)), const EpisodeRef(2, 1));
    });

    test('returns null at the end of the last season', () {
      expect(nextEpisodeRef(seasons, const EpisodeRef(2, 2)), isNull);
    });
  });

  group('watched rule', () {
    test('the last 15 seconds of a short video count as watched', () {
      expect(isWatchedAt(100, 110), isTrue);
      expect(isWatchedAt(80, 110), isFalse);
    });

    test('the last 4% of a long video counts as watched', () {
      expect(isWatchedAt(5800, 6000), isTrue); // 200s left of 6000 == 3.3%
      expect(isWatchedAt(5000, 6000), isFalse);
    });

    test('a zero-length video is never watched', () {
      expect(isWatchedAt(0, 0), isFalse);
    });
  });

  group('quality preference', () {
    test('picks the best rendition at or below the target', () {
      expect(pickByHeight([1080, 720, 480], 720), 1);
      expect(pickByHeight([1080, 720, 480], 1080), 0);
    });

    test('falls back to the lowest when everything is above the target', () {
      expect(pickByHeight([1080, 720], 360), 1);
    });

    test('auto takes the best available', () {
      expect(pickByHeight([1080, 720, 480], null), 0);
    });
  });

  group('settings round-trip', () {
    test('survives a save and load with unknown keys present', () {
      const s = Settings(skipSeconds: 30, autoplayNext: false, subtitleSize: 1.5);
      final back = Settings.fromJson({...s.toJson(), 'somethingNew': 1});
      expect(back.skipSeconds, 30);
      expect(back.autoplayNext, isFalse);
      expect(back.subtitleSize, 1.5);
    });

    test('falls back to defaults on junk', () {
      expect(Settings.fromJson('nonsense').skipSeconds, 10);
      expect(Settings.fromJson(null).autoplayNext, isTrue);
    });
  });
}
