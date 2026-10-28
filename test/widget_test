import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haneen_kids_vod/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Haneen Kids v3.0 Security, Isolation & Educational Audit Tests', () {
    late AppStateManager appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      appState = AppStateManager(prefs);
      await appState.initialize();
      AppNetworkPolicyGuard.isOfflineOnlyModeActive = false;
      AppNetworkPolicyGuard.isExternalVideosAllowed = true;
      AppNetworkPolicyGuard.blockedNetworkRequestsCount = 0;
    });

    test('1. ParentAccount hashes PIN and password with per-account random salt (never plain text)', () {
      final acc1 = ParentAccount(
        fullName: 'Parent One',
        emailOrPhone: 'p1@example.com',
        password: 'mySecretPassword',
        parentalPin: '4321',
        children: [
          ChildProfile(
            id: 'c1',
            name: 'عمر',
            age: '3–6 سنوات',
            dailyTimeLimit: 20,
            chosenAvatar: '🦁',
          ),
        ],
        activeChildId: 'c1',
      );
      final acc2 = ParentAccount(
        fullName: 'Parent Two',
        emailOrPhone: 'p2@example.com',
        password: 'mySecretPassword',
        parentalPin: '4321',
        children: [
          ChildProfile(
            id: 'c2',
            name: 'سارة',
            age: '3–6 سنوات',
            dailyTimeLimit: 20,
            chosenAvatar: '🦋',
          ),
        ],
        activeChildId: 'c2',
      );

      // Salts must be randomly generated per account
      expect(acc1.credentialSalt, isNotEmpty);
      expect(acc2.credentialSalt, isNotEmpty);
      expect(acc1.credentialSalt, isNot(equals(acc2.credentialSalt)));

      // Hashes must not equal raw secret and must differ across different salts
      expect(acc1.passwordHash, isNot(equals('mySecretPassword')));
      expect(acc1.pinHash, isNot(equals('4321')));
      expect(acc1.passwordHash.startsWith('pbkdf2_sha256\$'), isTrue);
      expect(acc1.pinHash.startsWith('pbkdf2_sha256\$'), isTrue);
      expect(acc1.passwordHash, isNot(equals(acc2.passwordHash)));

      // Verification works accurately
      expect(acc1.verifyPassword('mySecretPassword'), isTrue);
      expect(acc1.verifyPassword('wrongPassword'), isFalse);
      expect(acc1.verifyParentalPin('4321'), isTrue);
      expect(acc1.verifyParentalPin('0000'), isFalse);

      // Legacy migration test: loading plain-text legacy JSON upgrades to PBKDF2 hash
      final legacyLoaded = ParentAccount.fromJson({
        'fullName': 'Legacy User',
        'emailOrPhone': 'legacy@example.com',
        'password': 'oldPlainPassword',
        'parentalPin': '9876',
      });
      expect(legacyLoaded.passwordHash.startsWith('pbkdf2_sha256\$'), isTrue);
      expect(legacyLoaded.pinHash.startsWith('pbkdf2_sha256\$'), isTrue);
      expect(legacyLoaded.verifyPassword('oldPlainPassword'), isTrue);
      expect(legacyLoaded.verifyParentalPin('9876'), isTrue);
    });

    test('2. Non-duplicating rewards: repeating completed game level or lesson does not grant duplicate stars', () async {
      final child = appState.currentAccount!.activeChild;
      final int initialStars = child.starsEarned;
      final int initialIq = child.intelligencePoints;

      // First completion grants reward
      final bool firstWin = await appState.recordBrainGameWin(
        gameId: 'odd_one_out_1',
        gameTitle: 'قوة الملاحظة (المرحلة 1)',
        earnedIqPoints: 15,
        earnedStars: 2,
        learnedWord: 'أسد',
      );
      expect(firstWin, isTrue);
      expect(child.starsEarned, equals(initialStars + 2));
      expect(child.intelligencePoints, equals(initialIq + 15));

      // Second completion of the exact same level allows practice but does NOT grant duplicate stars
      final bool secondWin = await appState.recordBrainGameWin(
        gameId: 'odd_one_out_1',
        gameTitle: 'قوة الملاحظة (المرحلة 1)',
        earnedIqPoints: 15,
        earnedStars: 2,
        learnedWord: 'أسد',
      );
      expect(secondWin, isFalse);
      expect(child.starsEarned, equals(initialStars + 2));
      expect(child.intelligencePoints, equals(initialIq + 15));

      // Academy lesson non-duplication
      final bool firstLesson = await appState.completeAcademyLesson(
        lessonId: 'les_arabic_alif',
        lessonTitle: 'حرف الألف',
        learnedWord: 'أرنب',
        rewardStars: 2,
      );
      expect(firstLesson, isTrue);
      expect(child.starsEarned, equals(initialStars + 4));

      final bool repeatLesson = await appState.completeAcademyLesson(
        lessonId: 'les_arabic_alif',
        lessonTitle: 'حرف الألف',
        learnedWord: 'أرنب',
        rewardStars: 2,
      );
      expect(repeatLesson, isFalse);
      expect(child.starsEarned, equals(initialStars + 4));
    });

    test('3. Multi-child data isolation: switching between Faris and Noor keeps all lessons, stars, achievements, and settings strictly separated', () async {
      final account = appState.currentAccount!;
      expect(account.children.length, greaterThanOrEqualTo(2));
      final String child1Id = account.children[0].id;
      final String child2Id = account.children[1].id;

      await appState.switchActiveChild(child1Id);
      final child1 = account.activeChild;
      final int c2InitialStars = account.children[1].starsEarned;

      await appState.completeAcademyLesson(
        lessonId: 'les_numbers_count',
        lessonTitle: 'الأرقام والعد',
        learnedWord: 'واحد اثنان ثلاثة',
        rewardStars: 2,
      );
      await appState.recordBrainGameWin(
        gameId: 'memory_match_lvl_3',
        gameTitle: 'الذاكرة البصرية 3',
        earnedIqPoints: 20,
        earnedStars: 2,
      );
      await appState.toggleFavoriteInteractiveStory('story_moon_rabbit');

      expect(child1.completedLessons.contains('les_numbers_count'), isTrue);
      expect(child1.favoriteStoryIds.contains('story_moon_rabbit'), isTrue);
      expect(child1.unlockedAchievements.containsKey('first_lesson'), isTrue);

      // Switch to Child 2 (Noor) and verify zero data leakage
      await appState.switchActiveChild(child2Id);
      final child2 = account.activeChild;
      expect(child2.id, equals(child2Id));
      expect(child2.completedLessons.contains('les_numbers_count'), isFalse);
      expect(child2.favoriteStoryIds.contains('story_moon_rabbit'), isFalse);
      expect(child2.unlockedAchievements.containsKey('first_lesson'), isFalse);
      expect(child2.starsEarned, equals(c2InitialStars));
    });

    test('4. Two-tier child data deletion: clearChildActivityHistoryOnly vs deleteAllChildPersonalAndEducationalData', () async {
      final account = appState.currentAccount!;
      final String c1Id = account.children[0].id;
      final String c2Id = account.children[1].id;

      await appState.switchActiveChild(c1Id);
      await appState.completeAcademyLesson(
        lessonId: 'les_colors_shapes',
        lessonTitle: 'الألوان والأشكال',
        learnedWord: 'دائرة حمراء',
      );
      await appState.recordVideoTransitionWatched(videoTitle: 'قصة القمر');

      final child1 = account.activeChild;
      expect(child1.completedLessons, isNotEmpty);
      expect(child1.watchedVideosToday, greaterThan(0));

      // Tier 1: Clear activity log only — preserves lessons, stars, and achievements
      final int starsBeforeLogClear = child1.starsEarned;
      await appState.clearChildActivityHistoryOnly(c1Id);
      expect(child1.watchedVideosToday, equals(0));
      expect(child1.usedMinutesToday, equals(0));
      expect(child1.completedLessons.contains('les_colors_shapes'), isTrue);
      expect(child1.starsEarned, equals(starsBeforeLogClear));

      // Tier 2: Delete all educational & personal data for Child 1 — resets everything for Child 1 without affecting Child 2
      final int c2StarsBefore = account.children[1].starsEarned;
      await appState.deleteAllChildPersonalAndEducationalData(c1Id);
      expect(child1.completedLessons, isEmpty);
      expect(child1.starsEarned, equals(0));
      expect(child1.unlockedAchievements, isEmpty);
      expect(child1.practicedVocabulary, isEmpty);
      expect(account.children[1].starsEarned, equals(c2StarsBefore));
      expect(c2Id, isNot(equals(c1Id)));
    });

    test('5. Service-layer enforcement of offlineOnlyMode, allowExternalVideos, and allowMicrophone', () async {
      final child = appState.currentAccount!.activeChild;

      // Enable offlineOnlyMode -> outbound network requests & video imports are blocked at service layer
      await appState.updateChildPrivacyAndSafetyControls(
        childId: child.id,
        offlineOnlyMode: true,
      );
      expect(AppNetworkPolicyGuard.isOfflineOnlyModeActive, isTrue);

      final importedWhileOffline = await appState.smartAutoImportFromAnyUrlOrPlaylist(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(importedWhileOffline, isEmpty);

      final syncedWhileOffline = await appState.syncVideosFromRemoteUrl(
        'https://example.com/feed.json',
      );
      expect(syncedWhileOffline, isFalse);

      // Disable offline mode, but disable allowExternalVideos -> external URL rejected, local file allowed
      await appState.updateChildPrivacyAndSafetyControls(
        childId: child.id,
        offlineOnlyMode: false,
        allowExternalVideos: false,
      );
      final bool externalAdded = await appState.addCustomVideo(
        VideoModel(
          id: 'v_ext_test',
          title: 'External Video',
          description: 'Desc',
          category: 'habits',
          ageGroup: '3–6 سنوات',
          repeatPhrase: 'ردد',
          activeActivity: 'نشاط',
          streamUrl: 'https://example.com/video.mp4',
        ),
      );
      expect(externalAdded, isFalse);

      final bool localAdded = await appState.addCustomVideo(
        VideoModel(
          id: 'v_loc_test',
          title: 'Local Video',
          description: 'Desc',
          category: 'habits',
          ageGroup: '3–6 سنوات',
          repeatPhrase: 'ردد',
          activeActivity: 'نشاط',
          streamUrl: '/storage/emulated/0/Download/local_story.mp4',
        ),
      );
      expect(localAdded, isTrue);

      // Disable microphone -> CalmVoiceService.startListening immediately refuses and invokes callback
      await appState.updateChildPrivacyAndSafetyControls(
        childId: child.id,
        allowMicrophone: false,
      );
      String? denialReason;
      final bool micStarted = await CalmVoiceService.instance.startListening(
        onResult: (_) {},
        onPermissionOrPolicyDenied: (reason) => denialReason = reason,
      );
      expect(micStarted, isFalse);
      expect(denialReason, isNotNull);
    });
  });
}
