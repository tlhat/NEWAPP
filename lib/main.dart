import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

const String kDefaultRemoteFeedUrl = '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final AppStateManager appState = AppStateManager(prefs);
  await appState.initialize();
  runApp(HaneenKidsApp(appState: appState));
}

class CalmVoiceService {
  static final CalmVoiceService instance = CalmVoiceService._internal();
  CalmVoiceService._internal();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _ttsReady = false;
  bool _sttReady = false;
  bool isSpeaking = false;
  bool isAssistantMuted = false;

  Future<void> setAssistantMuted(bool muted) async {
    isAssistantMuted = muted;
    if (muted) {
      await stopSpeaking();
    }
  }

  Future<void> init() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('ar-EG');
      await _tts.setSpeechRate(0.38);
      await _tts.setPitch(0.95);
      await _tts.setVolume(1.0);
      _tts.setStartHandler(() {
        isSpeaking = true;
      });
      _tts.setCompletionHandler(() {
        isSpeaking = false;
      });
      _tts.setErrorHandler((_) {
        isSpeaking = false;
      });
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
  }

  Future<void> speakCalmly(
    String text, {
    double rate = 0.38,
    bool forceSpeakEvenIfAssistantMuted = false,
    bool allowSpeechForRepeatGame = false,
  }) async {
    if (!allowSpeechForRepeatGame) return;
    try {
      await init();
      final String cleanText = text
          .replaceAll('«', '')
          .replaceAll('»', '')
          .replaceAll('"', '')
          .trim();
      if (cleanText.isEmpty) return;
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(0.95);
      await _tts.stop();
      await _tts.speak(cleanText);
    } catch (_) {}
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
      isSpeaking = false;
    } catch (_) {}
  }

  Future<bool> initSpeechRecognition() async {
    try {
      if (_sttReady) return true;
      _sttReady = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      return _sttReady;
    } catch (_) {
      return false;
    }
  }

  Future<void> startListening({
    required void Function(String recognizedWords) onResult,
  }) async {
    final bool available = await initSpeechRecognition();
    if (!available) return;
    await stopSpeaking();
    await _speech.listen(
      localeId: 'ar_EG',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (result) {
        onResult(result.recognizedWords);
      },
    );
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  static String normalizeArabicText(String input) {
    final RegExp diacritics =
        RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED«»"؛،؟!.,:\-\(\)]');
    String cleaned = input.replaceAll(diacritics, ' ');
    cleaned = cleaned
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static PronunciationEvaluation evaluatePronunciation({
    required String targetPhrase,
    required String spokenText,
  }) {
    final String normTarget = normalizeArabicText(targetPhrase);
    final String normSpoken = normalizeArabicText(spokenText);

    final List<String> targetWords =
        normTarget.split(' ').where((w) => w.isNotEmpty).toList();
    final List<String> spokenWords =
        normSpoken.split(' ').where((w) => w.isNotEmpty).toList();

    if (targetWords.isEmpty) {
      return PronunciationEvaluation(
        accuracyScore: 1.0,
        isCorrect: true,
        matchedWords: const [],
        missingOrWrongWords: const [],
        correctionAdvice: 'أحسنت النطق يا بطل!',
      );
    }

    if (spokenWords.isEmpty) {
      return PronunciationEvaluation(
        accuracyScore: 0.0,
        isCorrect: false,
        matchedWords: const [],
        missingOrWrongWords: targetWords,
        correctionAdvice:
            'لم نسمع الجملة بوضوح، استمع إلى النطق الهادئ ثم حاول ترديد الجملة كاملة بصوت واضح.',
      );
    }

    final List<String> matched = [];
    final List<String> missing = [];

    for (final String tWord in targetWords) {
      bool found = false;
      for (final String sWord in spokenWords) {
        if (sWord == tWord ||
            (tWord.length >= 3 &&
                (sWord.contains(tWord) || tWord.contains(sWord)))) {
          found = true;
          break;
        }
      }
      if (found) {
        matched.add(tWord);
      } else {
        missing.add(tWord);
      }
    }

    final double score = matched.length / targetWords.length;
    final bool passed = score >= 0.65;

    String advice;
    if (score >= 0.95) {
      advice = 'ما شاء الله! نطقك العربي فصيح ومتقن بنسبة ١٠٠٪ يا بطل حنين!';
    } else if (passed) {
      advice = missing.isEmpty
          ? 'نطق رائع جداً! استمر على هذا الهدوء والوضوح.'
          : 'أحسنت يا بطل! نطقك جميل جداً، ولتكون أروع انتبه لنطق كلمة (${missing.join(" ، ")}) بهدوء.';
    } else {
      advice =
          'محاولة جميلة يا بطل! هيا نستمع معاً للنطق الهادئ ونركز على نطق الكلمات: (${missing.join(" ، ")}) ثم نردد معاً ببطء.';
    }

    return PronunciationEvaluation(
      accuracyScore: score,
      isCorrect: passed,
      matchedWords: matched,
      missingOrWrongWords: missing,
      correctionAdvice: advice,
    );
  }
}

class PronunciationEvaluation {
  final double accuracyScore;
  final bool isCorrect;
  final List<String> matchedWords;
  final List<String> missingOrWrongWords;
  final String correctionAdvice;

  const PronunciationEvaluation({
    required this.accuracyScore,
    required this.isCorrect,
    required this.matchedWords,
    required this.missingOrWrongWords,
    required this.correctionAdvice,
  });
}

class ImportedVideoSourceMetadata {
  final String? title;
  final String? originalDescription;
  final String? authorName;
  final String? hdStreamUrl;
  final String? separateAudioStreamUrl;
  final String sourceRawUrl;
  final String qualityBadge;
  final bool isVerticalSource;
  final bool resolvedRealStream;

  const ImportedVideoSourceMetadata({
    this.title,
    this.originalDescription,
    this.authorName,
    this.hdStreamUrl,
    this.separateAudioStreamUrl,
    required this.sourceRawUrl,
    this.qualityBadge = '1080p Full HD',
    this.isVerticalSource = true,
    this.resolvedRealStream = false,
  });
}

class SmartVideoLinkAutoImporter {
  static String stripPlatformMentions(String input) {
    final RegExp forbiddenPlatforms = RegExp(
      r'(youtube\s*shorts|youtube|youtu\.be|tiktok|tik\s*tok|انستقرام|انستغرام|فيسبوك|تيك\s*توك|تيكتوك|التيك\s*توك|التيكتوك|يوتيوب|اليوتيوب|شورتس|shorts|reels)',
      caseSensitive: false,
    );
    String cleaned = input.replaceAll(forbiddenPlatforms, '');
    cleaned = cleaned
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '')
        .replaceAll(RegExp(r'-\s*-'), '-')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return cleaned;
  }

  static String? extractYouTubeVideoId(String url) {
    final RegExp regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|shorts|live)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url.trim());
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  static String? extractYouTubePlaylistId(String url) {
    final RegExp listRegex =
        RegExp(r'[?&]list=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = listRegex.firstMatch(url.trim());
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  static bool isYouTubeChannelOrPlaylistUrl(String url) {
    final lower = url.toLowerCase().trim();
    if (!isYouTubeUrl(lower)) return false;
    return extractYouTubePlaylistId(url) != null;
  }

  static String? extractTikTokUsernameFromProfile(String url) {
    final String trimmed = Uri.decodeFull(url.trim());
    if (trimmed.startsWith('@') && !trimmed.contains('/')) {
      return trimmed.substring(1).trim();
    }
    if (!isTikTokUrl(trimmed)) return null;
    if (trimmed.toLowerCase().contains('/video/') ||
        trimmed.toLowerCase().contains('/photo/')) {
      return null;
    }
    final RegExp profileRegex =
        RegExp(r'tiktok\.com\/@([a-zA-Z0-9_.-]+)', caseSensitive: false);
    final match = profileRegex.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  static Future<String> _resolveRedirectUrlIfNeeded(String rawUrl) async {
    String currentUrl = rawUrl.trim();
    if (currentUrl.startsWith('@') && !currentUrl.contains('/')) {
      return 'https://www.tiktok.com/$currentUrl';
    }
    final String lower = currentUrl.toLowerCase();
    if (!lower.contains('vm.tiktok.com') &&
        !lower.contains('vt.tiktok.com') &&
        !lower.contains('tiktok.com/t/')) {
      return currentUrl;
    }

    final client = http.Client();
    try {
      for (int hop = 0; hop < 5; hop++) {
        final req = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36';
        final streamed =
            await client.send(req).timeout(const Duration(seconds: 6));
        final String? loc = streamed.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          if (loc.startsWith('http')) {
            currentUrl = loc;
          } else if (loc.startsWith('/')) {
            final uri = Uri.parse(currentUrl);
            currentUrl = '${uri.scheme}://${uri.host}$loc';
          }
          if (currentUrl.contains('/@') || currentUrl.contains('/video/')) {
            break;
          }
        } else {
          break;
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return currentUrl;
  }

  static Future<bool> detectIfChannelOrPlaylistUrl(String rawUrl) async {
    return extractYouTubePlaylistId(rawUrl) != null;
  }

  static bool isChannelOrPlaylistUrl(String url) {
    return extractYouTubePlaylistId(url) != null;
  }

  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  static bool isTikTokUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('tiktok.com') || lower.startsWith('@');
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"')
        .trim();
  }

  static String _normalizeAbsoluteTikwmUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    final String u = rawUrl.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return 'https://www.tikwm.com$u';
    return 'https://www.tikwm.com/$u';
  }

  static List<Map<String, String>> _extractTikwmVideoListFromResponse(
      dynamic decoded) {
    final List<Map<String, String>> results = [];
    if (decoded is! Map) return results;
    final dynamic dataNode = decoded['data'];
    List<dynamic>? rawList;
    if (dataNode is Map) {
      if (dataNode['videos'] is List) {
        rawList = dataNode['videos'] as List<dynamic>;
      } else if (dataNode['itemList'] is List) {
        rawList = dataNode['itemList'] as List<dynamic>;
      }
    } else if (dataNode is List) {
      rawList = dataNode;
    }
    if (rawList == null) return results;

    for (final v in rawList) {
      if (v is Map) {
        final String rawCaption =
            stripPlatformMentions((v['title'] ?? v['desc'] ?? '').toString());
        final String hdPlay =
            _normalizeAbsoluteTikwmUrl(v['hdplay']?.toString());
        final String play = _normalizeAbsoluteTikwmUrl(v['play']?.toString());
        final String wmPlay =
            _normalizeAbsoluteTikwmUrl(v['wmplay']?.toString());
        final String bestUrl = hdPlay.startsWith('http')
            ? hdPlay
            : (play.startsWith('http') ? play : wmPlay);
        final String videoIdStr =
            (v['video_id'] ?? v['aweme_id'] ?? v['id'] ?? '').toString();
        if (bestUrl.startsWith('http')) {
          results.add({
            'title': rawCaption.split('\n').first.trim(),
            'description': rawCaption,
            'streamUrl': bestUrl,
            'videoId': videoIdStr,
            'badge': hdPlay.startsWith('http') ? '1080p Full HD' : '720p HD',
          });
        }
      }
    }
    return results;
  }

  static Future<ImportedVideoSourceMetadata> fetchHighDefStreamAndExactMetadata(
      String rawUrl) async {
    final String trimmed = await _resolveRedirectUrlIfNeeded(rawUrl.trim());

    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      final String fileName = trimmed.split('/').last.replaceAll('.mp4', '');
      return ImportedVideoSourceMetadata(
        title: fileName.isNotEmpty ? fileName : 'فيديو محلي عالي الدقة',
        originalDescription:
            'فيديو محلي بأعلى جودة أصلية من ذاكرة الجهاز ($fileName).',
        hdStreamUrl: trimmed,
        sourceRawUrl: trimmed,
        qualityBadge: 'Original 1080p HD',
        isVerticalSource: true,
        resolvedRealStream: true,
      );
    }

    if (trimmed.contains('drive.google.com/file/d/')) {
      final RegExp driveRegex =
          RegExp(r'drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)');
      final match = driveRegex.firstMatch(trimmed);
      if (match != null && match.groupCount >= 1) {
        final String fileId = match.group(1)!;
        return ImportedVideoSourceMetadata(
          title: 'قصة سحابية عالية الجودة',
          originalDescription: 'بث مرئي مباشر بالجودة الأصلية الكاملة.',
          hdStreamUrl: 'https://drive.google.com/uc?export=download&id=$fileId',
          sourceRawUrl: trimmed,
          qualityBadge: 'Original HD',
          isVerticalSource: true,
          resolvedRealStream: true,
        );
      }
    }

    if (isTikTokUrl(trimmed)) {
      String? ttTitle;
      String? ttDesc;
      String? ttAuthor;
      String? bestHdUrl;
      String badge = '1080p Full HD';

      try {
        final postRes = await http.post(
          Uri.parse('https://www.tikwm.com/api/'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          },
          body: {'url': trimmed, 'hd': '1'},
        ).timeout(const Duration(seconds: 12));

        if (postRes.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(postRes.bodyBytes));
          if (decoded is Map && decoded['data'] is Map) {
            final dataMap = decoded['data'] as Map;
            final String? rawCaption = dataMap['title']?.toString().trim();
            if (rawCaption != null && rawCaption.isNotEmpty) {
              ttDesc = rawCaption;
              ttTitle = rawCaption.split('\n').first.trim();
            }
            if (dataMap['author'] is Map) {
              ttAuthor = (dataMap['author'] as Map)['nickname']?.toString();
            }
            final String hdPlay =
                _normalizeAbsoluteTikwmUrl(dataMap['hdplay']?.toString());
            final String play =
                _normalizeAbsoluteTikwmUrl(dataMap['play']?.toString());
            final String wmPlay =
                _normalizeAbsoluteTikwmUrl(dataMap['wmplay']?.toString());

            if (hdPlay.startsWith('http')) {
              bestHdUrl = hdPlay;
              badge = '1080p Full HD';
            } else if (play.startsWith('http')) {
              bestHdUrl = play;
              badge = '720p HD';
            } else if (wmPlay.startsWith('http')) {
              bestHdUrl = wmPlay;
              badge = 'HD';
            }
          }
        }
      } catch (_) {}

      if (bestHdUrl == null) {
        try {
          final getUri = Uri.parse(
              'https://www.tikwm.com/api/?url=${Uri.encodeComponent(trimmed)}&hd=1');
          final getRes = await http.get(
            getUri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
            },
          ).timeout(const Duration(seconds: 10));
          if (getRes.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(getRes.bodyBytes));
            if (decoded is Map && decoded['data'] is Map) {
              final dataMap = decoded['data'] as Map;
              final String? rawCaption = dataMap['title']?.toString().trim();
              if (rawCaption != null && rawCaption.isNotEmpty) {
                ttDesc ??= rawCaption;
                ttTitle ??= rawCaption.split('\n').first.trim();
              }
              final String hdPlay =
                  _normalizeAbsoluteTikwmUrl(dataMap['hdplay']?.toString());
              final String play =
                  _normalizeAbsoluteTikwmUrl(dataMap['play']?.toString());
              if (hdPlay.startsWith('http')) {
                bestHdUrl = hdPlay;
                badge = '1080p Full HD';
              } else if (play.startsWith('http')) {
                bestHdUrl = play;
                badge = '720p HD';
              }
            }
          }
        } catch (_) {}
      }

      if (ttTitle == null || ttDesc == null) {
        try {
          final oembedRes = await http
              .get(Uri.parse(
                  'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(trimmed)}'))
              .timeout(const Duration(seconds: 6));
          if (oembedRes.statusCode == 200) {
            final data = jsonDecode(utf8.decode(oembedRes.bodyBytes));
            if (data is Map) {
              final String? oTitle = data['title']?.toString().trim();
              ttAuthor ??= data['author_name']?.toString().trim();
              if (oTitle != null && oTitle.isNotEmpty) {
                ttDesc ??= oTitle;
                ttTitle ??= oTitle.split('\n').first.trim();
              }
            }
          }
        } catch (_) {}
      }

      return ImportedVideoSourceMetadata(
        title: ttTitle,
        originalDescription: ttDesc,
        authorName: ttAuthor,
        hdStreamUrl: bestHdUrl,
        sourceRawUrl: trimmed,
        qualityBadge: badge,
        isVerticalSource: true,
        resolvedRealStream: bestHdUrl != null,
      );
    }

    if (isYouTubeUrl(trimmed)) {
      String? ytTitle;
      String? ytDesc;
      String? ytAuthor;
      String? bestStreamUrl;
      String? separateAudioUrl;
      String badge = '1080p Full HD';
      bool isVertical = trimmed.toLowerCase().contains('/shorts/');

      final yt = yt_explode.YoutubeExplode();
      try {
        final String? extractedId = extractYouTubeVideoId(trimmed);
        final videoId = yt_explode.VideoId(extractedId ?? trimmed);
        final video =
            await yt.videos.get(videoId).timeout(const Duration(seconds: 12));

        ytTitle = video.title.trim();
        ytDesc = video.description.trim();
        ytAuthor = video.author.trim();

        final manifest = await yt.videos.streamsClient
            .getManifest(videoId)
            .timeout(const Duration(seconds: 12));

        final mp4VideoOnlyList = manifest.videoOnly
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .toList()
          ..sort((a, b) {
            final cmpRes = b.videoResolution.height
                .compareTo(a.videoResolution.height);
            if (cmpRes != 0) return cmpRes;
            return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
          });

        if (mp4VideoOnlyList.isNotEmpty && manifest.audioOnly.isNotEmpty) {
          final bestVo = mp4VideoOnlyList.firstWhere(
            (s) => s.videoResolution.height <= 1920,
            orElse: () => mp4VideoOnlyList.first,
          );
          final bestAo = manifest.audioOnly.withHighestBitrate();
          final int h = bestVo.videoResolution.height;
          final int w = bestVo.videoResolution.width;
          if (h > w) isVertical = true;

          if (h >= 720) {
            bestStreamUrl = bestVo.url.toString();
            separateAudioUrl = bestAo.url.toString();
            final int shortSide = min(w, h);
            badge = shortSide >= 1080
                ? '1080p Full HD'
                : (shortSide >= 720 ? '720p HD' : '${h}p HD');
          }
        }

        if (bestStreamUrl == null && manifest.hls.isNotEmpty) {
          final bestHls = manifest.hls.withHighestBitrate();
          bestStreamUrl = bestHls.url.toString();
          badge = '1080p Adaptive HLS';
        }

        if (bestStreamUrl == null && manifest.muxed.isNotEmpty) {
          final bestMuxed = manifest.muxed.withHighestBitrate();
          bestStreamUrl = bestMuxed.url.toString();
          final int h = bestMuxed.videoResolution.height;
          final int w = bestMuxed.videoResolution.width;
          if (h > w) {
            isVertical = true;
          }
          badge = h >= 720 ? '${h}p Full HD' : '${h}p HD';
        }
      } catch (_) {
      } finally {
        yt.close();
      }

      if (bestStreamUrl == null) {
        final String? ytId = extractYouTubeVideoId(trimmed);
        if (ytId != null) {
          final List<String> pipedApis = [
            'https://pipedapi.kavin.rocks/streams/$ytId',
            'https://pipedapi.tokhmi.xyz/streams/$ytId',
            'https://inv.tux.pizza/api/v1/videos/$ytId',
          ];
          for (final api in pipedApis) {
            try {
              final res = await http
                  .get(Uri.parse(api))
                  .timeout(const Duration(seconds: 7));
              if (res.statusCode == 200) {
                final decoded = jsonDecode(utf8.decode(res.bodyBytes));
                if (decoded is Map) {
                  ytTitle ??= decoded['title']?.toString().trim();
                  ytDesc ??= decoded['description']?.toString().trim();
                  if (decoded['hls'] != null &&
                      decoded['hls'].toString().startsWith('http')) {
                    bestStreamUrl = decoded['hls'].toString();
                    badge = '1080p Adaptive HLS';
                    break;
                  }
                  if (decoded['formatStreams'] is List) {
                    for (final fs in (decoded['formatStreams'] as List)) {
                      if (fs is Map &&
                          fs['url'] != null &&
                          fs['url'].toString().startsWith('http')) {
                        bestStreamUrl = fs['url'].toString();
                        break;
                      }
                    }
                  }
                  if (bestStreamUrl != null) break;
                }
              }
            } catch (_) {}
          }
        }
      }

      if (ytTitle == null || ytDesc == null) {
        try {
          final oembedRes = await http
              .get(Uri.parse(
                  'https://www.youtube.com/oembed?url=${Uri.encodeComponent(trimmed)}&format=json'))
              .timeout(const Duration(seconds: 6));
          if (oembedRes.statusCode == 200) {
            final data = jsonDecode(utf8.decode(oembedRes.bodyBytes));
            if (data is Map) {
              ytTitle ??= data['title']?.toString().trim();
              ytAuthor ??= data['author_name']?.toString().trim();
            }
          }
        } catch (_) {}
      }

      return ImportedVideoSourceMetadata(
        title: ytTitle,
        originalDescription: ytDesc,
        authorName: ytAuthor,
        hdStreamUrl: bestStreamUrl,
        separateAudioStreamUrl: separateAudioUrl,
        sourceRawUrl: trimmed,
        qualityBadge: badge,
        isVerticalSource: isVertical,
        resolvedRealStream: bestStreamUrl != null,
      );
    }

    final bool isDirectLink = trimmed.startsWith('http');
    return ImportedVideoSourceMetadata(
      title: null,
      originalDescription: null,
      hdStreamUrl: isDirectLink ? trimmed : null,
      sourceRawUrl: trimmed,
      qualityBadge: '1080p HD',
      isVerticalSource: true,
      resolvedRealStream: isDirectLink,
    );
  }

  static String _cleanOriginalDescription(String? rawDesc, String fallbackTitle) {
    final String safeFallback = stripPlatformMentions(fallbackTitle);
    if (rawDesc == null || rawDesc.trim().isEmpty) {
      return safeFallback.isNotEmpty
          ? safeFallback
          : 'قصة مرئية هادئة وممتعة لأطفالنا الأبطال.';
    }
    String cleaned = rawDesc
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'#\S+'), '')
        .replaceAll(RegExp(r'\s{3,}'), '\n')
        .trim();
    cleaned = stripPlatformMentions(cleaned);
    return cleaned.isEmpty
        ? (safeFallback.isNotEmpty
            ? safeFallback
            : 'قصة مرئية هادئة وممتعة لأطفالنا الأبطال.')
        : cleaned;
  }

  static String _extractSmartRepeatPhraseFromContent(
      String title, String description, String category) {
    final String safeText = stripPlatformMentions('$title $description');
    final RegExp quotedMatch = RegExp(r'«([^»]{6,60})»|"([^"]{6,60})"');
    final m = quotedMatch.firstMatch(safeText);
    if (m != null) {
      final String extracted =
          stripPlatformMentions(m.group(1) ?? m.group(2) ?? '');
      if (extracted.isNotEmpty) {
        return '«$extracted»';
      }
    }

    final String cleanTitle = stripPlatformMentions(title)
        .replaceAll(RegExp(r'[#@|•\-_~]'), ' ')
        .trim();
    final List<String> titleWords =
        cleanTitle.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (titleWords.length >= 2 && titleWords.length <= 8) {
      return '«${titleWords.join(" ")}»';
    }

    switch (category) {
      case 'bedtime':
        return '«بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا، تُصْبِحُونَ عَلَى خَيْرٍ»';
      case 'arabic':
        return '«لُغَتِي العَرَبِيَّةُ جَمِيلَةٌ، وَأَنَا أَتَحَدَّثُ بِفَصَاحَةٍ»';
      case 'science':
        return '«سُبْحَانَ اللَّهِ الخَالِقِ العَظِيمِ، مَا أَجْمَلَ الطَّبِيعَةَ!»';
      case 'crafts':
        return '«أَنَا طِفْلٌ مُبْدِعٌ، أَصْنَعُ وَأَرْسُمُ بِيَدِي الجَمِيلَةِ»';
      default:
        return '«أَنَا بَطَلٌ مُؤَدَّبٌ، أُحِبُّ الخَيْرَ وَأُسَاعِدُ الجَمِيعَ»';
    }
  }

  static Map<String, dynamic> classifyAndGeneratePedagogicalMetadata({
    required String rawUrl,
    required ImportedVideoSourceMetadata sourceMeta,
  }) {
    final String rawTitle = stripPlatformMentions(sourceMeta.title?.trim() ?? '');
    final String rawDesc =
        stripPlatformMentions(sourceMeta.originalDescription?.trim() ?? '');
    final String combined = '$rawTitle $rawDesc'.toLowerCase();

    String category = 'habits';
    String ageGroup = '3–6 سنوات';
    String emoji = '🌟';
    String activeActivity = '';
    Color gradStart = const Color(0xFF1E1B4B);

    if (combined.contains('نوم') ||
        combined.contains('ليل') ||
        combined.contains('قمر') ||
        combined.contains('هادئ') ||
        combined.contains('sleep') ||
        combined.contains('bedtime') ||
        combined.contains('lullaby') ||
        combined.contains('moon')) {
      category = 'bedtime';
      ageGroup = '3–6 سنوات';
      emoji = '🌙';
      gradStart = const Color(0xFF1E1B4B);
      activeActivity =
          'خذ ٣ أنفاس عميقة وهادئة مع ماما أو بابا، وابتسم قبل إغماض عينيك للنوم الجميل.';
    } else if (combined.contains('حروف') ||
        combined.contains('عربي') ||
        combined.contains('نطق') ||
        combined.contains('قرآن') ||
        combined.contains('انشود') ||
        combined.contains('نشيد') ||
        combined.contains('كلمات') ||
        combined.contains('alphabet') ||
        combined.contains('arabic') ||
        combined.contains('learn')) {
      category = 'arabic';
      ageGroup = '2–6 سنوات';
      emoji = '🗣️';
      gradStart = const Color(0xFF312E81);
      activeActivity =
          'انطق ٣ كلمات عربية سمعتها في هذه القصة بصوت واضح أمام ماما أو بابا لتحصل على نجمة البطل!';
    } else if (combined.contains('حيوان') ||
        combined.contains('طبيع') ||
        combined.contains('بحر') ||
        combined.contains('فضاء') ||
        combined.contains('علوم') ||
        combined.contains('كيف') ||
        combined.contains('لماذا') ||
        combined.contains('animal') ||
        combined.contains('science') ||
        combined.contains('nature') ||
        combined.contains('space') ||
        combined.contains('dino')) {
      category = 'science';
      ageGroup = '4–8 سنوات';
      emoji = '🦋';
      gradStart = const Color(0xFF064E3B);
      activeActivity =
          'احكِ لماما أو بابا معلومة جديدة رأيتها في هذه القصة، وقلّد حركة الكائن اللطيف الذي ظهر فيها!';
    } else if (combined.contains('رسم') ||
        combined.contains('تلوين') ||
        combined.contains('اصنع') ||
        combined.contains('لعب') ||
        combined.contains('صلصال') ||
        combined.contains('رياضة') ||
        combined.contains('draw') ||
        combined.contains('craft') ||
        combined.contains('art') ||
        combined.contains('diy')) {
      category = 'crafts';
      ageGroup = '4–8 سنوات';
      emoji = '🎨';
      gradStart = const Color(0xFF78350F);
      activeActivity =
          'أحضر ورقة وألواناً أو مكعباتك الآن، وحاول رسم أو تقليد الشكل الجميل الذي شاهدته في القصة!';
    } else {
      category = 'habits';
      ageGroup = '3–6 سنوات';
      emoji = '🧸';
      gradStart = const Color(0xFF134E4A);
      activeActivity =
          'شارك ماما أو بابا أجمل فكرة تعلمتها من هذه القصة، ورتب ٣ أشياء في غرفتك بنشاط!';
    }

    String finalTitle = rawTitle
        .replaceAll(RegExp(r'#\S+'), '')
        .replaceAll('|', '—')
        .trim();
    if (finalTitle.isEmpty) {
      finalTitle = rawDesc.split('\n').first.trim();
    }
    finalTitle = stripPlatformMentions(finalTitle);
    if (finalTitle.length > 75) {
      finalTitle = '${finalTitle.substring(0, 72)}...';
    }
    if (finalTitle.isEmpty) {
      finalTitle = 'قصة حنين التربوية المصورة للأبطال';
    }

    final String exactOriginalDescription =
        _cleanOriginalDescription(rawDesc, finalTitle);

    final String repeatPhrase = _extractSmartRepeatPhraseFromContent(
      finalTitle,
      exactOriginalDescription,
      category,
    );

    final String smartFitMode =
        sourceMeta.isVerticalSource ? 'auto_cover' : 'contain';

    return {
      'title': finalTitle,
      'description': exactOriginalDescription,
      'category': category,
      'ageGroup': ageGroup,
      'repeatPhrase': repeatPhrase,
      'activeActivity': activeActivity,
      'emoji': emoji,
      'bgGradientStart': gradStart,
      'autoFitMode': smartFitMode,
      'qualityBadge': sourceMeta.qualityBadge,
    };
  }

  static Future<VideoModel?> autoImportAndGenerateFromUrl(
    String rawUrl, {
    String? preFetchedTitle,
    String? preFetchedDescription,
  }) async {
    final String cleanUrl = rawUrl.trim();
    final ImportedVideoSourceMetadata fetchedMeta =
        await fetchHighDefStreamAndExactMetadata(cleanUrl);

    final String? finalTitle = fetchedMeta.title ?? preFetchedTitle;
    final String? finalDesc =
        fetchedMeta.originalDescription ?? preFetchedDescription ?? finalTitle;

    if (fetchedMeta.hdStreamUrl == null &&
        !isYouTubeUrl(cleanUrl) &&
        !isTikTokUrl(cleanUrl)) {
      return null;
    }

    final ImportedVideoSourceMetadata mergedMeta = ImportedVideoSourceMetadata(
      title: finalTitle,
      originalDescription: finalDesc,
      authorName: fetchedMeta.authorName,
      hdStreamUrl: fetchedMeta.hdStreamUrl,
      separateAudioStreamUrl: fetchedMeta.separateAudioStreamUrl,
      sourceRawUrl: cleanUrl,
      qualityBadge: fetchedMeta.qualityBadge,
      isVerticalSource: fetchedMeta.isVerticalSource,
      resolvedRealStream: fetchedMeta.resolvedRealStream,
    );

    final Map<String, dynamic> meta =
        classifyAndGeneratePedagogicalMetadata(
      rawUrl: cleanUrl,
      sourceMeta: mergedMeta,
    );

    return VideoModel(
      id: 'v_auto_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      title: meta['title'] as String,
      description: meta['description'] as String,
      category: meta['category'] as String,
      ageGroup: meta['ageGroup'] as String,
      repeatPhrase: meta['repeatPhrase'] as String,
      activeActivity: meta['activeActivity'] as String,
      streamUrl: fetchedMeta.hdStreamUrl ?? cleanUrl,
      audioStreamUrl: fetchedMeta.separateAudioStreamUrl ?? '',
      originalSourceUrl: cleanUrl,
      bgGradientStart: meta['bgGradientStart'] as Color,
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: meta['emoji'] as String,
      autoFitMode: meta['autoFitMode'] as String,
      qualityBadge: meta['qualityBadge'] as String,
      likes: 150,
    );
  }

  static VideoModel _buildDeferredChannelVideoItem({
    required String watchUrl,
    required String rawTitle,
    required String rawDescription,
    required bool isVertical,
    required int indexOffset,
    String? directStreamUrl,
    String badge = '1080p Full HD',
  }) {
    final sourceMeta = ImportedVideoSourceMetadata(
      title: rawTitle,
      originalDescription: rawDescription.isNotEmpty ? rawDescription : rawTitle,
      hdStreamUrl: directStreamUrl,
      sourceRawUrl: watchUrl,
      qualityBadge: badge,
      isVerticalSource: isVertical,
      resolvedRealStream: directStreamUrl != null,
    );
    final meta = classifyAndGeneratePedagogicalMetadata(
      rawUrl: watchUrl,
      sourceMeta: sourceMeta,
    );
    return VideoModel(
      id: 'v_ch_${DateTime.now().millisecondsSinceEpoch}_$indexOffset',
      title: meta['title'] as String,
      description: meta['description'] as String,
      category: meta['category'] as String,
      ageGroup: meta['ageGroup'] as String,
      repeatPhrase: meta['repeatPhrase'] as String,
      activeActivity: meta['activeActivity'] as String,
      streamUrl: directStreamUrl ?? watchUrl,
      originalSourceUrl: watchUrl,
      bgGradientStart: meta['bgGradientStart'] as Color,
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: meta['emoji'] as String,
      autoFitMode: meta['autoFitMode'] as String,
      qualityBadge: badge,
      likes: 165 + indexOffset * 9,
    );
  }

  static Future<String?> _resolveYouTubeChannelIdFromAnyUrl(
      String channelUrl) async {
    final RegExp directUcRegex =
        RegExp(r'youtube\.com\/channel\/(UC[a-zA-Z0-9_-]{20,28})');
    final directMatch = directUcRegex.firstMatch(channelUrl);
    if (directMatch != null) return directMatch.group(1);

    String cleanUrl = channelUrl.split('?').first.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    final List<String> urlsToTry = [
      if (!cleanUrl.endsWith('/videos') && !cleanUrl.endsWith('/shorts'))
        '$cleanUrl/videos',
      cleanUrl,
    ];

    for (final u in urlsToTry) {
      try {
        final res = await http.get(
          Uri.parse(u),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
            'Cookie': 'CONSENT=YES+cb.20230531-07-p0.en+FX+999',
          },
        ).timeout(const Duration(seconds: 9));

        if (res.statusCode == 200) {
          final html = utf8.decode(res.bodyBytes, allowMalformed: true);
          final RegExp ucRegex = RegExp(
              r'(?:"externalId"|"channelId"|"browseId"|channel_id=)\s*[:=]?\s*"?(UC[a-zA-Z0-9_-]{20,28})"?');
          final m = ucRegex.firstMatch(html);
          if (m != null && m.groupCount >= 1) {
            return m.group(1);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<List<VideoModel>> _parseYouTubeXmlFeed(
    String feedUrl, {
    required int maxCount,
    bool resolveFirstStreamImmediately = true,
  }) async {
    final List<VideoModel> results = [];
    try {
      final res = await http.get(
        Uri.parse(feedUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 9));

      if (res.statusCode == 200) {
        final xml = utf8.decode(res.bodyBytes, allowMalformed: true);
        final RegExp entryRegex =
            RegExp(r'<entry>([\s\S]*?)<\/entry>', caseSensitive: false);
        final matches = entryRegex.allMatches(xml).take(maxCount).toList();

        for (int i = 0; i < matches.length; i++) {
          final String entryXml = matches[i].group(1)!;
          final vidMatch =
              RegExp(r'<yt:videoId>([^<]+)<\/yt:videoId>').firstMatch(entryXml);
          final titleMatch =
              RegExp(r'<title>([\s\S]*?)<\/title>').firstMatch(entryXml);
          final descMatch = RegExp(
                  r'<media:description>([\s\S]*?)<\/media:description>')
              .firstMatch(entryXml);

          if (vidMatch != null) {
            final String vidId = vidMatch.group(1)!.trim();
            final String title =
                _decodeHtmlEntities(titleMatch?.group(1) ?? '');
            final String desc = _decodeHtmlEntities(descMatch?.group(1) ?? '');
            final String watchUrl = 'https://www.youtube.com/watch?v=$vidId';

            if (i == 0 && resolveFirstStreamImmediately) {
              final resolved = await autoImportAndGenerateFromUrl(
                watchUrl,
                preFetchedTitle: title,
                preFetchedDescription: desc,
              );
              if (resolved != null) {
                results.add(resolved);
                continue;
              }
            }

            results.add(
              _buildDeferredChannelVideoItem(
                watchUrl: watchUrl,
                rawTitle: title,
                rawDescription: desc,
                isVertical: false,
                indexOffset: i,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return results;
  }

  static Future<List<VideoModel>> _scrapeTikTokProfilePageDirectly(
    String username, {
    required int maxVideosToImport,
  }) async {
    final List<VideoModel> scrapedList = [];
    final String cleanUser =
        username.startsWith('@') ? username.substring(1) : username;
    final String profileUrl = 'https://www.tiktok.com/@$cleanUser';

    try {
      final res = await http.get(
        Uri.parse(profileUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 9));

      if (res.statusCode == 200) {
        final String html = utf8.decode(res.bodyBytes, allowMalformed: true);
        final Set<String> discoveredVideoIds = {};

        final RegExp urlVidRegex =
            RegExp(r'\/@[a-zA-Z0-9_.-]+\/video\/(\d{15,22})');
        for (final m in urlVidRegex.allMatches(html)) {
          discoveredVideoIds.add(m.group(1)!);
          if (discoveredVideoIds.length >= maxVideosToImport) break;
        }

        if (discoveredVideoIds.isEmpty) {
          final RegExp itemIdRegex =
              RegExp(r'"(?:id|video_id|aweme_id)"\s*:\s*"(\d{18,20})"');
          for (final m in itemIdRegex.allMatches(html)) {
            discoveredVideoIds.add(m.group(1)!);
            if (discoveredVideoIds.length >= maxVideosToImport) break;
          }
        }

        final List<String> idList =
            discoveredVideoIds.take(maxVideosToImport).toList();
        for (int i = 0; i < idList.length; i++) {
          final String vidId = idList[i];
          final String videoUrl =
              'https://www.tiktok.com/@$cleanUser/video/$vidId';
          if (i == 0) {
            final firstResolved =
                await autoImportAndGenerateFromUrl(videoUrl);
            if (firstResolved != null) {
              scrapedList.add(firstResolved);
              continue;
            }
          }
          String? oembedTitle;
          try {
            final oRes = await http
                .get(Uri.parse(
                    'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(videoUrl)}'))
                .timeout(const Duration(seconds: 4));
            if (oRes.statusCode == 200) {
              final data = jsonDecode(utf8.decode(oRes.bodyBytes));
              if (data is Map) {
                oembedTitle = data['title']?.toString().trim();
              }
            }
          } catch (_) {}

          scrapedList.add(
            _buildDeferredChannelVideoItem(
              watchUrl: videoUrl,
              rawTitle: oembedTitle?.split('\n').first.trim() ??
                  'قصة تربوية ممتعة (${i + 1})',
              rawDescription: oembedTitle ?? '',
              isVertical: true,
              indexOffset: i,
            ),
          );
        }
      }
    } catch (_) {}

    return scrapedList;
  }

  static Future<List<VideoModel>> autoImportChannelOrPlaylistFromUrl(
    String rawUrl, {
    int maxVideosToImport = 8,
  }) async {
    final String trimmed = await _resolveRedirectUrlIfNeeded(rawUrl.trim());
    final List<VideoModel> importedList = [];

    final String? ttUsername = extractTikTokUsernameFromProfile(trimmed);
    if (ttUsername != null) {
      final String cleanUser =
          ttUsername.startsWith('@') ? ttUsername.substring(1) : ttUsername;
      String? resolvedSecUid;
      String? resolvedUserId;

      try {
        final infoRes = await http.post(
          Uri.parse('https://www.tikwm.com/api/user/info'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
          },
          body: {'unique_id': cleanUser},
        ).timeout(const Duration(seconds: 8));

        if (infoRes.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(infoRes.bodyBytes));
          if (decoded is Map &&
              decoded['data'] is Map &&
              (decoded['data'] as Map)['user'] is Map) {
            final userMap = (decoded['data'] as Map)['user'] as Map;
            resolvedSecUid = userMap['secUid']?.toString();
            resolvedUserId = userMap['id']?.toString();
          }
        }
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 1150));

      final List<Map<String, String>> postPayloads = [
        {
          'unique_id': cleanUser,
          if (resolvedSecUid != null && resolvedSecUid.isNotEmpty)
            'secUid': resolvedSecUid,
          if (resolvedUserId != null && resolvedUserId.isNotEmpty)
            'user_id': resolvedUserId,
          'count': '12',
          'cursor': '0',
          'hd': '1',
        },
        {
          'unique_id': '@$cleanUser',
          'count': '12',
          'cursor': '0',
          'hd': '1',
        },
      ];

      for (final bodyMap in postPayloads) {
        try {
          final postRes = await http.post(
            Uri.parse('https://www.tikwm.com/api/user/posts'),
            headers: {
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
            },
            body: bodyMap,
          ).timeout(const Duration(seconds: 12));

          if (postRes.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(postRes.bodyBytes));
            final extracted = _extractTikwmVideoListFromResponse(decoded);
            for (int i = 0;
                i < extracted.take(maxVideosToImport).length;
                i++) {
              final item = extracted[i];
              final String vidId = item['videoId'] ?? '';
              importedList.add(
                _buildDeferredChannelVideoItem(
                  watchUrl: vidId.isNotEmpty
                      ? 'https://www.tiktok.com/@$cleanUser/video/$vidId'
                      : trimmed,
                  rawTitle: item['title'] ?? '',
                  rawDescription: item['description'] ?? '',
                  isVertical: true,
                  indexOffset: i,
                  directStreamUrl: item['streamUrl'],
                  badge: item['badge'] ?? '1080p Full HD',
                ),
              );
            }
          }
        } catch (_) {}

        if (importedList.isNotEmpty) return importedList;
        await Future.delayed(const Duration(milliseconds: 1150));
      }

      try {
        final searchRes = await http.post(
          Uri.parse('https://www.tikwm.com/api/feed/search'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
          },
          body: {
            'keywords': cleanUser,
            'count': '12',
            'cursor': '0',
            'hd': '1',
          },
        ).timeout(const Duration(seconds: 11));

        if (searchRes.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(searchRes.bodyBytes));
          final extracted = _extractTikwmVideoListFromResponse(decoded);
          for (int i = 0; i < extracted.take(maxVideosToImport).length; i++) {
            final item = extracted[i];
            final String vidId = item['videoId'] ?? '';
            importedList.add(
              _buildDeferredChannelVideoItem(
                watchUrl: vidId.isNotEmpty
                    ? 'https://www.tiktok.com/@$cleanUser/video/$vidId'
                    : trimmed,
                rawTitle: item['title'] ?? '',
                rawDescription: item['description'] ?? '',
                isVertical: true,
                indexOffset: i,
                directStreamUrl: item['streamUrl'],
                badge: item['badge'] ?? '1080p Full HD',
              ),
            );
          }
        }
      } catch (_) {}

      if (importedList.isNotEmpty) return importedList;

      final scraped = await _scrapeTikTokProfilePageDirectly(
        cleanUser,
        maxVideosToImport: maxVideosToImport,
      );
      if (scraped.isNotEmpty) return scraped;
    }

    if (isYouTubeUrl(trimmed)) {
      final String? playlistId = extractYouTubePlaylistId(trimmed);

      if (playlistId != null) {
        final xmlItems = await _parseYouTubeXmlFeed(
          'https://www.youtube.com/feeds/videos.xml?playlist_id=$playlistId',
          maxCount: maxVideosToImport,
        );
        if (xmlItems.isNotEmpty) return xmlItems;

        final yt = yt_explode.YoutubeExplode();
        try {
          final videosStream = yt.playlists
              .getVideos(yt_explode.PlaylistId(playlistId))
              .take(maxVideosToImport);
          int idx = 0;
          await for (final v in videosStream) {
            if (idx == 0) {
              final resolved = await autoImportAndGenerateFromUrl(
                v.url,
                preFetchedTitle: v.title,
                preFetchedDescription: v.description,
              );
              if (resolved != null) {
                importedList.add(resolved);
                idx++;
                continue;
              }
            }
            importedList.add(
              _buildDeferredChannelVideoItem(
                watchUrl: v.url,
                rawTitle: v.title,
                rawDescription: v.description,
                isVertical: false,
                indexOffset: idx,
              ),
            );
            idx++;
          }
        } catch (_) {
        } finally {
          yt.close();
        }
        if (importedList.isNotEmpty) return importedList;
      }

      final String? channelId =
          await _resolveYouTubeChannelIdFromAnyUrl(trimmed);
      if (channelId != null) {
        final xmlItems = await _parseYouTubeXmlFeed(
          'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId',
          maxCount: maxVideosToImport,
        );
        if (xmlItems.isNotEmpty) return xmlItems;

        final yt = yt_explode.YoutubeExplode();
        try {
          final uploads = await yt.channels
              .getUploads(yt_explode.ChannelId(channelId))
              .take(maxVideosToImport)
              .toList()
              .timeout(const Duration(seconds: 12));
          for (int i = 0; i < uploads.length; i++) {
            final v = uploads[i];
            if (i == 0) {
              final resolved = await autoImportAndGenerateFromUrl(
                v.url,
                preFetchedTitle: v.title,
                preFetchedDescription: v.description,
              );
              if (resolved != null) {
                importedList.add(resolved);
                continue;
              }
            }
            importedList.add(
              _buildDeferredChannelVideoItem(
                watchUrl: v.url,
                rawTitle: v.title,
                rawDescription: v.description,
                isVertical: false,
                indexOffset: i,
              ),
            );
          }
        } catch (_) {
        } finally {
          yt.close();
        }
        if (importedList.isNotEmpty) return importedList;
      }

      try {
        String scrapeUrl = trimmed.split('?').first;
        if (!scrapeUrl.endsWith('/videos') &&
            !scrapeUrl.endsWith('/shorts') &&
            !scrapeUrl.contains('watch')) {
          scrapeUrl = '$scrapeUrl/videos';
        }
        final pageRes = await http.get(
          Uri.parse(scrapeUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
            'Accept-Language': 'ar,en;q=0.9',
            'Cookie': 'CONSENT=YES+cb.20230531-07-p0.en+FX+999',
          },
        ).timeout(const Duration(seconds: 9));

        if (pageRes.statusCode == 200) {
          final html = utf8.decode(pageRes.bodyBytes, allowMalformed: true);
          final RegExp vidMatches = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"');
          final List<String> ids = [];
          for (final m in vidMatches.allMatches(html)) {
            final String id = m.group(1)!;
            if (!ids.contains(id)) {
              ids.add(id);
              if (ids.length >= maxVideosToImport) break;
            }
          }
          for (int i = 0; i < ids.length; i++) {
            final String watchUrl = 'https://www.youtube.com/watch?v=${ids[i]}';
            if (i == 0) {
              final firstResolved =
                  await autoImportAndGenerateFromUrl(watchUrl);
              if (firstResolved != null) {
                importedList.add(firstResolved);
                continue;
              }
            }
            String? quickTitle;
            try {
              final oembedRes = await http
                  .get(Uri.parse(
                      'https://www.youtube.com/oembed?url=${Uri.encodeComponent(watchUrl)}&format=json'))
                  .timeout(const Duration(seconds: 4));
              if (oembedRes.statusCode == 200) {
                final data = jsonDecode(utf8.decode(oembedRes.bodyBytes));
                if (data is Map) {
                  quickTitle = data['title']?.toString().trim();
                }
              }
            } catch (_) {}
            importedList.add(
              _buildDeferredChannelVideoItem(
                watchUrl: watchUrl,
                rawTitle: quickTitle ?? 'قصة تربوية ممتعة (${i + 1})',
                rawDescription: quickTitle ?? '',
                isVertical: scrapeUrl.endsWith('/shorts'),
                indexOffset: i,
              ),
            );
          }
        }
      } catch (_) {}

      if (importedList.isNotEmpty) return importedList;
    }

    final single = await autoImportAndGenerateFromUrl(trimmed);
    if (single != null) {
      importedList.add(single);
    }
    return importedList;
  }
}

class VideoModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String ageGroup;
  final String repeatPhrase;
  final String activeActivity;
  String streamUrl;
  String audioStreamUrl;
  final String originalSourceUrl;
  final Color bgGradientStart;
  final Color bgGradientEnd;
  final String emoji;
  String autoFitMode;
  String qualityBadge;
  int likes;
  bool isLiked;

  VideoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.ageGroup,
    required this.repeatPhrase,
    required this.activeActivity,
    required this.streamUrl,
    this.audioStreamUrl = '',
    this.originalSourceUrl = '',
    this.bgGradientStart = const Color(0xFF1E1B4B),
    this.bgGradientEnd = const Color(0xFF0F172A),
    this.emoji = '🌟',
    this.autoFitMode = 'auto_cover',
    this.qualityBadge = '1080p HD',
    this.likes = 120,
    this.isLiked = false,
  });

  static Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    String cleaned = hex.trim().replaceAll('#', '');
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    final int? val = int.tryParse(cleaned, radix: 16);
    return val != null ? Color(val) : fallback;
  }

  static String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  static String getCategoryDisplayLabel(String categoryKey) {
    switch (categoryKey) {
      case 'bedtime':
        return '🌙 قصص النوم';
      case 'habits':
        return '🧸 سلوكياتي';
      case 'arabic':
        return '🗣️ فصاحة ونطق';
      case 'science':
        return '🦋 لماذا وكيف؟';
      case 'crafts':
        return '🎨 افعلها بيدك';
      default:
        return categoryKey.isNotEmpty ? categoryKey : '✨ قصة تفاعلية';
    }
  }

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    final String rawCategory =
        (json['category'] ?? json['playlistId'] ?? 'bedtime').toString();
    return VideoModel(
      id: (json['id'] ?? 'v_${DateTime.now().millisecondsSinceEpoch}')
          .toString(),
      title: (json['title'] ?? 'قصة جديدة').toString(),
      description: (json['description'] ?? json['subtitle'] ?? '').toString(),
      category: rawCategory,
      ageGroup:
          (json['ageGroup'] ?? json['ageRange'] ?? '3–6 سنوات').toString(),
      repeatPhrase: (json['repeatPhrase'] ??
              json['interactivePhrase'] ??
              '«أَنَا طِفْلٌ ذَكِيٌّ وَهَادِئٌ»')
          .toString(),
      activeActivity: (json['activeActivity'] ??
              json['offlineActivity'] ??
              'شارك ما تعلمته اليوم مع ماما أو بابا!')
          .toString(),
      streamUrl: (json['streamUrl'] ?? json['hlsStreamUrl'] ?? '').toString(),
      audioStreamUrl: (json['audioStreamUrl'] ?? '').toString(),
      originalSourceUrl: (json['originalSourceUrl'] ?? '').toString(),
      bgGradientStart: _parseHexColor(
          json['bgGradientStart']?.toString(), const Color(0xFF1E1B4B)),
      bgGradientEnd: _parseHexColor(
          json['bgGradientEnd']?.toString(), const Color(0xFF0F172A)),
      emoji: (json['emoji'] ?? '🌟').toString(),
      autoFitMode: (json['autoFitMode'] ?? 'auto_cover').toString(),
      qualityBadge: (json['qualityBadge'] ?? '1080p HD').toString(),
      likes: int.tryParse(json['likes']?.toString() ?? '120') ?? 120,
      isLiked: json['isLiked'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'ageGroup': ageGroup,
      'repeatPhrase': repeatPhrase,
      'activeActivity': activeActivity,
      'streamUrl': streamUrl,
      'audioStreamUrl': audioStreamUrl,
      'originalSourceUrl': originalSourceUrl,
      'playlistId': category,
      'categoryLabel': getCategoryDisplayLabel(category),
      'ageRange': ageGroup,
      'subtitle': description,
      'interactivePhrase': repeatPhrase,
      'offlineActivity': activeActivity,
      'bgGradientStart': _colorToHex(bgGradientStart),
      'bgGradientEnd': _colorToHex(bgGradientEnd),
      'emoji': emoji,
      'autoFitMode': autoFitMode,
      'qualityBadge': qualityBadge,
      'likes': likes,
      'isLiked': isLiked,
    };
  }
}

class ChildActivityLogEntry {
  final String timestampIso;
  final String actionTitle;
  final String categoryBadge;

  const ChildActivityLogEntry({
    required this.timestampIso,
    required this.actionTitle,
    required this.categoryBadge,
  });

  factory ChildActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ChildActivityLogEntry(
      timestampIso: (json['timestampIso'] ?? DateTime.now().toIso8601String())
          .toString(),
      actionTitle: (json['actionTitle'] ?? '').toString(),
      categoryBadge: (json['categoryBadge'] ?? 'نشاط').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestampIso': timestampIso,
      'actionTitle': actionTitle,
      'categoryBadge': categoryBadge,
    };
  }
}

class ChildProfile {
  final String id;
  String name;
  String age;
  int dailyTimeLimit;
  int starsEarned;
  String chosenAvatar;
  int usedMinutesToday;
  int watchedVideosToday;
  int correctPronunciationsCount;
  int intelligencePoints;
  int gamesCompletedCount;
  bool isDeviceRemotelyLocked;
  String remoteLockReasonMessage;
  String currentLiveStatus;
  String familyPairingCode;
  List<String> completedActivities;
  List<String> likedVideoIds;
  List<ChildActivityLogEntry> liveActivityTimeline;

  ChildProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.dailyTimeLimit,
    this.starsEarned = 0,
    required this.chosenAvatar,
    this.usedMinutesToday = 0,
    this.watchedVideosToday = 0,
    this.correctPronunciationsCount = 0,
    this.intelligencePoints = 10,
    this.gamesCompletedCount = 0,
    this.isDeviceRemotelyLocked = false,
    this.remoteLockReasonMessage =
        'تم قفل شاشة التطبيق الآن من هاتف ولي الأمر. حان وقت الراحة أو اللعب الواقعي يا بطل!',
    this.currentLiveStatus = 'متصل — يتصفح قصص حنين الهادئة',
    this.familyPairingCode = 'HK-8824',
    List<String>? completedActivities,
    List<String>? likedVideoIds,
    List<ChildActivityLogEntry>? liveActivityTimeline,
  })  : completedActivities = completedActivities ?? [],
        likedVideoIds = likedVideoIds ?? [],
        liveActivityTimeline = liveActivityTimeline ??
            [
              ChildActivityLogEntry(
                timestampIso: DateTime.now().toIso8601String(),
                actionTitle: 'بدأ جلسة المشاهدة الهادئة على التطبيق',
                categoryBadge: 'جلسة مباشرة',
              ),
            ];

  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    return ChildProfile(
      id: (json['id'] ?? 'child_${DateTime.now().millisecondsSinceEpoch}')
          .toString(),
      name: (json['name'] ?? 'فارس').toString(),
      age: (json['age'] ?? json['ageGroup'] ?? '3–6 سنوات').toString(),
      dailyTimeLimit: int.tryParse(
              (json['dailyTimeLimit'] ?? json['dailyQuota'] ?? '20')
                  .toString()) ??
          20,
      starsEarned: int.tryParse(json['starsEarned']?.toString() ?? '0') ?? 0,
      chosenAvatar:
          (json['chosenAvatar'] ?? json['avatarEmoji'] ?? '🦁').toString(),
      usedMinutesToday:
          int.tryParse(json['usedMinutesToday']?.toString() ?? '0') ?? 0,
      watchedVideosToday: int.tryParse(
              (json['watchedVideosToday'] ?? json['watchedToday'] ?? '0')
                  .toString()) ??
          0,
      correctPronunciationsCount: int.tryParse(
              json['correctPronunciationsCount']?.toString() ?? '0') ??
          0,
      intelligencePoints: int.tryParse(
              json['intelligencePoints']?.toString() ?? '10') ??
          10,
      gamesCompletedCount: int.tryParse(
              json['gamesCompletedCount']?.toString() ?? '0') ??
          0,
      isDeviceRemotelyLocked: json['isDeviceRemotelyLocked'] == true,
      remoteLockReasonMessage: (json['remoteLockReasonMessage'] ??
              'تم قفل شاشة التطبيق الآن من هاتف ولي الأمر. حان وقت الراحة يا بطل!')
          .toString(),
      currentLiveStatus:
          (json['currentLiveStatus'] ?? 'متصل — يشاهد القصص الهادئة')
              .toString(),
      familyPairingCode: (json['familyPairingCode'] ?? 'HK-8824').toString(),
      completedActivities: (json['completedActivities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      likedVideoIds: (json['likedVideoIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      liveActivityTimeline: (json['liveActivityTimeline'] as List<dynamic>?)
              ?.map((e) => ChildActivityLogEntry.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'dailyTimeLimit': dailyTimeLimit,
      'starsEarned': starsEarned,
      'chosenAvatar': chosenAvatar,
      'usedMinutesToday': usedMinutesToday,
      'watchedVideosToday': watchedVideosToday,
      'correctPronunciationsCount': correctPronunciationsCount,
      'intelligencePoints': intelligencePoints,
      'gamesCompletedCount': gamesCompletedCount,
      'isDeviceRemotelyLocked': isDeviceRemotelyLocked,
      'remoteLockReasonMessage': remoteLockReasonMessage,
      'currentLiveStatus': currentLiveStatus,
      'familyPairingCode': familyPairingCode,
      'completedActivities': completedActivities,
      'likedVideoIds': likedVideoIds,
      'liveActivityTimeline':
          liveActivityTimeline.map((e) => e.toJson()).toList(),
    };
  }
}

class SubscriptionPlanModel {
  final String id;
  final String title;
  final String badge;
  final String subtitle;
  final int priceEgp;
  final int originalPriceEgp;
  final int durationDays;
  final List<String> features;
  final Color accentColor;
  final bool isPopular;

  const SubscriptionPlanModel({
    required this.id,
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.priceEgp,
    required this.originalPriceEgp,
    required this.durationDays,
    required this.features,
    required this.accentColor,
    this.isPopular = false,
  });
}

const List<SubscriptionPlanModel> kSubscriptionPlans = [
  SubscriptionPlanModel(
    id: 'trial_1day',
    title: 'التجربة المجانية (٢٤ ساعة)',
    badge: 'مجاني لمدة يوم كامل 🎁',
    subtitle: 'استكشف جميع القصص والميزات الصوتية الذكية مجاناً لمدة ٢٤ ساعة',
    priceEgp: 0,
    originalPriceEgp: 0,
    durationDays: 1,
    features: [
      'فتح جميع القصص الهادئة لمدة ٢٤ ساعة كاملة',
      'تجربة المصحح الصوتي الذكي في نافذة «ردد معي»',
      'تجربة المساعد الصوتي الذكي للطفل (رفيق حنين)',
      'تقارير وتنبيهات البريد الإلكتروني للوالدين',
    ],
    accentColor: Color(0xFF38BDF8),
  ),
  SubscriptionPlanModel(
    id: 'weekly_flex',
    title: 'باقة الأسبوع المرنة',
    badge: 'مرونة عالية ⚡',
    subtitle: 'مثالية للإجازات الأسبوعية والتجربة السريعة بدون التزام طويل',
    priceEgp: 45,
    originalPriceEgp: 65,
    durationDays: 7,
    features: [
      'مشاهدة غير محدودة لجميع الأقسام لمدة ٧ أيام',
      'تفعيل كامل للمساعد الصوتي وتصحيح النطق العربي',
      'إضافة حتى ٣ ملفات أطفال مستقلة',
      'تقارير يومية واقتراحات تربوية على إيميل الوالدين',
    ],
    accentColor: Color(0xFF14B8A6),
  ),
  SubscriptionPlanModel(
    id: 'monthly_family',
    title: 'الباقة الشهرية الذكية',
    badge: 'الأكثر اختياراً في مصر ⭐',
    subtitle: 'الخيار المفضل للعائلات لمتابعة يومية هادئة وتطوير النطق والسلوك',
    priceEgp: 120,
    originalPriceEgp: 180,
    durationDays: 30,
    isPopular: true,
    features: [
      'فتح كافة القصص والتحديثات السحابية طوال الشهر',
      'إضافة حتى ٥ ملفات أطفال مع تقارير أداء مفصلة',
      'المساعد الذكي الصوتي التفاعلي وتصحيح مخارج الحروف',
      'تنبيهات بريدية ذكية واقتراحات مخصصة لكل طفل',
      'أولوية الدعم الفني وإمكانية الإلغاء في أي وقت',
    ],
    accentColor: Color(0xFFF59E0B),
  ),
  SubscriptionPlanModel(
    id: 'quarterly_plus',
    title: 'باقة الـ ٣ شهور التوفيرية',
    badge: 'وفّر ٣٥٪ 💎',
    subtitle: 'خطة فصلية متكاملة لبناء عادات القراءة والنطق الفصيح والهدوء',
    priceEgp: 280,
    originalPriceEgp: 430,
    durationDays: 90,
    features: [
      'جميع مميزات الباقة الشهرية لمدة ٩٠ يوماً كاملة',
      'برامج نطق وفصاحة متدرجة مع المساعد الصوتي',
      'تقارير شهرية وأسبوعية شاملة عبر الإيميل للوالدين',
      'إمكانية تخصيص مكتبة قصص خاصة لكل طفل',
    ],
    accentColor: Color(0xFFA855F7),
  ),
  SubscriptionPlanModel(
    id: 'annual_vip',
    title: 'باقة العائلة السنوية VIP',
    badge: 'أفضل قيمة — وفّر ٥٥٪ 👑',
    subtitle: 'استثمار تربوي كامل لعام كامل من القصص الهادئة والأنشطة الواقعية',
    priceEgp: 799,
    originalPriceEgp: 1800,
    durationDays: 365,
    features: [
      'اشتراك كامل لمدة ٣٦٥ يوماً لكل أطفال العائلة بلا حدود',
      'تفعيل دائم للمساعد الذكي الصوتي ومصحح النطق العربي',
      'تنبيهات فورية على الإيميل واقتراحات تربوية ذكية يومية',
      'وصول مبكر لجميع السلاسل والقصص التربوية الجديدة',
      'هدية شهر إضافي مجاني عند التجديد',
    ],
    accentColor: Color(0xFFEC4899),
  ),
];

class EgyptianPaymentMethodInfo {
  final String id;
  final String nameAr;
  final String subtitleAr;
  final String badgeText;
  final Color brandColor;
  final IconData icon;
  final String merchantAccountNumber;

  const EgyptianPaymentMethodInfo({
    required this.id,
    required this.nameAr,
    required this.subtitleAr,
    required this.badgeText,
    required this.brandColor,
    required this.icon,
    required this.merchantAccountNumber,
  });
}

const List<EgyptianPaymentMethodInfo> kEgyptianPaymentMethods = [
  EgyptianPaymentMethodInfo(
    id: 'vodafone_cash',
    nameAr: 'فودافون كاش (Vodafone Cash)',
    subtitleAr: 'الدفع الفوري عبر محفظة فودافون كاش (*9*7#)',
    badgeText: 'الأسرع في مصر',
    brandColor: Color(0xFFE60000),
    icon: Icons.phone_android_rounded,
    merchantAccountNumber: '0100-888-9922',
  ),
  EgyptianPaymentMethodInfo(
    id: 'instapay',
    nameAr: 'إنستا باي (InstaPay Egypt)',
    subtitleAr: 'تحويل لحظي عبر عنوان الدفع IPA أو رقم الهاتف البنكي',
    badgeText: 'تحويل لحظي مجاني',
    brandColor: Color(0xFF7C3AED),
    icon: Icons.account_balance_rounded,
    merchantAccountNumber: 'haneenkids@instapay',
  ),
  EgyptianPaymentMethodInfo(
    id: 'orange_cash',
    nameAr: 'أورنج كاش (Orange Cash)',
    subtitleAr: 'الدفع السريع عبر محفظة أورنج كاش (#7115#)',
    badgeText: 'محفظة أورنج',
    brandColor: Color(0xFFFF7900),
    icon: Icons.smartphone_rounded,
    merchantAccountNumber: '0122-555-7744',
  ),
  EgyptianPaymentMethodInfo(
    id: 'etisalat_cash',
    nameAr: 'اتصالات كاش (e& money / Etisalat Cash)',
    subtitleAr: 'الدفع المباشر عبر محفظة اتصالات كاش (*777#)',
    badgeText: 'محفظة e& money',
    brandColor: Color(0xFF10B981),
    icon: Icons.mobile_friendly_rounded,
    merchantAccountNumber: '0111-333-8855',
  ),
  EgyptianPaymentMethodInfo(
    id: 'visa_mastercard',
    nameAr: 'بطاقة بنكية (فيزا / ماستركارد / ميزة)',
    subtitleAr: 'دفع آمن بالبطاقات البنكية المصرية وبطاقات ميزة الوطنية',
    badgeText: 'Visa / Meeza',
    brandColor: Color(0xFF2563EB),
    icon: Icons.credit_card_rounded,
    merchantAccountNumber: 'بوابة الدفع الإلكتروني المؤمنة 3D-Secure',
  ),
];

class PaymentTransactionRecord {
  final String id;
  final String planId;
  final String planTitle;
  final int amountEgp;
  final String paymentMethodId;
  final String paymentMethodName;
  final String payerIdentifier;
  final String referenceCode;
  final String status;
  final String failureReason;
  final DateTime createdAt;

  PaymentTransactionRecord({
    required this.id,
    required this.planId,
    required this.planTitle,
    required this.amountEgp,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.payerIdentifier,
    required this.referenceCode,
    this.status = 'verified',
    this.failureReason = '',
    required this.createdAt,
  });

  bool get isVerified => status == 'verified';

  factory PaymentTransactionRecord.fromJson(Map<String, dynamic> json) {
    return PaymentTransactionRecord(
      id: (json['id'] ?? '').toString(),
      planId: (json['planId'] ?? '').toString(),
      planTitle: (json['planTitle'] ?? '').toString(),
      amountEgp: int.tryParse(json['amountEgp']?.toString() ?? '0') ?? 0,
      paymentMethodId: (json['paymentMethodId'] ?? '').toString(),
      paymentMethodName: (json['paymentMethodName'] ?? '').toString(),
      payerIdentifier: (json['payerIdentifier'] ?? '').toString(),
      referenceCode: (json['referenceCode'] ?? '').toString(),
      status: (json['status'] ?? 'verified').toString(),
      failureReason: (json['failureReason'] ?? '').toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'planId': planId,
      'planTitle': planTitle,
      'amountEgp': amountEgp,
      'paymentMethodId': paymentMethodId,
      'paymentMethodName': paymentMethodName,
      'payerIdentifier': payerIdentifier,
      'referenceCode': referenceCode,
      'status': status,
      'failureReason': failureReason,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class PaymentVerificationOutcome {
  final bool isPaidAndVerified;
  final String message;
  final PaymentTransactionRecord? transaction;

  const PaymentVerificationOutcome({
    required this.isPaidAndVerified,
    required this.message,
    this.transaction,
  });
}

class StrictEgyptianPaymentValidator {
  static String? validateWalletPrefix(String methodId, String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s+|-'), '');
    if (!RegExp(r'^\d{11}$').hasMatch(cleaned)) {
      return 'رقم المحفظة يجب أن يتكون من ١١ رقماً بالضبط (مثال: 01012345678).';
    }
    if (methodId == 'vodafone_cash' && !cleaned.startsWith('010')) {
      return 'رقم محفظة فودافون كاش يجب أن يبدأ بـ 010.';
    }
    if (methodId == 'orange_cash' && !cleaned.startsWith('012')) {
      return 'رقم محفظة أورنج كاش يجب أن يبدأ بـ 012.';
    }
    if (methodId == 'etisalat_cash' && !cleaned.startsWith('011')) {
      return 'رقم محفظة اتصالات كاش (e& money) يجب أن يبدأ بـ 011.';
    }
    return null;
  }

  static String? validateInstaPayIdentifier(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) {
      return 'يرجى إدخال عنوان الدفع اللحظي (IPA مثل name@instapay) أو رقم الهاتف البنكي (١١ رقماً).';
    }
    final bool isIpa = cleaned.contains('@') && cleaned.length >= 6;
    final bool isPhone =
        RegExp(r'^01[0125]\d{8}$').hasMatch(cleaned.replaceAll(' ', ''));
    if (!isIpa && !isPhone) {
      return 'صيغة إنستا باي غير صحيحة: أدخل عنوان IPA يحتوي على @ أو رقم هاتف مصري مكون من ١١ رقماً.';
    }
    return null;
  }

  static bool checkLuhnCardNumber(String cardNumber) {
    final cleaned = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length != 16) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = cleaned.length - 1; i >= 0; i--) {
      int n = int.parse(cleaned[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  static String? validateBankCard({
    required String cardNumber,
    required String expiry,
    required String cvv,
    required String cardHolderName,
  }) {
    if (cardHolderName.trim().length < 4) {
      return 'يرجى إدخال اسم حامل البطاقة ثلاثياً أو ثنائياً كما هو مطبوع على البطاقة.';
    }
    final cleanedNum = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanedNum.length != 16) {
      return 'رقم البطاقة البنكية (فيزا / ماستركارد / ميزة) يجب أن يتكون من ١٦ رقماً.';
    }
    if (!checkLuhnCardNumber(cleanedNum)) {
      return 'رقم البطاقة البنكية غير صالح (فشل التحقق الرقمي Luhn Check). تأكد من الأرقام الصحيحة.';
    }
    final expMatch = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(expiry.trim());
    if (expMatch == null) {
      return 'تاريخ انتهاء البطاقة يجب أن يكون بصيغة MM/YY (مثال: 08/28).';
    }
    final int month = int.tryParse(expMatch.group(1)!) ?? 0;
    final int year = 2000 + (int.tryParse(expMatch.group(2)!) ?? 0);
    if (month < 1 || month > 12) {
      return 'شهر انتهاء البطاقة غير صحيح (يجب أن يكون بين 01 و 12).';
    }
    final now = DateTime.now();
    if (year < now.year || (year == now.year && month < now.month)) {
      return 'هذه البطاقة منتهية الصلاحية ولا يمكن الخصم منها.';
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(cvv.trim())) {
      return 'رمز الأمان الخلفي (CVV) يجب أن يتكون من ٣ أو ٤ أرقام.';
    }
    return null;
  }
}

class ParentEmailAlertItem {
  final String id;
  final String recipientEmail;
  final String subject;
  final String bodyMessage;
  final String smartImprovementSuggestion;
  final DateTime sentAt;
  final bool deliveredToCloud;

  ParentEmailAlertItem({
    required this.id,
    required this.recipientEmail,
    required this.subject,
    required this.bodyMessage,
    required this.smartImprovementSuggestion,
    required this.sentAt,
    this.deliveredToCloud = true,
  });

  factory ParentEmailAlertItem.fromJson(Map<String, dynamic> json) {
    return ParentEmailAlertItem(
      id: (json['id'] ?? '').toString(),
      recipientEmail: (json['recipientEmail'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      bodyMessage: (json['bodyMessage'] ?? '').toString(),
      smartImprovementSuggestion:
          (json['smartImprovementSuggestion'] ?? '').toString(),
      sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ??
          DateTime.now(),
      deliveredToCloud: json['deliveredToCloud'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recipientEmail': recipientEmail,
      'subject': subject,
      'bodyMessage': bodyMessage,
      'smartImprovementSuggestion': smartImprovementSuggestion,
      'sentAt': sentAt.toIso8601String(),
      'deliveredToCloud': deliveredToCloud,
    };
  }
}

class ParentAccount {
  String fullName;
  String emailOrPhone;
  String password;
  String parentalPin;
  String authProvider;
  bool warmEveningFilter;
  bool emailNotificationsEnabled;
  bool dailySmartSuggestionsEnabled;
  bool voiceAssistantEnabled;
  String subscriptionPlanId;
  DateTime trialStartDate;
  DateTime subscriptionExpiryDate;
  List<ChildProfile> children;
  String activeChildId;
  List<PaymentTransactionRecord> paymentHistory;
  List<ParentEmailAlertItem> emailAlertsLog;

  ParentAccount({
    required this.fullName,
    required this.emailOrPhone,
    required this.password,
    this.parentalPin = '1234',
    this.authProvider = 'email',
    this.warmEveningFilter = false,
    this.emailNotificationsEnabled = true,
    this.dailySmartSuggestionsEnabled = true,
    this.voiceAssistantEnabled = true,
    this.subscriptionPlanId = 'trial_1day',
    DateTime? trialStartDate,
    DateTime? subscriptionExpiryDate,
    required this.children,
    required this.activeChildId,
    List<PaymentTransactionRecord>? paymentHistory,
    List<ParentEmailAlertItem>? emailAlertsLog,
  })  : trialStartDate = trialStartDate ?? DateTime.now(),
        subscriptionExpiryDate = subscriptionExpiryDate ??
            DateTime.now().add(const Duration(hours: 24)),
        paymentHistory = paymentHistory ?? [],
        emailAlertsLog = emailAlertsLog ?? [];

  ChildProfile get activeChild {
    if (children.isEmpty) {
      final defaultChild = ChildProfile(
        id: 'c_default',
        name: 'فارس',
        age: '3–6 سنوات',
        dailyTimeLimit: 20,
        chosenAvatar: '🦁',
      );
      children.add(defaultChild);
      activeChildId = defaultChild.id;
    }
    return children.firstWhere(
      (c) => c.id == activeChildId,
      orElse: () => children.first,
    );
  }

  bool get isTrialPlan => subscriptionPlanId == 'trial_1day';

  bool get isSubscriptionActive =>
      DateTime.now().isBefore(subscriptionExpiryDate);

  Duration get remainingSubscriptionDuration {
    final diff = subscriptionExpiryDate.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get subscriptionStatusLabel {
    if (!isSubscriptionActive) {
      return 'انتهت الفترة التجريبية (يرجى اختيار باقة لتجديد الاشتراك)';
    }
    final rem = remainingSubscriptionDuration;
    if (isTrialPlan) {
      final int hours = rem.inHours;
      final int mins = rem.inMinutes.remainder(60);
      return 'فترة تجريبية مجانية (متبقي $hours ساعة و $mins دقيقة)';
    }
    final plan = kSubscriptionPlans.firstWhere(
      (p) => p.id == subscriptionPlanId,
      orElse: () => kSubscriptionPlans[2],
    );
    return '${plan.title} — سارية (${rem.inDays + 1} يوم متبقي)';
  }

  factory ParentAccount.fromJson(Map<String, dynamic> json) {
    final childrenList = (json['children'] as List<dynamic>?)
            ?.map((c) =>
                ChildProfile.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList() ??
        [
          ChildProfile(
            id: 'c1',
            name: 'فارس',
            age: '3–6 سنوات',
            dailyTimeLimit: 20,
            chosenAvatar: '🦁',
          ),
        ];

    final payments = (json['paymentHistory'] as List<dynamic>?)
            ?.map((p) => PaymentTransactionRecord.fromJson(
                Map<String, dynamic>.from(p as Map)))
            .toList() ??
        [];

    final alerts = (json['emailAlertsLog'] as List<dynamic>?)
            ?.map((a) => ParentEmailAlertItem.fromJson(
                Map<String, dynamic>.from(a as Map)))
            .toList() ??
        [];

    final DateTime parsedTrialStart =
        DateTime.tryParse(json['trialStartDate']?.toString() ?? '') ??
            DateTime.now();
    final DateTime parsedExpiry =
        DateTime.tryParse(json['subscriptionExpiryDate']?.toString() ?? '') ??
            parsedTrialStart.add(const Duration(hours: 24));

    return ParentAccount(
      fullName: (json['fullName'] ?? 'ولي الأمر').toString(),
      emailOrPhone: (json['emailOrPhone'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      parentalPin: (json['parentalPin'] ?? '1234').toString(),
      authProvider: (json['authProvider'] ?? 'email').toString(),
      warmEveningFilter:
          json['warmEveningFilter'] == true || json['bedtimeDimming'] == true,
      emailNotificationsEnabled: json['emailNotificationsEnabled'] != false,
      dailySmartSuggestionsEnabled:
          json['dailySmartSuggestionsEnabled'] != false,
      voiceAssistantEnabled: json['voiceAssistantEnabled'] != false,
      subscriptionPlanId:
          (json['subscriptionPlanId'] ?? 'trial_1day').toString(),
      trialStartDate: parsedTrialStart,
      subscriptionExpiryDate: parsedExpiry,
      children: childrenList,
      activeChildId:
          (json['activeChildId'] ?? childrenList.first.id).toString(),
      paymentHistory: payments,
      emailAlertsLog: alerts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'emailOrPhone': emailOrPhone,
      'password': password,
      'parentalPin': parentalPin,
      'authProvider': authProvider,
      'warmEveningFilter': warmEveningFilter,
      'emailNotificationsEnabled': emailNotificationsEnabled,
      'dailySmartSuggestionsEnabled': dailySmartSuggestionsEnabled,
      'voiceAssistantEnabled': voiceAssistantEnabled,
      'subscriptionPlanId': subscriptionPlanId,
      'trialStartDate': trialStartDate.toIso8601String(),
      'subscriptionExpiryDate': subscriptionExpiryDate.toIso8601String(),
      'children': children.map((c) => c.toJson()).toList(),
      'activeChildId': activeChildId,
      'paymentHistory': paymentHistory.map((p) => p.toJson()).toList(),
      'emailAlertsLog': emailAlertsLog.map((a) => a.toJson()).toList(),
    };
  }
}

const List<Map<String, String>> kVideoCategories = [
  {'id': 'all', 'title': 'كل القصص', 'icon': '✨'},
  {'id': 'bedtime', 'title': 'قصص النوم', 'icon': '🌙'},
  {'id': 'habits', 'title': 'سلوكياتي', 'icon': '🧸'},
  {'id': 'arabic', 'title': 'فصاحة ونطق', 'icon': '🗣️'},
  {'id': 'science', 'title': 'لماذا وكيف؟', 'icon': '🦋'},
  {'id': 'crafts', 'title': 'افعلها بيدك', 'icon': '🎨'},
];

List<VideoModel> getDefaultVideos() {
  return [
    VideoModel(
      id: 'v1',
      title: 'فارس ونور يراقبان الهلال المبتسم',
      description:
          '«في المساء الهادئ، جلس فارس وأخته نور قرب النافذة يتأملان الهلال المبتسم في السماء الصافية...»',
      category: 'bedtime',
      ageGroup: '3–6 سنوات',
      repeatPhrase: '«تُصْبِحُونَ عَلَى خَيْرٍ يَا أَصْدِقَائِي»',
      activeActivity:
          'انظر من النافذة مع ماما أو بابا قبل النوم، وابحث عن القمر، ثم خذ 3 أنفاس عميقة وهادئة.',
      streamUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      bgGradientStart: const Color(0xFF1E1B4B),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: '🌙',
      likes: 142,
    ),
    VideoModel(
      id: 'v2',
      title: 'سلة الألعاب السعيدة مع أرنوب',
      description:
          '«ابتسم فارس وقال لنور: هيا نلعب لعبة الترتيب الهادئ! أنا أضع السيارات في السلة، وأنتِ تضعين المكعبات.»',
      category: 'habits',
      ageGroup: '3–7 سنوات',
      repeatPhrase: '«أَنَا أُرَتِّبُ أَلْعَابِي بِنَفْسِي»',
      activeActivity:
          'اذهب الآن واجمع 3 ألعاب من غرفتك وضعها في مكانها الصحيح مثل فارس ونور لتحصل على نجمة البطل!',
      streamUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      bgGradientStart: const Color(0xFF134E4A),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: '🧸',
      likes: 198,
    ),
    VideoModel(
      id: 'v3',
      title: 'سر أجنحة الفراشة الملونة في الحديقة',
      description:
          '«في البستان الأخضر الهادئ، أمسك فارس عدسته المكبرة واقترب بهدوء شديد ليرى فراشة تقف على زهرة وردية...»',
      category: 'science',
      ageGroup: '4–8 سنوات',
      repeatPhrase: '«سُبْحَانَ اللَّهِ، مَا أَجْمَلَ الْفَرَاشَةَ!»',
      activeActivity:
          'حرك يديك ببطء شديد مثل أجنحة الفراشة الهادئة 5 مرات، واذكر لونين رأيتهما على جناح الفراشة.',
      streamUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      bgGradientStart: const Color(0xFF064E3B),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: '🦋',
      likes: 215,
    ),
    VideoModel(
      id: 'v4',
      title: 'كلمات الصباح والمساء باللغة العربية الفصحى',
      description:
          '«عندما تشرق الشمس الدافئة في الصباح، نبتسم ونقول بصوت واضح وجميل: صَبَاحُ الْخَيْرِ!»',
      category: 'arabic',
      ageGroup: '2–6 سنوات',
      repeatPhrase: '«صَبَاحُ الْخَيْرِ يَا أُمِّي، مَسَاءُ النُّورِ يَا أَبِي»',
      activeActivity:
          'اذهب الآن إلى ماما أو بابا وقل بصوت عربي واضح وجميل: «شكراً لك، أنا أحبك كثيراً!»',
      streamUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      bgGradientStart: const Color(0xFF312E81),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: '🗣️',
      likes: 176,
    ),
    VideoModel(
      id: 'v5',
      title: 'بناء برج التوازن الخشبي وتمرين التنفس',
      description:
          '«نأخذ شهيقاً عميقاً من الأنف مثل شم زهرة جميلة.. ثم نخرج الهواء ببطء، ونضع المكعب الثاني فوق الأول.»',
      category: 'crafts',
      ageGroup: '4–8 سنوات',
      repeatPhrase: '«يَدِي ثَابِتَةٌ وَعَقْلِي هَادِئٌ»',
      activeActivity:
          'أغلق الشاشة الآن، وحاول وضع 5 مكعبات أو كتب فوق بعضها بهدوء تام دون أن تسقط!',
      streamUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      bgGradientStart: const Color(0xFF78350F),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: '🎨',
      likes: 164,
    ),
  ];
}

class AppStateManager extends ChangeNotifier {
  final SharedPreferences _prefs;
  bool isInitialized = false;
  bool onboardingCompleted = false;
  bool hasSelectedChildInSession = false;

  final Map<String, ParentAccount> _accounts = {};
  ParentAccount? currentAccount;

  List<VideoModel> videos = [];
  String remoteFeedUrl = kDefaultRemoteFeedUrl;
  String authApiUrl = '';
  String emailWebhookUrl = '';
  String paymentVerifyApiUrl = '';
  String merchantSecretKey = '';
  String remoteMonitorApiUrl = '';
  bool isSyncingVideos = false;
  String? lastSyncMessage;

  String currentAssistantBannerMessage =
      'مرحباً يا بطل! أنا رفيق حنين الذكي، اضغط عليّ لأقرأ لك أو أقترح عليك قصة ممتعة!';
  VideoModel? suggestedVideoForChild;

  Timer? _screenTimeTimer;
  int _activeSessionSeconds = 0;

  AppStateManager(this._prefs);

  Future<void> initialize() async {
    await CalmVoiceService.instance.init();
    onboardingCompleted = _prefs.getBool('onboarding_completed') ?? false;
    remoteFeedUrl =
        _prefs.getString('remote_feed_url') ?? kDefaultRemoteFeedUrl;
    authApiUrl = _prefs.getString('auth_api_url') ?? '';
    emailWebhookUrl = _prefs.getString('email_webhook_url') ?? '';
    paymentVerifyApiUrl = _prefs.getString('payment_verify_api_url') ?? '';
    merchantSecretKey = _prefs.getString('merchant_secret_key') ?? '';
    remoteMonitorApiUrl = _prefs.getString('remote_monitor_api_url') ?? '';

    final String? accountsJson = _prefs.getString('registered_accounts_v2');
    if (accountsJson != null && accountsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(accountsJson);
        decoded.forEach((key, value) {
          _accounts[key] =
              ParentAccount.fromJson(Map<String, dynamic>.from(value as Map));
        });
      } catch (_) {}
    }

    if (!_accounts.containsKey('parent@haneenkids.com')) {
      final demoAccount = ParentAccount(
        fullName: 'أبو فارس (حساب تجريبي)',
        emailOrPhone: 'parent@haneenkids.com',
        password: '123456',
        parentalPin: '1234',
        authProvider: 'demo',
        warmEveningFilter: false,
        subscriptionPlanId: 'trial_1day',
        trialStartDate: DateTime.now(),
        subscriptionExpiryDate: DateTime.now().add(const Duration(hours: 24)),
        children: [
          ChildProfile(
            id: 'child_faris',
            name: 'فارس',
            age: '3–6 سنوات',
            dailyTimeLimit: 20,
            starsEarned: 4,
            chosenAvatar: '🦁',
            usedMinutesToday: 0,
            watchedVideosToday: 1,
            correctPronunciationsCount: 2,
          ),
          ChildProfile(
            id: 'child_noor',
            name: 'نور',
            age: '4–8 سنوات',
            dailyTimeLimit: 25,
            starsEarned: 6,
            chosenAvatar: '🦋',
            usedMinutesToday: 0,
            watchedVideosToday: 2,
            correctPronunciationsCount: 3,
          ),
        ],
        activeChildId: 'child_faris',
      );
      demoAccount.emailAlertsLog.add(
        ParentEmailAlertItem(
          id: 'alert_welcome',
          recipientEmail: 'parent@haneenkids.com',
          subject:
              '🎉 مرحباً بك في حنين كيدز — بدأت فترتك التجريبية المجانية (٢٤ ساعة)',
          bodyMessage:
              'تم تفعيل حسابك بنجاح مع فترة تجريبية مجانية لمدة يوم كامل (٢٤ ساعة). يمكنك متابعة تقدم فارس ونور في الفصاحة والأنشطة الواقعية من بوابة الوالدين.',
          smartImprovementSuggestion:
              '💡 اقتراح لتحسين التجربة: فعّل «فلتر المساء الدافئ» قبل موعد نوم الطفل بنصف ساعة، وشجّع طفلك على استخدام زر «ردد معي» الصوتي لكسب نجوم الفصاحة.',
          sentAt: DateTime.now(),
        ),
      );
      _accounts['parent@haneenkids.com'] = demoAccount;
      await _saveAccounts();
    }

    final String? loggedInUser = _prefs.getString('current_user_key');
    if (loggedInUser != null && _accounts.containsKey(loggedInUser)) {
      currentAccount = _accounts[loggedInUser];
      hasSelectedChildInSession =
          _prefs.getBool('has_selected_child_in_session') ?? true;
    }

    final String? savedVideosJson = _prefs.getString('saved_videos_v2');
    if (savedVideosJson != null && savedVideosJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(savedVideosJson);
        videos = list
            .map((item) =>
                VideoModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (_) {
        videos = getDefaultVideos();
      }
    } else {
      videos = getDefaultVideos();
    }

    _syncLikedStateForActiveChild();
    CalmVoiceService.instance.setAssistantMuted(
        !(currentAccount?.voiceAssistantEnabled ?? true));
    _refreshSmartVoiceAssistantSuggestion(speakAloud: false);
    _startScreenTimeTracker();
    isInitialized = true;
    notifyListeners();

    if (remoteFeedUrl.trim().isNotEmpty) {
      syncVideosFromRemoteUrl(remoteFeedUrl);
    }
  }

  void _startScreenTimeTracker() {
    _screenTimeTimer?.cancel();
    _screenTimeTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (currentAccount != null && hasSelectedChildInSession) {
        final child = currentAccount!.activeChild;
        if (child.usedMinutesToday < child.dailyTimeLimit) {
          child.usedMinutesToday++;
          _activeSessionSeconds += 60;
          final int remaining = child.dailyTimeLimit - child.usedMinutesToday;
          if (remaining == 5 && currentAccount!.voiceAssistantEnabled) {
            final msg =
                'تنبيه لطيف يا ${child.name}، بقيت خمس دقائق فقط في وقت المشاهدة اليومي، استعد لنشاط البطل!';
            currentAssistantBannerMessage = msg;
            CalmVoiceService.instance.speakCalmly(msg);
          } else if (remaining <= 0) {
            sendParentEmailAlert(
              subject:
                  '🌙 إشعار حنين كيدز: انتهاء الحصة اليومية للطفل ${child.name}',
              bodyMessage:
                  'أكمل الطفل ${child.name} حصته اليومية المحددة (${child.dailyTimeLimit} دقيقة) وتم إسدال ستارة النوم الهادئة تلقائياً.',
              customSuggestion: generateSmartParentRecommendation(),
            );
          }
          _saveAccounts();
          notifyListeners();
        }
      }
    });
  }

  int get activeSessionMinutes => (_activeSessionSeconds / 60).floor();

  bool get isDailyLimitReached {
    final child = currentAccount?.activeChild;
    if (child == null) return false;
    return child.usedMinutesToday >= child.dailyTimeLimit;
  }

  bool get isSubscriptionExpired {
    if (currentAccount == null) return false;
    return !currentAccount!.isSubscriptionActive;
  }

  String generateSmartParentRecommendation() {
    final account = currentAccount;
    if (account == null) {
      return '💡 خصص ١٥ دقيقة يومياً لمشاركة طفلك قصة من قسم الفصاحة والنطق.';
    }
    final child = account.activeChild;
    final int hour = DateTime.now().hour;

    if (hour >= 18 && !account.warmEveningFilter) {
      return '🌙 اقتراح المساء: نلاحظ أن وقت المشاهدة مسائي؛ ننصح بتفعيل «فلتر المساء الدافئ» واختيار قسم «قصص النوم» لتهدئة الطفل قبل النوم.';
    }
    if (child.correctPronunciationsCount < 2) {
      return '🗣️ اقتراح تطوير النطق: شجّع ${child.name} على الضغط على زر «ردد معي» في قصص «فصاحة ونطق» ليستمع للمصحح الصوتي الهادئ ويطور مخارج الحروف.';
    }
    if (child.completedActivities.length < 2) {
      return '🎯 اقتراح التوازن الحركي: بعد انتهاء القصة القادمة، افتح نافذة «نشاط البطل الواقعي» مع ${child.name} لتنفيذ مهمة حركية خارج الشاشة.';
    }
    return '🌟 أداء رائع! ${child.name} يتفاعل بانتظام؛ نقترح تجربة قصص «لماذا وكيف؟» لتنمية الفضول العلمي والتفكير الهادئ.';
  }

  void _refreshSmartVoiceAssistantSuggestion({bool speakAloud = false}) {
    if (videos.isEmpty) return;
    final child = currentAccount?.activeChild;
    final String childName = child?.name ?? 'يا بطل';
    final int hour = DateTime.now().hour;

    VideoModel candidate = videos.first;
    String greeting;

    if (hour >= 19) {
      candidate = videos.firstWhere(
        (v) => v.category == 'bedtime',
        orElse: () => videos.first,
      );
      greeting =
          'مساء الهدوء يا $childName! أنا مساعدك الذكي، أقترح عليك مشاهدة قصة «${candidate.title}» للاستعداد لنوم هادئ وجميل.';
    } else if ((child?.correctPronunciationsCount ?? 0) < 2) {
      candidate = videos.firstWhere(
        (v) => v.category == 'arabic',
        orElse: () => videos.first,
      );
      greeting =
          'أهلاً يا $childName! هيا نشاهد قصة «${candidate.title}» ونتدرب معاً بصوتي الهادئ على نطق الجملة الفصيحة!';
    } else {
      final randomIndex = Random().nextInt(videos.length);
      candidate = videos[randomIndex];
      greeting =
          'مرحباً يا $childName! لدي اقتراح رائع لك اليوم: قصة «${candidate.title}»، وبعدها سنلعب معاً نشاط البطل الواقعي!';
    }

    suggestedVideoForChild = candidate;
    currentAssistantBannerMessage = greeting;
    if (speakAloud && (currentAccount?.voiceAssistantEnabled ?? true)) {
      CalmVoiceService.instance.speakCalmly(greeting);
    }
    notifyListeners();
  }

  void triggerVoiceAssistantGreetingAndSuggestion() {
    _refreshSmartVoiceAssistantSuggestion(speakAloud: true);
  }

  Future<void> sendParentEmailAlert({
    required String subject,
    required String bodyMessage,
    String? customSuggestion,
  }) async {
    final account = currentAccount;
    if (account == null) return;
    final String suggestion =
        customSuggestion ?? generateSmartParentRecommendation();

    final alert = ParentEmailAlertItem(
      id: 'mail_${DateTime.now().millisecondsSinceEpoch}',
      recipientEmail: account.emailOrPhone,
      subject: subject,
      bodyMessage: bodyMessage,
      smartImprovementSuggestion: suggestion,
      sentAt: DateTime.now(),
      deliveredToCloud: true,
    );

    account.emailAlertsLog.insert(0, alert);

    if (emailWebhookUrl.trim().isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(emailWebhookUrl.trim()),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode(alert.toJson()),
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    await _saveAccounts();
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboardingCompleted = true;
    await _prefs.setBool('onboarding_completed', true);
    notifyListeners();
  }

  Future<void> _saveAccounts() async {
    final Map<String, dynamic> data = {};
    _accounts.forEach((key, acc) {
      data[key] = acc.toJson();
    });
    await _prefs.setString('registered_accounts_v2', jsonEncode(data));
  }

  Future<void> _saveVideos() async {
    final List<Map<String, dynamic>> data =
        videos.map((v) => v.toJson()).toList();
    await _prefs.setString('saved_videos_v2', jsonEncode(data));
  }

  void _syncLikedStateForActiveChild() {
    final child = currentAccount?.activeChild;
    if (child == null) return;
    for (final video in videos) {
      video.isLiked = child.likedVideoIds.contains(video.id);
    }
  }

  Future<String?> login(String emailOrPhone, String password) async {
    final key = emailOrPhone.trim().toLowerCase();
    if (key.isEmpty || password.isEmpty) {
      return 'يرجى إدخال البريد الإلكتروني أو رقم الهاتف وكلمة المرور';
    }

    if (authApiUrl.trim().isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse('${authApiUrl.trim()}/login'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({'emailOrPhone': key, 'password': password}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 || response.statusCode == 201) {
          final json = jsonDecode(utf8.decode(response.bodyBytes));
          if (json is Map<String, dynamic> && json['account'] is Map) {
            final account = ParentAccount.fromJson(
                Map<String, dynamic>.from(json['account'] as Map));
            _accounts[key] = account;
            currentAccount = account;
            hasSelectedChildInSession = true;
            await _saveAccounts();
            await _prefs.setString('current_user_key', key);
            await _prefs.setBool('has_selected_child_in_session', true);
            _syncLikedStateForActiveChild();
            _refreshSmartVoiceAssistantSuggestion(speakAloud: false);
            notifyListeners();
            return null;
          }
        }
      } catch (_) {}
    }

    final account = _accounts[key];
    if (account == null) {
      return 'لا يوجد حساب مسجل بهذا البريد أو الهاتف. أنشئ حساباً جديداً أو سجل بحساب جوجل.';
    }
    if (account.password != password && account.authProvider != 'google') {
      return 'كلمة المرور غير صحيحة، يرجى المحاولة مرة أخرى.';
    }

    currentAccount = account;
    hasSelectedChildInSession = true;
    await _prefs.setString('current_user_key', key);
    await _prefs.setBool('has_selected_child_in_session', true);
    _syncLikedStateForActiveChild();
    _refreshSmartVoiceAssistantSuggestion(speakAloud: false);
    notifyListeners();
    return null;
  }

  Future<String?> signInOrSignUpWithGoogle({
    required String googleEmail,
    required String googleDisplayName,
    required String parentalPin,
    required String childName,
    required String childAgeGroup,
    required String childAvatar,
    required int dailyTimeLimit,
  }) async {
    final key = googleEmail.trim().toLowerCase();
    if (key.isEmpty || !key.contains('@')) {
      return 'يرجى اختيار أو إدخال بريد حساب Google صحيح (مثل name@gmail.com).';
    }

    if (_accounts.containsKey(key)) {
      currentAccount = _accounts[key];
      onboardingCompleted = true;
      hasSelectedChildInSession = true;
      await _prefs.setBool('onboarding_completed', true);
      await _prefs.setString('current_user_key', key);
      await _prefs.setBool('has_selected_child_in_session', true);
      _syncLikedStateForActiveChild();
      _refreshSmartVoiceAssistantSuggestion(speakAloud: false);
      await sendParentEmailAlert(
        subject: '🔐 تسجيل دخول ناجح عبر حساب جوجل — حنين كيدز',
        bodyMessage:
            'تم تسجيل الدخول إلى حسابك ($key) عبر مصادقة Google بنجاح.',
      );
      notifyListeners();
      return null;
    }

    final firstChild = ChildProfile(
      id: 'child_${DateTime.now().millisecondsSinceEpoch}',
      name: childName.trim().isEmpty ? 'بطل حنين' : childName.trim(),
      age: childAgeGroup,
      dailyTimeLimit: dailyTimeLimit,
      chosenAvatar: childAvatar,
    );

    final now = DateTime.now();
    final newAccount = ParentAccount(
      fullName: googleDisplayName.trim().isEmpty
          ? 'ولي أمر (${key.split('@').first})'
          : googleDisplayName.trim(),
      emailOrPhone: key,
      password: 'google_oauth_${now.millisecondsSinceEpoch}',
      parentalPin: parentalPin.trim().length == 4 ? parentalPin.trim() : '1234',
      authProvider: 'google',
      warmEveningFilter: false,
      subscriptionPlanId: 'trial_1day',
      trialStartDate: now,
      subscriptionExpiryDate: now.add(const Duration(hours: 24)),
      children: [firstChild],
      activeChildId: firstChild.id,
    );

    _accounts[key] = newAccount;
    currentAccount = newAccount;
    onboardingCompleted = true;
    hasSelectedChildInSession = true;
    await _saveAccounts();
    await _prefs.setBool('onboarding_completed', true);
    await _prefs.setString('current_user_key', key);
    await _prefs.setBool('has_selected_child_in_session', true);
    _syncLikedStateForActiveChild();
    _refreshSmartVoiceAssistantSuggestion(speakAloud: false);

    await sendParentEmailAlert(
      subject:
          '🎁 مرحباً بك عبر Google في حنين كيدز — بدأت تجربتك المجانية (٢٤ ساعة)',
      bodyMessage:
          'أهلاً بك يا ${newAccount.fullName}! تم ربط حساب جوجل ($key) وإنشاء ملف الطفل (${firstChild.name}) مع تفعيل تجربة مجانية شاملة لمدة ٢٤ ساعة.',
      customSuggestion:
          '💡 نصيحة اليوم الأول: جرب مع ${firstChild.name} ميزة «ردد معي» الصوتية ومساعد حنين الذكي لاكتشاف القصص الأنسب لعمره (${firstChild.age}).',
    );

    notifyListeners();
    return null;
  }

  Future<void> quickDemoLogin() async {
    onboardingCompleted = true;
    await _prefs.setBool('onboarding_completed', true);
    await login('parent@haneenkids.com', '123456');
  }

  Future<String?> registerParentAccount({
    required String fullName,
    required String emailOrPhone,
    required String password,
    required String parentalPin,
    required String childName,
    required String childAgeGroup,
    required String childAvatar,
    required int dailyTimeLimit,
  }) async {
    final key = emailOrPhone.trim().toLowerCase();
    if (fullName.trim().isEmpty || key.isEmpty || password.length < 4) {
      return 'يرجى ملء كافة الحقول والتأكد أن كلمة المرور 4 أحرف أو أرقام على الأقل.';
    }
    if (parentalPin.trim().length != 4) {
      return 'يرجى إدخال رمز حماية أبوي (PIN) مكون من 4 أرقام.';
    }
    if (_accounts.containsKey(key)) {
      return 'هذا الحساب مسجل بالفعل، يمكنك تسجيل الدخول مباشرة.';
    }

    final firstChild = ChildProfile(
      id: 'child_${DateTime.now().millisecondsSinceEpoch}',
      name: childName.trim().isEmpty ? 'بطل حنين' : childName.trim(),
      age: childAgeGroup,
      dailyTimeLimit: dailyTimeLimit,
      chosenAvatar: childAvatar,
    );

    final now = DateTime.now();
    final newAccount = ParentAccount(
      fullName: fullName.trim(),
      emailOrPhone: key,
      password: password,
      parentalPin: parentalPin.trim(),
      authProvider: 'email',
      warmEveningFilter: false,
      subscriptionPlanId: 'trial_1day',
      trialStartDate: now,
      subscriptionExpiryDate: now.add(const Duration(hours: 24)),
      children: [firstChild],
      activeChildId: firstChild.id,
    );

    _accounts[key] = newAccount;
    currentAccount = newAccount;
    hasSelectedChildInSession = true;
    await _saveAccounts();
    await _prefs.setString('current_user_key', key);
    await _prefs.setBool('has_selected_child_in_session', true);
    _syncLikedStateForActiveChild();
    _refreshSmartVoiceAssistantSuggestion(speakAloud: false);

    await sendParentEmailAlert(
      subject:
          '🎉 مرحباً بك في حنين كيدز — تفعيل التجربة المجانية لمدة يوم كامل (٢٤ ساعة)',
      bodyMessage:
          'تم إنشاء حساب الوالدين ($key) وتخصيص ملف الطفل (${firstChild.name}). لديك الآن ٢٤ ساعة مجانية لاستكشاف كافة المميزات قبل اختيار باقة الاشتراك المناسبة.',
    );

    notifyListeners();
    return null;
  }

  Future<void> updatePaymentGatewayConfig({
    required String verifyUrl,
    required String secretKey,
  }) async {
    paymentVerifyApiUrl = verifyUrl.trim();
    merchantSecretKey = secretKey.trim();
    await _prefs.setString('payment_verify_api_url', paymentVerifyApiUrl);
    await _prefs.setString('merchant_secret_key', merchantSecretKey);
    notifyListeners();
  }

  Future<PaymentVerificationOutcome> verifyAndActivateEgyptianPayment({
    required SubscriptionPlanModel plan,
    required EgyptianPaymentMethodInfo method,
    required String payerIdentifier,
    required String bankTransferRefNum,
    required String generatedSessionOtp,
    required String userEnteredOtp,
    required bool simulateBankRejection,
  }) async {
    final account = currentAccount;
    if (account == null) {
      return const PaymentVerificationOutcome(
        isPaidAndVerified: false,
        message: 'لا يوجد حساب مسجل حالياً لإتمام عملية الدفع.',
      );
    }

    final now = DateTime.now();

    Future<PaymentVerificationOutcome> recordRejectedAttempt(
        String reason) async {
      final failedTx = PaymentTransactionRecord(
        id: 'tx_fail_${now.millisecondsSinceEpoch}',
        planId: plan.id,
        planTitle: plan.title,
        amountEgp: plan.priceEgp,
        paymentMethodId: method.id,
        paymentMethodName: method.nameAr,
        payerIdentifier: payerIdentifier.trim(),
        referenceCode: bankTransferRefNum.trim().isEmpty
            ? 'REJECTED-${1000 + Random().nextInt(8999)}'
            : bankTransferRefNum.trim(),
        status: 'failed',
        failureReason: reason,
        createdAt: now,
      );
      account.paymentHistory.insert(0, failedTx);
      await sendParentEmailAlert(
        subject:
            '⚠️ لم تكتمل عملية الدفع (${plan.title}) — لم يتم تفعيل الباقة',
        bodyMessage:
            'تم رفض أو عدم اكتمال عملية الدفع بقيمة ${plan.priceEgp} ج.م عبر ${method.nameAr}. السبب: $reason. لم يتم تغيير أو تفعيل الباقة المختارة.',
        customSuggestion:
            '💡 يرجى التأكد من إتمام التحويل الفعلي وإدخال رقم مرجع العملية البنكي وكود التحقق الصحيح لإتمام التفعيل.',
      );
      await _saveAccounts();
      notifyListeners();
      return PaymentVerificationOutcome(
        isPaidAndVerified: false,
        message: '❌ فشل التحقق من الدفع: $reason — لم يتم تفعيل الباقة المختارة.',
        transaction: failedTx,
      );
    }

    if (simulateBankRejection) {
      return recordRejectedAttempt(
        'تم رفض العملية من البنك أو المحفظة الإلكترونية (رصيد غير كافٍ أو إلغاء العملية من المصدر).',
      );
    }

    if (userEnteredOtp.trim().isEmpty ||
        userEnteredOtp.trim() != generatedSessionOtp.trim()) {
      return recordRejectedAttempt(
        'كود التحقق البنكي (3D-Secure / OTP) غير مطابق للكود المرسل للعملية.',
      );
    }

    final String cleanRef =
        bankTransferRefNum.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanRef.length < 6) {
      return recordRejectedAttempt(
        'رقم مرجع العملية البنكية / إيصال التحويل غير صالح (يجب أن لا يقل عن ٦ أرقام أو حروف).',
      );
    }

    final bool duplicateRefUsed = account.paymentHistory.any(
      (tx) =>
          tx.isVerified &&
          tx.referenceCode.toLowerCase() == cleanRef.toLowerCase(),
    );
    if (duplicateRefUsed) {
      return recordRejectedAttempt(
        'رقم مرجع التحويل ($cleanRef) تم استخدامه مسبقاً في عملية سابقة ولا يمكن إعادة استخدامه.',
      );
    }

    if (paymentVerifyApiUrl.trim().isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse(paymentVerifyApiUrl.trim()),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                if (merchantSecretKey.isNotEmpty)
                  'Authorization': 'Bearer $merchantSecretKey',
              },
              body: jsonEncode({
                'planId': plan.id,
                'amountEgp': plan.priceEgp,
                'paymentMethod': method.id,
                'payerIdentifier': payerIdentifier.trim(),
                'referenceCode': cleanRef,
                'otpCode': userEnteredOtp.trim(),
                'email': account.emailOrPhone,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode != 200 && response.statusCode != 201) {
          return recordRejectedAttempt(
            'رفض سيرفر بوابة الدفع تأكيد العملية (كود الاستجابة: ${response.statusCode}).',
          );
        }

        final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final bool paidConfirmed = decoded is Map &&
            (decoded['paid'] == true ||
                decoded['verified'] == true ||
                decoded['status'] == 'success' ||
                decoded['status'] == 'paid');

        if (!paidConfirmed) {
          final String serverMsg = (decoded is Map && decoded['message'] != null)
              ? decoded['message'].toString()
              : 'لم يتم العثور على تحصيل مالي مؤكد لهذا المرجع في بوابة الدفع.';
          return recordRejectedAttempt(serverMsg);
        }
      } catch (_) {
        return recordRejectedAttempt(
          'تعذر الاتصال بسيرفر التحقق من الدفع الحي (${paymentVerifyApiUrl.trim()})، لم يتم تفعيل الخطة لحين التأكد من الدفع.',
        );
      }
    }

    final DateTime baseDate = account.subscriptionExpiryDate.isAfter(now)
        ? account.subscriptionExpiryDate
        : now;

    account.subscriptionPlanId = plan.id;
    account.subscriptionExpiryDate =
        baseDate.add(Duration(days: plan.durationDays));

    final verifiedTx = PaymentTransactionRecord(
      id: 'tx_${now.millisecondsSinceEpoch}',
      planId: plan.id,
      planTitle: plan.title,
      amountEgp: plan.priceEgp,
      paymentMethodId: method.id,
      paymentMethodName: method.nameAr,
      payerIdentifier: payerIdentifier.trim(),
      referenceCode: cleanRef.toUpperCase(),
      status: 'verified',
      createdAt: now,
    );

    account.paymentHistory.insert(0, verifiedTx);

    await sendParentEmailAlert(
      subject:
          '✅ إيصال دفع مؤكد وتفعيل باقة (${plan.title}) عبر ${method.nameAr}',
      bodyMessage:
          'تم التحقق الفعلي من سداد مبلغ ${plan.priceEgp} جنيه مصري عبر ${method.nameAr} (رقم مرجع العملية الموثق: ${verifiedTx.referenceCode}). تم تفعيل الباقة المختارة بنجاح حتى ${account.subscriptionExpiryDate.toLocal().toString().split(" ").first}.',
      customSuggestion:
          '💡 نصيحة بعد تفعيل الاشتراك: يمكنك الآن إدارة ملفات أطفالك ومتابعة تقدمهم في الفصاحة وألعاب الذكاء.',
    );

    await _saveAccounts();
    notifyListeners();

    return PaymentVerificationOutcome(
      isPaidAndVerified: true,
      message:
          '✅ تم التحقق من الدفع بنجاح وتفعيل (${plan.title})! رقم المرجع الموثق: ${verifiedTx.referenceCode}',
      transaction: verifiedTx,
    );
  }

  Future<void> activateOrResetOneDayTrial() async {
    final account = currentAccount;
    if (account == null) return;
    account.subscriptionPlanId = 'trial_1day';
    account.trialStartDate = DateTime.now();
    account.subscriptionExpiryDate =
        DateTime.now().add(const Duration(hours: 24));
    await sendParentEmailAlert(
      subject: '🎁 تم تفعيل يوم تجريبي مجاني جديد (٢٤ ساعة) في حنين كيدز',
      bodyMessage:
          'تم منح حسابك ٢٤ ساعة تجريبية مجانية إضافية للاستمتاع بجميع القصص والميزات الصوتية الذكية.',
    );
    await _saveAccounts();
    notifyListeners();
  }

  Future<String?> resetPassword({
    required String emailOrPhone,
    required String parentalPin,
    required String newPassword,
  }) async {
    final key = emailOrPhone.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null) {
      return 'لم يتم العثور على حساب مرتبط بهذا البريد أو رقم الهاتف.';
    }
    if (account.parentalPin != parentalPin.trim()) {
      return 'رمز الحماية الأبوي (PIN) غير مطابق لهذا الحساب.';
    }
    if (newPassword.length < 4) {
      return 'كلمة المرور الجديدة يجب أن تكون 4 أحرف أو أرقام على الأقل.';
    }
    account.password = newPassword;
    await _saveAccounts();
    notifyListeners();
    return null;
  }

  Future<void> updateParentalPin(String newPin) async {
    if (currentAccount == null || newPin.trim().length != 4) return;
    currentAccount!.parentalPin = newPin.trim();
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> toggleParentEmailNotifications(bool enabled) async {
    if (currentAccount == null) return;
    currentAccount!.emailNotificationsEnabled = enabled;
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> toggleDailySmartSuggestions(bool enabled) async {
    if (currentAccount == null) return;
    currentAccount!.dailySmartSuggestionsEnabled = enabled;
    await _saveAccounts();
    notifyListeners();
  }

  bool get isAssistantVoiceMuted =>
      !(currentAccount?.voiceAssistantEnabled ?? true);

  Future<void> toggleVoiceAssistant([bool? enabled]) async {
    if (currentAccount == null) return;
    final bool nextVal = enabled ?? !currentAccount!.voiceAssistantEnabled;
    currentAccount!.voiceAssistantEnabled = nextVal;
    await CalmVoiceService.instance.setAssistantMuted(!nextVal);
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> logChildRealtimeActivity({
    required String statusSummary,
    required String actionLogText,
    required String categoryBadge,
  }) async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    child.currentLiveStatus = statusSummary;
    child.liveActivityTimeline.insert(
      0,
      ChildActivityLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        actionTitle: actionLogText,
        categoryBadge: categoryBadge,
      ),
    );
    if (child.liveActivityTimeline.length > 35) {
      child.liveActivityTimeline.removeLast();
    }
    if (remoteMonitorApiUrl.trim().isNotEmpty) {
      try {
        http.post(
          Uri.parse(remoteMonitorApiUrl.trim()),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'event': 'child_activity_update',
            'childId': child.id,
            'childName': child.name,
            'currentLiveStatus': child.currentLiveStatus,
            'isLocked': child.isDeviceRemotelyLocked,
            'usedMinutesToday': child.usedMinutesToday,
            'starsEarned': child.starsEarned,
            'intelligencePoints': child.intelligencePoints,
            'latestAction': actionLogText,
          }),
        );
      } catch (_) {}
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> setRemoteDeviceLockForChild({
    required String childId,
    required bool lockDevice,
    String? customLockMessage,
  }) async {
    if (currentAccount == null) return;
    final idx = currentAccount!.children.indexWhere((c) => c.id == childId);
    if (idx == -1) return;
    final child = currentAccount!.children[idx];
    child.isDeviceRemotelyLocked = lockDevice;
    if (customLockMessage != null && customLockMessage.trim().isNotEmpty) {
      child.remoteLockReasonMessage = customLockMessage.trim();
    }
    child.currentLiveStatus = lockDevice
        ? '🔒 الشاشة مقفلة عن بُعد بأمر من هاتف ولي الأمر'
        : '🟢 متصل — تم فتح القفل الأبوي عن بُعد';
    child.liveActivityTimeline.insert(
      0,
      ChildActivityLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        actionTitle: lockDevice
            ? 'قام ولي الأمر بقفل شاشة موبايل الطفل عن بُعد'
            : 'قام ولي الأمر بفتح قفل شاشة موبايل الطفل عن بُعد',
        categoryBadge: 'تحكم عن بُعد',
      ),
    );
    if (lockDevice) {
      await CalmVoiceService.instance.stopSpeaking();
    }
    if (remoteMonitorApiUrl.trim().isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(remoteMonitorApiUrl.trim()),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({
                'command': lockDevice ? 'LOCK_CHILD_DEVICE' : 'UNLOCK_CHILD_DEVICE',
                'childId': child.id,
                'childName': child.name,
                'lockReason': child.remoteLockReasonMessage,
                'timestamp': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> sendRemoteVoiceAlertToChild({
    required String childId,
    required String messageText,
  }) async {
    if (currentAccount == null || messageText.trim().isEmpty) return;
    final idx = currentAccount!.children.indexWhere((c) => c.id == childId);
    if (idx == -1) return;
    final child = currentAccount!.children[idx];
    currentAssistantBannerMessage = '📲 رسالة من بابا وماما: ${messageText.trim()}';
    child.liveActivityTimeline.insert(
      0,
      ChildActivityLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        actionTitle: 'رسالة صوتية مباشرة من ولي الأمر: «${messageText.trim()}»',
        categoryBadge: 'تنبيه أبوي',
      ),
    );
    await CalmVoiceService.instance.speakCalmly(
      'رسالة من بابا وماما يا ${child.name}: ${messageText.trim()}',
      forceSpeakEvenIfAssistantMuted: true,
    );
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> updateRemoteMonitorApiUrl(String url) async {
    remoteMonitorApiUrl = url.trim();
    await _prefs.setString('remote_monitor_api_url', remoteMonitorApiUrl);
    notifyListeners();
  }

  Future<void> logout() async {
    await CalmVoiceService.instance.stopSpeaking();
    currentAccount = null;
    hasSelectedChildInSession = false;
    await _prefs.remove('current_user_key');
    await _prefs.setBool('has_selected_child_in_session', false);
    notifyListeners();
  }

  Future<void> openChildProfilesScreen() async {
    hasSelectedChildInSession = false;
    await _prefs.setBool('has_selected_child_in_session', false);
    notifyListeners();
  }

  Future<void> selectChildAndEnterFeed(String childId) async {
    if (currentAccount == null) return;
    currentAccount!.activeChildId = childId;
    hasSelectedChildInSession = true;
    _syncLikedStateForActiveChild();
    _refreshSmartVoiceAssistantSuggestion(speakAloud: true);
    await _saveAccounts();
    await _prefs.setBool('has_selected_child_in_session', true);
    notifyListeners();
  }

  Future<void> switchActiveChild(String childId) async {
    if (currentAccount == null) return;
    currentAccount!.activeChildId = childId;
    _syncLikedStateForActiveChild();
    _refreshSmartVoiceAssistantSuggestion(speakAloud: false);
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> addChildProfile({
    required String name,
    required String age,
    required String chosenAvatar,
    required int dailyTimeLimit,
  }) async {
    if (currentAccount == null) return;
    final child = ChildProfile(
      id: 'child_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      age: age,
      chosenAvatar: chosenAvatar,
      dailyTimeLimit: dailyTimeLimit,
    );
    currentAccount!.children.add(child);
    currentAccount!.activeChildId = child.id;
    _syncLikedStateForActiveChild();
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> updateChildProfile({
    required String childId,
    required String name,
    required String age,
    required String chosenAvatar,
    required int dailyTimeLimit,
  }) async {
    if (currentAccount == null) return;
    final index = currentAccount!.children.indexWhere((c) => c.id == childId);
    if (index == -1) return;
    final child = currentAccount!.children[index];
    child.name = name.trim().isEmpty ? child.name : name.trim();
    child.age = age;
    child.chosenAvatar = chosenAvatar;
    child.dailyTimeLimit = dailyTimeLimit;
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> removeChildProfile(String childId) async {
    if (currentAccount == null || currentAccount!.children.length <= 1) return;
    currentAccount!.children.removeWhere((c) => c.id == childId);
    currentAccount!.activeChildId = currentAccount!.children.first.id;
    _syncLikedStateForActiveChild();
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> recordVideoTransitionWatched({String? videoTitle}) async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    child.watchedVideosToday++;
    if (videoTitle != null && videoTitle.isNotEmpty) {
      child.currentLiveStatus = '🎬 يشاهد الآن قصة: «$videoTitle»';
      child.liveActivityTimeline.insert(
        0,
        ChildActivityLogEntry(
          timestampIso: DateTime.now().toIso8601String(),
          actionTitle: 'بدأ مشاهدة قصة «$videoTitle»',
          categoryBadge: 'مشاهدة قصة',
        ),
      );
    }
    if (child.usedMinutesToday < child.dailyTimeLimit) {
      child.usedMinutesToday =
          min(child.dailyTimeLimit, child.usedMinutesToday + 2);
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> resetDailyScreenTimeForActiveChild() async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    child.usedMinutesToday = 0;
    child.watchedVideosToday = 0;
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> updateDailyTimeLimit(int newMinutesLimit) async {
    if (currentAccount == null) return;
    currentAccount!.activeChild.dailyTimeLimit = newMinutesLimit;
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> toggleWarmEveningFilter([bool? newValue]) async {
    if (currentAccount == null) return;
    currentAccount!.warmEveningFilter =
        newValue ?? !currentAccount!.warmEveningFilter;
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> recordBrainGameWin({
    required String gameId,
    required String gameTitle,
    int earnedIqPoints = 15,
    int earnedStars = 2,
  }) async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    child.starsEarned += earnedStars;
    child.intelligencePoints += earnedIqPoints;
    child.gamesCompletedCount++;
    final String key = 'game_${gameId}_${DateTime.now().millisecondsSinceEpoch}';
    child.completedActivities.add(key);
    child.currentLiveStatus = '🧠 يلعب ويتفوق في: «$gameTitle»';
    child.liveActivityTimeline.insert(
      0,
      ChildActivityLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        actionTitle: 'أنجز تحدياً في ($gameTitle) وكسب +$earnedIqPoints نقطة ذكاء',
        categoryBadge: 'ألعاب الذكاء',
      ),
    );

    if (currentAccount!.emailNotificationsEnabled &&
        child.gamesCompletedCount % 2 == 0) {
      await sendParentEmailAlert(
        subject:
            '🧠 تطور قدرات الذكاء للطفل ${child.name} في «$gameTitle»!',
        bodyMessage:
            'أنجز ${child.name} تحدياً جديداً في لعبة ($gameTitle) وارتفعت نقاط الذكاء والقدرات لديه إلى ${child.intelligencePoints} نقطة مع ${child.starsEarned} نجمة!',
        customSuggestion:
            '💡 اقتراح تربوي: شجع ${child.name} على التنوع بين ألعاب الذاكرة البصرية والمنطق والحساب لتنمية نصفي الدماغ معاً.',
      );
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> awardStarAndRecordActivity(
    String activityKey, {
    bool isPronunciation = false,
  }) async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    child.starsEarned++;
    if (isPronunciation) {
      child.correctPronunciationsCount++;
    }
    if (!child.completedActivities.contains(activityKey)) {
      child.completedActivities.add(activityKey);
    }
    if (currentAccount!.emailNotificationsEnabled &&
        child.starsEarned % 3 == 0) {
      await sendParentEmailAlert(
        subject:
            '🌟 إنجاز جديد للبطل ${child.name} — وصل إلى ${child.starsEarned} نجوم!',
        bodyMessage:
            'أحرز ${child.name} تقدماً رائعاً في الفصاحة والأنشطة التربوية وجمع الآن ${child.starsEarned} نجوم.',
      );
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> toggleLikeVideo(VideoModel video) async {
    if (currentAccount == null) return;
    final child = currentAccount!.activeChild;
    if (video.isLiked) {
      video.isLiked = false;
      video.likes = max(0, video.likes - 1);
      child.likedVideoIds.remove(video.id);
    } else {
      video.isLiked = true;
      video.likes++;
      if (!child.likedVideoIds.contains(video.id)) {
        child.likedVideoIds.add(video.id);
      }
    }
    await _saveAccounts();
    await _saveVideos();
    notifyListeners();
  }

  Future<void> addCustomVideo(VideoModel newVideo) async {
    videos.insert(0, newVideo);
    _syncLikedStateForActiveChild();
    await _saveVideos();
    notifyListeners();
  }

  Future<List<VideoModel>> smartAutoImportFromAnyUrlOrPlaylist(
    String rawUrl, {
    bool forceChannelOrPlaylistMode = false,
  }) async {
    final bool isMulti = forceChannelOrPlaylistMode ||
        await SmartVideoLinkAutoImporter.detectIfChannelOrPlaylistUrl(rawUrl);

    if (isMulti) {
      final List<VideoModel> importedBatch =
          await SmartVideoLinkAutoImporter.autoImportChannelOrPlaylistFromUrl(
        rawUrl,
        maxVideosToImport: 8,
      );
      if (importedBatch.isNotEmpty) {
        for (final v in importedBatch.reversed) {
          videos.insert(0, v);
        }
        _syncLikedStateForActiveChild();
        await _saveVideos();
        notifyListeners();
      }
      return importedBatch;
    } else {
      final VideoModel? generatedVideo =
          await SmartVideoLinkAutoImporter.autoImportAndGenerateFromUrl(rawUrl);
      if (generatedVideo != null) {
        videos.insert(0, generatedVideo);
        _syncLikedStateForActiveChild();
        await _saveVideos();
        notifyListeners();
        return [generatedVideo];
      }
      return [];
    }
  }

  Future<void> deleteVideo(String videoId) async {
    if (videos.length <= 1) return;
    videos.removeWhere((v) => v.id == videoId);
    await _saveVideos();
    notifyListeners();
  }

  Future<void> restoreDefaultVideos() async {
    videos = getDefaultVideos();
    _syncLikedStateForActiveChild();
    await _saveVideos();
    notifyListeners();
  }

  Future<void> updateAuthApiUrl(String url) async {
    authApiUrl = url.trim();
    await _prefs.setString('auth_api_url', authApiUrl);
    notifyListeners();
  }

  Future<void> updateEmailWebhookUrl(String url) async {
    emailWebhookUrl = url.trim();
    await _prefs.setString('email_webhook_url', emailWebhookUrl);
    notifyListeners();
  }

  Future<bool> syncVideosFromRemoteUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      lastSyncMessage = 'يرجى إدخال رابط ملف JSON سحابي صالح.';
      notifyListeners();
      return false;
    }

    isSyncingVideos = true;
    lastSyncMessage = 'جاري الاتصال بالسحابة وسحب تغذية الفيديوهات...';
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(cleanUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final String body = utf8.decode(response.bodyBytes);
        final dynamic decoded = jsonDecode(body);

        List<dynamic>? rawList;
        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map<String, dynamic> &&
            decoded['videos'] is List) {
          rawList = decoded['videos'] as List<dynamic>;
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          rawList = decoded['data'] as List<dynamic>;
        }

        if (rawList != null && rawList.isNotEmpty) {
          final fetched = rawList
              .map((item) =>
                  VideoModel.fromJson(Map<String, dynamic>.from(item as Map)))
              .where((v) => v.streamUrl.trim().isNotEmpty)
              .toList();

          if (fetched.isNotEmpty) {
            videos = fetched;
            remoteFeedUrl = cleanUrl;
            await _prefs.setString('remote_feed_url', remoteFeedUrl);
            _syncLikedStateForActiveChild();
            await _saveVideos();
            isSyncingVideos = false;
            lastSyncMessage =
                'تم بنجاح مزامنة واستقبال ${fetched.length} فيديو من الرابط السحابي!';
            notifyListeners();
            return true;
          }
        }
        isSyncingVideos = false;
        lastSyncMessage =
            'تم الاتصال ولكن لم يتم العثور على قائمة فيديوهات صالحة داخل ملف JSON.';
        notifyListeners();
        return false;
      } else {
        isSyncingVideos = false;
        lastSyncMessage =
            'تعذر الجلب من الرابط السحابي (كود الاستجابة: ${response.statusCode}).';
        notifyListeners();
        return false;
      }
    } catch (_) {
      isSyncingVideos = false;
      lastSyncMessage =
          'تعذر الاتصال بالرابط: تأكد من اتصال الإنترنت وصحة رابط ملف JSON.';
      notifyListeners();
      return false;
    }
  }

  String exportVideosAsJson() {
    final map = {
      'app': 'Haneen Kids v2.5',
      'version': 25,
      'updatedAt': DateTime.now().toIso8601String(),
      'videos': videos.map((v) => v.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  @override
  void dispose() {
    _screenTimeTimer?.cancel();
    super.dispose();
  }
}

class HaneenKidsApp extends StatelessWidget {
  final AppStateManager appState;
  const HaneenKidsApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'حنين كيدز (Haneen Kids v2.5)',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF14B8A6),
              secondary: Color(0xFFF59E0B),
              surface: Color(0xFF1E293B),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF14B8A6), width: 2),
              ),
            ),
          ),
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            );
          },
          home: SplashRouterScreen(appState: appState),
        );
      },
    );
  }
}

class SplashRouterScreen extends StatefulWidget {
  final AppStateManager appState;
  const SplashRouterScreen({super.key, required this.appState});

  @override
  State<SplashRouterScreen> createState() => _SplashRouterScreenState();
}

class _SplashRouterScreenState extends State<SplashRouterScreen> {
  bool _splashTimerDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _splashTimerDone = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isInitialized || !_splashTimerDone) {
      return const SplashScreen();
    }
    if (!widget.appState.onboardingCompleted) {
      return OnboardingScreen(appState: widget.appState);
    }
    if (widget.appState.currentAccount == null) {
      return AuthScreen(appState: widget.appState);
    }
    if (!widget.appState.hasSelectedChildInSession) {
      return MultiChildProfilesScreen(appState: widget.appState);
    }
    return VerticalVideoFeedPlayerScreen(appState: widget.appState);
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF14B8A6).withOpacity(0.5),
                      width: 2),
                ),
                child: const Text('🌙✨', style: TextStyle(fontSize: 64)),
              ),
              const SizedBox(height: 20),
              const Text(
                'حنين كيدز (Haneen Kids)',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'مشاهدة هادئة • مساعد صوتي ذكي • تجربة مجانية ٢٤ ساعة',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(color: Color(0xFF14B8A6)),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  final AppStateManager appState;
  const OnboardingScreen({super.key, required this.appState});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _steps = [
    {
      'emoji': '🌿📺',
      'title': '١. المشاهدة الهادئة + تجربة مجانية ليوم كامل',
      'subtitle':
          'قصص مرئية مصممة خصيصاً للأطفال بإيقاع بصري وصوتي هادئ، مع تجربة مجانية شاملة لمدة ٢٤ ساعة فور التسجيل بحساب جوجل أو الإيميل.',
    },
    {
      'emoji': '🎙️🤖',
      'title': '٢. مصحح «ردد معي» الصوتي والمساعد الذكي',
      'subtitle':
          'يستمع التطبيق لنطق طفلك بالعربية الفصحى ويتأكد من صحته ويعدّله بصوت هادئ ودافئ، مع مساعد ذكي يقدم تنبيهات واقتراحات مشاهدة.',
    },
    {
      'emoji': '📧💳',
      'title': '٣. تنبيهات الإيميل للآباء ووسائل الدفع المصرية',
      'subtitle':
          'تقارير واقتراحات تربوية ذكية تصل لإيميل الوالدين، وباقات اشتراك مرنة تدعم فودافون كاش، أورنج كاش، اتصالات كاش، إنستا باي، وفيزا.',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'حنين كيدز v2.5',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14B8A6),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.appState.completeOnboarding,
                      child: const Text(
                        'تخطي إلى التسجيل',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final item = _steps[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              item['emoji']!,
                              style: const TextStyle(fontSize: 64),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            item['title']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            item['subtitle']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _steps.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? const Color(0xFF14B8A6)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          if (_currentPage < _steps.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            widget.appState.completeOnboarding();
                          }
                        },
                        child: Text(
                          _currentPage < _steps.length - 1
                              ? 'الخطوة التالية'
                              : 'ابدأ تجربتك المجانية (٢٤ ساعة)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: widget.appState.quickDemoLogin,
                        icon: const Icon(Icons.flash_on),
                        label: const Text(
                          'دخول سريع بحساب تجريبي (parent@haneenkids.com / 123456)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final AppStateManager appState;
  const AuthScreen({super.key, required this.appState});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController(text: '1234');
  final TextEditingController _childNameCtrl = TextEditingController();

  String _selectedAgeGroup = '3–6 سنوات';
  String _selectedAvatar = '🦁';
  int _initialDailyMinutes = 20;

  final List<String> _ageGroups = [
    '2–4 سنوات',
    '3–6 سنوات',
    '4–8 سنوات',
    '6–10 سنوات'
  ];
  final List<String> _avatars = [
    '🦁',
    '🦋',
    '🐰',
    '🐼',
    '🚀',
    '🌸',
    '🐬',
    '🦊'
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _pinCtrl.dispose();
    _childNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    String? error;
    if (_isLogin) {
      error = await widget.appState.login(
        _emailCtrl.text,
        _passwordCtrl.text,
      );
    } else {
      error = await widget.appState.registerParentAccount(
        fullName: _fullNameCtrl.text,
        emailOrPhone: _emailCtrl.text,
        password: _passwordCtrl.text,
        parentalPin: _pinCtrl.text,
        childName: _childNameCtrl.text,
        childAgeGroup: _selectedAgeGroup,
        childAvatar: _selectedAvatar,
        dailyTimeLimit: _initialDailyMinutes,
      );
    }

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = error;
      });
    }
  }

  void _openGoogleSignUpModal() {
    final googleEmailCtrl =
        TextEditingController(text: 'ahmed.family.eg@gmail.com');
    final googleNameCtrl = TextEditingController(text: 'أحمد محمود (حساب جوجل)');
    final googlePinCtrl = TextEditingController(text: _pinCtrl.text);
    final googleChildCtrl = TextEditingController(
        text: _childNameCtrl.text.isEmpty ? 'ياسين' : _childNameCtrl.text);
    String googleAge = _selectedAgeGroup;
    String googleAvatar = _selectedAvatar;
    int googleMinutes = _initialDailyMinutes;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                right: 24,
                left: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'التسجيل السريع بحساب Google',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'يشمل تجربة مجانية فورية لمدة ٢٤ ساعة + تنبيهات الإيميل',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF14B8A6)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: googleEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'حساب جوجل (Gmail)',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: googleNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم ولي الأمر في حساب Google',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: googleChildCtrl,
                            decoration: const InputDecoration(
                              labelText: 'اسم الطفل الأول',
                              prefixIcon: Icon(Icons.child_care),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 115,
                          child: TextField(
                            controller: googlePinCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: 'PIN الأبوي',
                              counterText: '',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: googleAge,
                            decoration: const InputDecoration(
                              labelText: 'الفئة العمرية',
                            ),
                            items: _ageGroups
                                .map((age) => DropdownMenuItem(
                                      value: age,
                                      child: Text(age),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setModalState(() => googleAge = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: googleAvatar,
                          items: _avatars
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 24)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => googleAvatar = v);
                            }
                          },
                        ),
                      ],
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 10),
                      Text(modalError!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final err =
                              await widget.appState.signInOrSignUpWithGoogle(
                            googleEmail: googleEmailCtrl.text,
                            googleDisplayName: googleNameCtrl.text,
                            parentalPin: googlePinCtrl.text,
                            childName: googleChildCtrl.text,
                            childAgeGroup: googleAge,
                            childAvatar: googleAvatar,
                            dailyTimeLimit: googleMinutes,
                          );
                          if (err != null) {
                            setModalState(() => modalError = err);
                          } else if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        },
                        icon: const Icon(Icons.verified_user,
                            color: Color(0xFF4285F4)),
                        label: const Text(
                          'متابعة بحساب Google وبدء تجربة ٢٤ ساعة مجاناً',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _quickDemoLogin() {
    _emailCtrl.text = 'parent@haneenkids.com';
    _passwordCtrl.text = '123456';
    setState(() => _isLogin = true);
    _submit();
  }

  void _showForgotPasswordModal() {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text);
    final resetPinCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    String? modalError;
    String? modalSuccess;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                right: 24,
                left: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔑 استعادة وتغيير كلمة المرور',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'أدخل بريدك الإلكتروني مع رمز الحماية الأبوي المكون من 4 أرقام (PIN) لتعيين كلمة مرور جديدة.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني أو رقم الهاتف',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: resetPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'رمز الحماية الأبوي (PIN - الافتراضي 1234)',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_clock_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 10),
                    Text(modalError!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                  if (modalSuccess != null) ...[
                    const SizedBox(height: 10),
                    Text(modalSuccess!,
                        style: const TextStyle(color: Color(0xFF14B8A6))),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14B8A6),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final err = await widget.appState.resetPassword(
                          emailOrPhone: resetEmailCtrl.text,
                          parentalPin: resetPinCtrl.text,
                          newPassword: newPassCtrl.text,
                        );
                        setModalState(() {
                          modalError = err;
                          modalSuccess = err == null
                              ? 'تم تحديث كلمة المرور بنجاح! يمكنك تسجيل الدخول الآن.'
                              : null;
                        });
                      },
                      child: const Text('تحديث كلمة المرور'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF14B8A6).withOpacity(0.5),
                        ),
                      ),
                      child:
                          const Text('🌙✨', style: TextStyle(fontSize: 38)),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'حنين كيدز — بوابة العائلة',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.5)),
                      ),
                      child: const Text(
                        '🎁 هدية الحساب الجديد: تجربة مجانية شاملة لمدة يوم كامل (٢٤ ساعة)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFDE68A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _openGoogleSignUpModal,
                        icon: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                        ),
                        label: Text(
                          _isLogin
                              ? 'الدخول السريع باستخدام حساب جوجل (Google)'
                              : 'تسجيل حساب جديد باستخدام جوجل (Google)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = false;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: !_isLogin
                                      ? const Color(0xFF14B8A6)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'حساب جديد (تجربة يوم)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = true;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: _isLogin
                                      ? const Color(0xFF14B8A6)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'تسجيل الدخول',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (!_isLogin) ...[
                      TextField(
                        controller: _fullNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم ولي الأمر',
                          hintText: 'مثال: أحمد محمد',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText:
                            'البريد الإلكتروني (لإرسال التنبيهات والاقتراحات)',
                        hintText: 'parent@haneenkids.com',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    if (!_isLogin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: 'رمز الحماية الأبوي (PIN من 4 أرقام)',
                          counterText: '',
                          prefixIcon: Icon(Icons.shield_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '👶 إعداد ملف الطفل الأول',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _childNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'اسم الطفل',
                                hintText: 'مثال: فارس أو نور',
                                prefixIcon: Icon(Icons.child_care),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedAgeGroup,
                              decoration: const InputDecoration(
                                labelText: 'الفئة العمرية للطفل',
                                prefixIcon: Icon(Icons.cake_outlined),
                              ),
                              items: _ageGroups
                                  .map((age) => DropdownMenuItem(
                                        value: age,
                                        child: Text(age),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedAgeGroup = val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'اختر الرمز التعبيري (Avatar) للطفل:',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _avatars.map((emoji) {
                                final isSelected = _selectedAvatar == emoji;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedAvatar = emoji),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF14B8A6)
                                              .withOpacity(0.3)
                                          : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF14B8A6)
                                            : Colors.white12,
                                        width: 2,
                                      ),
                                    ),
                                    child: Text(emoji,
                                        style: const TextStyle(fontSize: 22)),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'دقائق المشاهدة اليومية:',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.white70),
                                ),
                                Text(
                                  '$_initialDailyMinutes دقيقة يومياً',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14B8A6),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: _initialDailyMinutes.toDouble(),
                              min: 5,
                              max: 60,
                              divisions: 11,
                              activeColor: const Color(0xFF14B8A6),
                              onChanged: (v) => setState(
                                  () => _initialDailyMinutes = v.round()),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.redAccent.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isLogin
                                    ? 'دخول إلى التطبيق'
                                    : 'إنشاء الحساب وتفعيل تجربة ٢٤ ساعة',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _showForgotPasswordModal,
                          child: const Text(
                            'نسيت كلمة المرور؟',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _quickDemoLogin,
                          icon: const Icon(Icons.flash_on,
                              size: 18, color: Color(0xFFF59E0B)),
                          label: const Text(
                            'دخول سريع بحساب تجريبي',
                            style: TextStyle(color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MultiChildProfilesScreen extends StatefulWidget {
  final AppStateManager appState;
  const MultiChildProfilesScreen({super.key, required this.appState});

  @override
  State<MultiChildProfilesScreen> createState() =>
      _MultiChildProfilesScreenState();
}

class _MultiChildProfilesScreenState extends State<MultiChildProfilesScreen> {
  final List<String> _ageGroups = [
    '2–4 سنوات',
    '3–6 سنوات',
    '4–8 سنوات',
    '6–10 سنوات'
  ];
  final List<String> _avatars = [
    '🦁',
    '🦋',
    '🐰',
    '🐼',
    '🚀',
    '🌸',
    '🐬',
    '🦊',
    '🐯',
    '🦄'
  ];

  void _showAddChildDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    String selectedAge = '3–6 سنوات';
    String selectedAvatar = '🦁';
    int selectedMinutes = 20;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                right: 24,
                left: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '➕ إضافة ملف طفل جديد',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14B8A6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم الطفل',
                        hintText: 'مثال: سارة أو عمر',
                        prefixIcon: Icon(Icons.child_care),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedAge,
                      decoration: const InputDecoration(
                        labelText: 'الفئة العمرية',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      items: _ageGroups
                          .map((age) => DropdownMenuItem(
                                value: age,
                                child: Text(age),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedAge = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'اختر الرمز التعبيري (Avatar):',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _avatars.map((emoji) {
                        final isSelected = selectedAvatar == emoji;
                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedAvatar = emoji),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF14B8A6).withOpacity(0.3)
                                  : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF14B8A6)
                                    : Colors.white12,
                                width: 2,
                              ),
                            ),
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 24)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'دقائق المشاهدة اليومية:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '$selectedMinutes دقيقة / يومياً',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: selectedMinutes.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      activeColor: const Color(0xFF14B8A6),
                      onChanged: (val) =>
                          setModalState(() => selectedMinutes = val.round()),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          if (nameCtrl.text.trim().isEmpty) return;
                          widget.appState.addChildProfile(
                            name: nameCtrl.text,
                            age: selectedAge,
                            chosenAvatar: selectedAvatar,
                            dailyTimeLimit: selectedMinutes,
                          );
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'حفظ ملف الطفل',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.appState.currentAccount;
    if (account == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'من سيشاهد قصص حنين اليوم؟',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                widget.appState.selectChildAndEnterFeed(account.activeChildId),
            icon: const Icon(Icons.play_circle_fill, color: Color(0xFF14B8A6)),
            label: const Text(
              'المشغل',
              style: TextStyle(
                  color: Color(0xFF14B8A6), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_outlined,
                          color: Color(0xFFF59E0B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'حالة الاشتراك: ${account.subscriptionStatusLabel}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParentalStudioScreen(
                          appState: widget.appState,
                          initialTabIndex: 0,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF1E293B)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF14B8A6)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.phonelink_lock_rounded,
                            color: Color(0xFFF59E0B), size: 28),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📲 وضع هاتف ولي الأمر: المراقبة الحية وقفل موبايل الطفل عن بُعد',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'شاهد ماذا يفعل طفلك الآن على التطبيق واقفل شاشة موبايله بضغطة زر من موبايلك',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 16, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'مرحباً بك يا ${account.fullName} 👋 اختر ملف الطفل للبدء أو أضف طفلاً جديداً:',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.86,
                    ),
                    itemCount: account.children.length + 1,
                    itemBuilder: (context, index) {
                      if (index == account.children.length) {
                        return GestureDetector(
                          onTap: _showAddChildDialog,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFF14B8A6).withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Color(0xFF14B8A6),
                                  child: Icon(Icons.add,
                                      size: 34, color: Colors.white),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'إضافة طفل جديد',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'تخصيص العمر والوقت',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final child = account.children[index];
                      final isSelected = child.id == account.activeChildId;
                      return GestureDetector(
                        onTap: () =>
                            widget.appState.selectChildAndEnterFeed(child.id),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF14B8A6).withOpacity(0.18)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF14B8A6)
                                  : Colors.white12,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                child.chosenAvatar,
                                style: const TextStyle(fontSize: 50),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                child.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                child.age,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '⏱️ ${child.usedMinutesToday}/${child.dailyTimeLimit} د • ⭐ ${child.starsEarned}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VerticalVideoFeedPlayerScreen extends StatefulWidget {
  final AppStateManager appState;
  const VerticalVideoFeedPlayerScreen({super.key, required this.appState});

  @override
  State<VerticalVideoFeedPlayerScreen> createState() =>
      _VerticalVideoFeedPlayerScreenState();
}

class _VerticalVideoFeedPlayerScreenState
    extends State<VerticalVideoFeedPlayerScreen> {
  final PageController _pageController = PageController();
  String _selectedCategory = 'all';
  int _currentVideoIndex = 0;

  List<VideoModel> get _filteredVideos {
    final all = widget.appState.videos;
    if (_selectedCategory == 'all') return all;
    return all.where((v) => v.category == _selectedCategory).toList();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentVideoIndex = index;
    });
    final videos = _filteredVideos;
    final String? title =
        (index >= 0 && index < videos.length) ? videos[index].title : null;
    widget.appState.recordVideoTransitionWatched(videoTitle: title);
  }

  void _openBrainGamesHub() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrainGamesHubScreen(appState: widget.appState),
      ),
    );
  }

  void _jumpToSuggestedVideo(VideoModel target) {
    setState(() {
      _selectedCategory = 'all';
    });
    final int idx =
        widget.appState.videos.indexWhere((v) => v.id == target.id);
    if (idx != -1 && _pageController.hasClients) {
      _pageController.jumpToPage(idx);
      setState(() {
        _currentVideoIndex = idx;
      });
    }
  }

  void _openSmartVoiceAssistantModal() {
    final child = widget.appState.currentAccount?.activeChild;
    final String childName = child?.name ?? 'بطل حنين';
    widget.appState.triggerVoiceAssistantGreetingAndSuggestion();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final suggested = widget.appState.suggestedVideoForChild ??
                widget.appState.videos.first;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14B8A6).withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF14B8A6), width: 2),
                        ),
                        child: const Text('🤖💬',
                            style: TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المساعد الذكي — نصوص عائمة ($childName)',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'يظهر رسائل تشجيعية ونصائح عائمة هادئة على الشاشة بدون صوت',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF14B8A6)),
                    ),
                    child: Text(
                      widget.appState.currentAssistantBannerMessage,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '✨ القصة المقترحة لك الآن:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: ListTile(
                      leading: Text(suggested.emoji,
                          style: const TextStyle(fontSize: 34)),
                      title: Text(
                        suggested.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${VideoModel.getCategoryDisplayLabel(suggested.category)} • ${suggested.ageGroup}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _jumpToSuggestedVideo(suggested);
                        },
                        child: const Text('شاهد الآن'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '🎧 اطلب من المساعد الصوتي أن يساعدك:',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xFF0F172A),
                        avatar: const Text('🌙'),
                        label: const Text('اقترح قصة نوم هادئة'),
                        onPressed: () {
                          final bedtimeVideo =
                              widget.appState.videos.firstWhere(
                            (v) => v.category == 'bedtime',
                            orElse: () => widget.appState.videos.first,
                          );
                          setModalState(() {
                            widget.appState.suggestedVideoForChild =
                                bedtimeVideo;
                            widget.appState.currentAssistantBannerMessage =
                                'اخترت لك قصة النوم الهادئة «${bedtimeVideo.title}». تنفس بعمق واستمع بهدوء يا $childName.';
                          });
                          CalmVoiceService.instance.speakCalmly(
                            widget.appState.currentAssistantBannerMessage,
                          );
                        },
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF0F172A),
                        avatar: const Text('🗣️'),
                        label: const Text('دربني على جملة عربية فصيحة'),
                        onPressed: () {
                          final arabicVideo = widget.appState.videos.firstWhere(
                            (v) => v.category == 'arabic',
                            orElse: () => widget.appState.videos.first,
                          );
                          setModalState(() {
                            widget.appState.suggestedVideoForChild =
                                arabicVideo;
                            widget.appState.currentAssistantBannerMessage =
                                'هيا نردد معاً بهدوء: ${arabicVideo.repeatPhrase}';
                          });
                          CalmVoiceService.instance.speakCalmly(
                            'هيا نردد معاً بهدوء يا $childName: ${arabicVideo.repeatPhrase}',
                            rate: 0.34,
                          );
                        },
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF0F172A),
                        avatar: const Text('🧘'),
                        label: const Text('تمرين التنفس والهدوء'),
                        onPressed: () {
                          const calmBreathing =
                              'يا بطل حنين، خذ شهيقاً عميقاً وهادئاً من أنفك كأنك تشم وردة جميلة... والآن أخرج الهواء ببطء وابتسم!';
                          setModalState(() {
                            widget.appState.currentAssistantBannerMessage =
                                calmBreathing;
                          });
                          CalmVoiceService.instance.speakCalmly(
                            calmBreathing,
                            rate: 0.34,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openRepeatWithMeModal(VideoModel item) {
    bool isListeningMic = false;
    final TextEditingController spokenCtrl = TextEditingController();
    PronunciationEvaluation? evaluation;

    CalmVoiceService.instance.speakCalmly(
      'استمع جيداً يا بطل ثم ردد معي بهدوء: ${item.repeatPhrase}',
      rate: 0.35,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> verifyAndSpeakCorrection() async {
              final result = CalmVoiceService.evaluatePronunciation(
                targetPhrase: item.repeatPhrase,
                spokenText: spokenCtrl.text,
              );
              setModalState(() {
                evaluation = result;
              });

              if (result.isCorrect) {
                await CalmVoiceService.instance.speakCalmly(
                  '${result.correctionAdvice} هيا نرددها معاً مرة أخرى بصوت هادئ: ${item.repeatPhrase}',
                  rate: 0.36,
                );
              } else {
                await CalmVoiceService.instance.speakCalmly(
                  '${result.correctionAdvice} استمع لي وردد معي كلمة بكلمة: ${item.repeatPhrase}',
                  rate: 0.32,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                right: 24,
                left: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14B8A6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () {
                            CalmVoiceService.instance.speakCalmly(
                              item.repeatPhrase,
                              rate: 0.33,
                              allowSpeechForRepeatGame: true,
                            );
                          },
                          icon: const Icon(Icons.hearing_rounded),
                          label: const Text('استمع للنطق الهادئ 🔊'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59E0B),
                            side: const BorderSide(color: Color(0xFFF59E0B)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () {
                            CalmVoiceService.instance.speakCalmly(
                              'هيا نقرأ معاً ببطء وهدوء: ${item.repeatPhrase}',
                              rate: 0.30,
                              allowSpeechForRepeatGame: true,
                            );
                          },
                          icon: const Icon(Icons.record_voice_over_rounded),
                          label: const Text('ردد معي بالصوت الهادئ'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF14B8A6)),
                      ),
                      child: Text(
                        item.repeatPhrase,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        if (isListeningMic) {
                          await CalmVoiceService.instance.stopListening();
                          setModalState(() => isListeningMic = false);
                          await verifyAndSpeakCorrection();
                          return;
                        }
                        setModalState(() {
                          isListeningMic = true;
                        });
                        final bool sttReady = await CalmVoiceService.instance
                            .initSpeechRecognition();
                        if (sttReady) {
                          await CalmVoiceService.instance.startListening(
                            onResult: (words) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  spokenCtrl.text = words;
                                });
                              }
                            },
                          );
                          await Future.delayed(const Duration(seconds: 4));
                          await CalmVoiceService.instance.stopListening();
                          if (ctx.mounted) {
                            setModalState(() => isListeningMic = false);
                            if (spokenCtrl.text.trim().isNotEmpty) {
                              await verifyAndSpeakCorrection();
                            }
                          }
                        } else {
                          await Future.delayed(const Duration(seconds: 2));
                          if (ctx.mounted) {
                            setModalState(() {
                              isListeningMic = false;
                              if (spokenCtrl.text.trim().isEmpty) {
                                spokenCtrl.text = item.repeatPhrase;
                              }
                            });
                            await verifyAndSpeakCorrection();
                          }
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isListeningMic
                              ? Colors.redAccent.withOpacity(0.25)
                              : const Color(0xFFF59E0B).withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isListeningMic
                                ? Colors.redAccent
                                : const Color(0xFFF59E0B),
                            width: 2.5,
                          ),
                        ),
                        child: Icon(
                          isListeningMic ? Icons.mic : Icons.mic_none_rounded,
                          size: 44,
                          color: isListeningMic
                              ? Colors.redAccent
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isListeningMic
                          ? '🎙️ تحدث الآن بصوت واضح... أنا أستمع لنطقك'
                          : 'اضغط على الميكروفون للتحدث أو راجع ما سمعه التطبيق أدناه:',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: spokenCtrl,
                            decoration: InputDecoration(
                              labelText: 'ما نطقه الطفل (التعرف الصوتي)',
                              hintText: 'انطق بالميكروفون أو اكتب لتجربة المصحح',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.check_circle_outline,
                                    color: Color(0xFF14B8A6)),
                                onPressed: verifyAndSpeakCorrection,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              spokenCtrl.text = item.repeatPhrase;
                            });
                            verifyAndSpeakCorrection();
                          },
                          icon: const Icon(Icons.done_all, size: 16),
                          label: const Text('محاكاة نطق متقن ١٠٠٪',
                              style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final words = CalmVoiceService.normalizeArabicText(
                                    item.repeatPhrase)
                                .split(' ');
                            setModalState(() {
                              spokenCtrl.text =
                                  words.isNotEmpty ? words.first : '';
                            });
                            verifyAndSpeakCorrection();
                          },
                          icon: const Icon(Icons.build_circle_outlined,
                              size: 16),
                          label: const Text('محاكاة نطق ناقص للتصحيح',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (evaluation != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: evaluation!.isCorrect
                              ? const Color(0xFF14B8A6).withOpacity(0.18)
                              : const Color(0xFFF59E0B).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: evaluation!.isCorrect
                                ? const Color(0xFF14B8A6)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  evaluation!.isCorrect
                                      ? '✅ نطق صحيح ومتقن!'
                                      : '🔄 يحتاج لتعديل بسيط وهادئ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'الدقة: ${(evaluation!.accuracyScore * 100).round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              evaluation!.correctionAdvice,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (evaluation?.isCorrect ?? false)
                              ? const Color(0xFF14B8A6)
                              : const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (evaluation?.isCorrect ?? false)
                            ? () {
                                widget.appState.awardStarAndRecordActivity(
                                  'phrase_${item.id}',
                                  isPronunciation: true,
                                );
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '🎉 أحسنت النطق العربي الصحيح يا بطل! ربحت نجمة الفصاحة ⭐'),
                                    backgroundColor: Color(0xFF14B8A6),
                                  ),
                                );
                              }
                            : verifyAndSpeakCorrection,
                        icon: Icon((evaluation?.isCorrect ?? false)
                            ? Icons.star
                            : Icons.graphic_eq),
                        label: Text(
                          (evaluation?.isCorrect ?? false)
                              ? 'تم التأكد من صحة النطق! استلم نجمتك ⭐'
                              : 'تحقق من صحة النطق واستمع للتصحيح الهادئ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openRealWorldHeroActivityModal(VideoModel item) {
    CalmVoiceService.instance.speakCalmly(
      'نشاط البطل الواقعي: ${item.activeActivity}',
      rate: 0.38,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎯🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 10),
              const Text(
                'نافذة «نشاط البطل الواقعي»',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14B8A6),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'مهمة حركية وتربوية ممتعة لتقوم بها خارج الشاشة الآن:',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  item.activeActivity,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    widget.appState
                        .awardStarAndRecordActivity('activity_${item.id}');
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            '🌟 بطل حقيقي! أضفنا نجمة جديدة إلى رصيدك بعد إنجاز النشاط!'),
                        backgroundColor: Color(0xFFF59E0B),
                      ),
                    );
                  },
                  icon: const Icon(Icons.emoji_events),
                  label: const Text(
                    'أنجزت النشاط الواقعي! (+1 نجمة ⭐)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openParentalGateDialog({int initialTab = 0}) {
    final random = Random();
    final int a = random.nextInt(6) + 4;
    final int b = random.nextInt(5) + 3;
    final int expected = a * b;
    final TextEditingController answerCtrl = TextEditingController();
    String? gateError;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'بوابة الوالدين المحمية',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'للدخول إلى استوديو الفيديوهات والاشتراكات والتنبيهات، حل المعادلة أو أدخل الرمز السري (PIN):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'كم ناتج:  $a × $b = ؟',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF14B8A6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: answerCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: 'أدخل ناتج المعادلة أو رمز PIN',
                    ),
                  ),
                  if (gateError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      gateError!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final input = answerCtrl.text.trim();
                    final pin =
                        widget.appState.currentAccount?.parentalPin ?? '1234';
                    if (input == expected.toString() || input == pin) {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentalStudioScreen(
                            appState: widget.appState,
                            initialTabIndex: initialTab,
                          ),
                        ),
                      );
                    } else {
                      setDialogState(() {
                        gateError = 'الإجابة أو رمز PIN غير صحيح.';
                      });
                    }
                  },
                  child: const Text('دخول استوديو الوالدين'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.appState.currentAccount!;
    final activeChild = account.activeChild;
    final videos = _filteredVideos;
    final bool sleepCurtainActive = widget.appState.isDailyLimitReached;
    final bool subscriptionExpired = widget.appState.isSubscriptionExpired;
    final bool remotelyLockedByParent = activeChild.isDeviceRemotelyLocked;

    return Scaffold(
      body: Stack(
        children: [
          if (videos.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📭', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد قصص في هذا القسم حالياً',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedCategory = 'all'),
                    child: const Text('عرض كل القصص'),
                  ),
                ],
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: videos.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final item = videos[index];
                final isCurrentPage = index == _currentVideoIndex &&
                    !sleepCurtainActive &&
                    !subscriptionExpired &&
                    !remotelyLockedByParent;
                return VerticalVideoFeedItemWidget(
                  key: ValueKey('${item.id}_$index'),
                  video: item,
                  isActive: isCurrentPage,
                  onLikeTap: () => widget.appState.toggleLikeVideo(item),
                  onRepeatPhraseTap: () => _openRepeatWithMeModal(item),
                  onHeroActivityTap: () =>
                      _openRealWorldHeroActivityModal(item),
                  onVoiceAssistantTap: _openSmartVoiceAssistantModal,
                  onBrainGamesTap: _openBrainGamesHub,
                );
              },
            ),

          if (account.warmEveningFilter)
            IgnorePointer(
              child: Container(
                color: const Color(0xFFFF8F00).withOpacity(0.20),
              ),
            ),

          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: widget.appState.openChildProfilesScreen,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(activeChild.chosenAvatar,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                activeChild.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.swap_horiz, size: 13),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFF59E0B).withOpacity(0.45),
                              width: 0.8),
                        ),
                        child: Text(
                          '⭐ ${activeChild.starsEarned}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: Text(
                          '⏱️ ${activeChild.usedMinutesToday}/${activeChild.dailyTimeLimit}د',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _openBrainGamesHub,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7).withOpacity(0.82),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🧠', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 3),
                              Text(
                                'الذكاء (${activeChild.intelligencePoints})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _openSmartVoiceAssistantModal,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.assistant_rounded,
                            size: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => widget.appState.toggleWarmEveningFilter(),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: account.warmEveningFilter
                                ? const Color(0xFFF59E0B)
                                : Colors.black.withOpacity(0.45),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Icon(
                            Icons.wb_twilight_rounded,
                            size: 14,
                            color: account.warmEveningFilter
                                ? Colors.black87
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _openParentalGateDialog(initialTab: 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF14B8A6).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 3),
                              Text(
                                'الوالدين',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  height: 28,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: kVideoCategories.length,
                    itemBuilder: (ctx, i) {
                      final cat = kVideoCategories[i];
                      final isSelected = _selectedCategory == cat['id'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = cat['id']!;
                            _currentVideoIndex = 0;
                          });
                          if (_pageController.hasClients) {
                            _pageController.jumpToPage(0);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF14B8A6)
                                : Colors.black.withOpacity(0.38),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF14B8A6)
                                  : Colors.white24,
                              width: 0.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${cat['icon']} ${cat['title']}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: GestureDetector(
                    onTap: _openSmartVoiceAssistantModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1E293B).withOpacity(0.78),
                            const Color(0xFF0F172A).withOpacity(0.72),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF38BDF8).withOpacity(0.5),
                            width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const Text('💬✨', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.appState.currentAssistantBannerMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'نص عائم ✨',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFBAE6FD),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                  child: CuteSuperheroCompanionBanner(
                    appState: widget.appState,
                    compactMode: true,
                  ),
                ),
              ],
            ),
          ),

          if (sleepCurtainActive)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🌙💤✨', style: TextStyle(fontSize: 68)),
                      const SizedBox(height: 20),
                      Text(
                        'ستارة النوم الهادئة — تصبح على خير يا ${activeChild.name}!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'انتهت حصتك اليومية (${activeChild.dailyTimeLimit} دقيقة) بهدوء، وجمعت ⭐ ${activeChild.starsEarned} نجوم رائعة! حان الآن وقت إراحة العينين والاستعداد للنوم الجميل.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _openParentalGateDialog(initialTab: 2),
                        icon: const Icon(Icons.lock_open),
                        label: const Text(
                          'بوابة الوالدين (لتمديد الوقت أو تغيير الطفل)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (subscriptionExpired && !sleepCurtainActive)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🎁👑', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      const Text(
                        'انتهت فترة التجربة المجانية (٢٤ ساعة)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'استمتع طفلك بقصص حنين الهادئة والمصحح الصوتي! يمكنك الآن اختيار الباقة المرنة الأنسب لعائلتك والدفع بسهولة عبر فودافون كاش أو أورنج كاش أو اتصالات كاش أو إنستا باي أو فيزا.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _openParentalGateDialog(initialTab: 2),
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text(
                          'استعراض باقات الاشتراك ووسائل الدفع المصرية',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (remotelyLockedByParent)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF31102F), Color(0xFF0F172A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.redAccent, width: 2.5),
                        ),
                        child: const Icon(
                          Icons.phonelink_lock_rounded,
                          size: 68,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '🔒 تم قفل شاشة الموبايل عن بُعد يا ${activeChild.name}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          activeChild.remoteLockReasonMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Color(0xFFFDE68A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _openParentalGateDialog(initialTab: 0),
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text(
                          'فتح القفل الأبوي (بوابة الوالدين / الرمز السري)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VerticalVideoFeedItemWidget extends StatefulWidget {
  final VideoModel video;
  final bool isActive;
  final VoidCallback onLikeTap;
  final VoidCallback onRepeatPhraseTap;
  final VoidCallback onHeroActivityTap;
  final VoidCallback onVoiceAssistantTap;
  final VoidCallback onBrainGamesTap;

  const VerticalVideoFeedItemWidget({
    super.key,
    required this.video,
    required this.isActive,
    required this.onLikeTap,
    required this.onRepeatPhraseTap,
    required this.onHeroActivityTap,
    required this.onVoiceAssistantTap,
    required this.onBrainGamesTap,
  });

  @override
  State<VerticalVideoFeedItemWidget> createState() =>
      _VerticalVideoFeedItemWidgetState();
}

class _VerticalVideoFeedItemWidgetState
    extends State<VerticalVideoFeedItemWidget> {
  VideoPlayerController? _videoController;
  VideoPlayerController? _audioController;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isMuted = false;
  late String _fitMode;

  @override
  void initState() {
    super.initState();
    _fitMode = widget.video.autoFitMode;
    _initVideoPlayer();
  }

  @override
  void didUpdateWidget(covariant VerticalVideoFeedItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.streamUrl != widget.video.streamUrl) {
      _fitMode = widget.video.autoFitMode;
      _disposeController();
      _initVideoPlayer();
    } else if (oldWidget.isActive != widget.isActive && _isInitialized) {
      if (widget.isActive) {
        _videoController?.play();
        _audioController?.play();
      } else {
        _videoController?.pause();
        _audioController?.pause();
      }
    }
  }

  static String normalizeStreamOrLocalUrl(String rawUrl) {
    final String trimmed = rawUrl.trim();
    final RegExp driveRegex =
        RegExp(r'drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)');
    final match = driveRegex.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      final String fileId = match.group(1)!;
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }
    return trimmed;
  }

  Future<void> _initVideoPlayer() async {
    final raw = widget.video.streamUrl.trim();
    if (raw.isEmpty) {
      setState(() => _hasError = true);
      return;
    }

    String url = normalizeStreamOrLocalUrl(raw);

    String separateAudioUrl = widget.video.audioStreamUrl.trim();

    if ((SmartVideoLinkAutoImporter.isYouTubeUrl(url) &&
            !url.contains('googlevideo.com')) ||
        (SmartVideoLinkAutoImporter.isTikTokUrl(url) &&
            !url.contains('tikwm.com'))) {
      final resolvedMeta = await SmartVideoLinkAutoImporter
          .fetchHighDefStreamAndExactMetadata(url);
      if (resolvedMeta.hdStreamUrl != null &&
          resolvedMeta.hdStreamUrl!.isNotEmpty) {
        url = resolvedMeta.hdStreamUrl!;
        widget.video.streamUrl = url;
        if (resolvedMeta.separateAudioStreamUrl != null) {
          separateAudioUrl = resolvedMeta.separateAudioStreamUrl!;
          widget.video.audioStreamUrl = separateAudioUrl;
        }
      }
    }

    try {
      VideoPlayerController ctrl;
      if (url.startsWith('/') || url.startsWith('file://')) {
        final String filePath =
            url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        ctrl = VideoPlayerController.file(File(filePath));
      } else {
        final VideoFormat? formatHint =
            url.toLowerCase().contains('.m3u8') ? VideoFormat.hls : null;
        ctrl = VideoPlayerController.networkUrl(
          Uri.parse(url),
          formatHint: formatHint,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            'Referer': 'https://www.tiktok.com/',
          },
        );
      }
      _videoController = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);

      if (separateAudioUrl.isNotEmpty && separateAudioUrl.startsWith('http')) {
        try {
          final audioCtrl = VideoPlayerController.networkUrl(
            Uri.parse(separateAudioUrl),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            httpHeaders: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
            },
          );
          _audioController = audioCtrl;
          await audioCtrl.initialize();
          await audioCtrl.setLooping(true);
        } catch (_) {
          _audioController = null;
        }
      }

      if (widget.isActive) {
        await ctrl.play();
        await _audioController?.play();
      }
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (_) {
      if (widget.video.originalSourceUrl.isNotEmpty) {
        try {
          final refreshed = await SmartVideoLinkAutoImporter
              .fetchHighDefStreamAndExactMetadata(
                  widget.video.originalSourceUrl);
          if (refreshed.hdStreamUrl != null &&
              refreshed.hdStreamUrl!.isNotEmpty &&
              refreshed.hdStreamUrl != url) {
            widget.video.streamUrl = refreshed.hdStreamUrl!;
            widget.video.audioStreamUrl =
                refreshed.separateAudioStreamUrl ?? '';
            final retryCtrl = VideoPlayerController.networkUrl(
              Uri.parse(refreshed.hdStreamUrl!),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
              httpHeaders: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
              },
            );
            _videoController = retryCtrl;
            await retryCtrl.initialize();
            await retryCtrl.setLooping(true);
            if (widget.isActive) {
              await retryCtrl.play();
            }
            if (mounted) {
              setState(() {
                _isInitialized = true;
                _hasError = false;
              });
            }
            return;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _cycleVideoFitMode() {
    setState(() {
      if (_fitMode == 'auto_cover') {
        _fitMode = 'cover_force';
      } else if (_fitMode == 'cover_force') {
        _fitMode = 'contain';
      } else if (_fitMode == 'contain') {
        _fitMode = 'fill';
      } else {
        _fitMode = 'auto_cover';
      }
      widget.video.autoFitMode = _fitMode;
    });
  }

  bool _showFullDescription = false;

  BoxFit _resolveBoxFit() {
    if (_fitMode == 'contain') return BoxFit.contain;
    if (_fitMode == 'fill') return BoxFit.fill;
    if (_fitMode == 'cover_force') return BoxFit.cover;

    final ctrl = _videoController;
    if (ctrl != null && _isInitialized) {
      final double w = ctrl.value.size.width;
      final double h = ctrl.value.size.height;
      if (w > 0 && h > 0 && (w / h) > 1.05) {
        return BoxFit.contain;
      }
    }
    return BoxFit.cover;
  }

  String _liveResolutionLabel() {
    final ctrl = _videoController;
    if (ctrl != null && _isInitialized && ctrl.value.size.height > 0) {
      final int h = ctrl.value.size.height.round();
      final int w = ctrl.value.size.width.round();
      final int shortSide = min(w, h);
      if (shortSide >= 1080) return '1080p Full HD';
      if (shortSide >= 720) return '720p HD';
      return '${shortSide}p';
    }
    return widget.video.qualityBadge;
  }

  String _fitModeLabel() {
    switch (_fitMode) {
      case 'cover_force':
        return 'ملء كامل';
      case 'contain':
        return 'أبعاد أصلية';
      case 'fill':
        return 'تمدد كامل';
      case 'auto_cover':
      default:
        return 'مقاس ذكي HD';
    }
  }

  void _disposeController() {
    _videoController?.dispose();
    _videoController = null;
    _audioController?.dispose();
    _audioController = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _togglePlayPause() {
    final ctrl = _videoController;
    if (ctrl == null || !_isInitialized) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
        _audioController?.pause();
      } else {
        if (_audioController != null) {
          _audioController!.seekTo(ctrl.value.position);
          _audioController!.play();
        }
        ctrl.play();
      }
    });
  }

  void _toggleMute() {
    final ctrl = _videoController;
    if (ctrl == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      ctrl.setVolume(_isMuted ? 0.0 : 1.0);
      _audioController?.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.video;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [item.bgGradientStart, item.bgGradientEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isInitialized && _videoController != null)
              SizedBox.expand(
                child: ClipRect(
                  child: FittedBox(
                    fit: _resolveBoxFit(),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: _videoController!.value.size.width > 0
                          ? _videoController!.value.size.width
                          : 1080,
                      height: _videoController!.value.size.height > 0
                          ? _videoController!.value.size.height
                          : 1920,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.emoji, style: const TextStyle(fontSize: 76)),
                      const SizedBox(height: 16),
                      if (!_hasError) ...[
                        const CircularProgressIndicator(
                            color: Color(0xFF14B8A6)),
                        const SizedBox(height: 12),
                        const Text(
                          'جاري تحضير البث المرئي الهادئ...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ] else ...[
                        const Text(
                          'وضع القصة المصورة الهادئة',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _initVideoPlayer,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('إعادة تحميل بث الفيديو'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.35),
                      Colors.transparent,
                      Colors.black.withOpacity(0.82),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            if (_isInitialized &&
                _videoController != null &&
                !_videoController!.value.isPlaying)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            Positioned(
              left: 10,
              bottom: 78,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SideActionButton(
                    icon: item.isLiked ? Icons.favorite : Icons.favorite_border,
                    iconColor: item.isLiked ? Colors.redAccent : Colors.white,
                    label: '${item.likes}',
                    onTap: widget.onLikeTap,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: Icons.mic_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    label: 'ردد معي',
                    onTap: widget.onRepeatPhraseTap,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: Icons.emoji_events_rounded,
                    iconColor: const Color(0xFF14B8A6),
                    label: 'نشاط البطل',
                    onTap: widget.onHeroActivityTap,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: Icons.psychology_rounded,
                    iconColor: const Color(0xFFC084FC),
                    label: 'ألعاب الذكاء',
                    onTap: widget.onBrainGamesTap,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: Icons.assistant_rounded,
                    iconColor: const Color(0xFF38BDF8),
                    label: 'مساعد ذكي',
                    onTap: widget.onVoiceAssistantTap,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: Icons.aspect_ratio_rounded,
                    iconColor: const Color(0xFFA7F3D0),
                    label: _fitModeLabel(),
                    onTap: _cycleVideoFitMode,
                  ),
                  const SizedBox(height: 8),
                  _SideActionButton(
                    icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                    iconColor: Colors.white,
                    label: _isMuted ? 'صامت' : 'الصوت',
                    onTap: _toggleMute,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              left: 68,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14B8A6).withOpacity(0.22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF14B8A6).withOpacity(0.5)),
                        ),
                        child: Text(
                          VideoModel.getCategoryDisplayLabel(item.category),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '🎂 ${item.ageGroup}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFF59E0B).withOpacity(0.6)),
                        ),
                        child: Text(
                          '✨ ${_liveResolutionLabel()}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFDE68A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(
                        () => _showFullDescription = !_showFullDescription),
                    child: Text(
                      item.description,
                      maxLines: _showFullDescription ? 10 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: widget.onRepeatPhraseTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic,
                              size: 13, color: Color(0xFFFDE68A)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'ردد معي: ${item.repeatPhrase}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isInitialized && _videoController != null)
              Positioned(
                right: 0,
                left: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF14B8A6),
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _SideActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.38),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 0.8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class ParentalStudioScreen extends StatefulWidget {
  final AppStateManager appState;
  final int initialTabIndex;
  const ParentalStudioScreen({
    super.key,
    required this.appState,
    this.initialTabIndex = 0,
  });

  @override
  State<ParentalStudioScreen> createState() => _ParentalStudioScreenState();
}

class _ParentalStudioScreenState extends State<ParentalStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<FormState> _manualVideoFormKey = GlobalKey<FormState>();

  late TextEditingController _remoteUrlCtrl;
  final TextEditingController _smartLinkImportCtrl = TextEditingController();
  bool _isSmartImporting = false;
  VideoModel? _lastAutoGeneratedPreview;
  final TextEditingController _vTitleCtrl = TextEditingController();
  final TextEditingController _vDescCtrl = TextEditingController();
  final TextEditingController _vUrlCtrl = TextEditingController();
  final TextEditingController _vPhraseCtrl = TextEditingController();
  final TextEditingController _vActivityCtrl = TextEditingController();
  final TextEditingController _vEmojiCtrl = TextEditingController(text: '🌟');
  String _vCategory = 'bedtime';
  String _vAgeGroup = '3–6 سنوات';

  final TextEditingController _newChildNameCtrl = TextEditingController();
  String _newChildAge = '3–6 سنوات';
  String _newChildAvatar = '🐰';
  int _newChildDailyLimit = 20;

  final TextEditingController _parentSuggestionInputCtrl =
      TextEditingController();

  late TextEditingController _authApiCtrl;
  late TextEditingController _emailWebhookCtrl;
  late TextEditingController _paymentApiCtrl;
  late TextEditingController _merchantKeyCtrl;
  late TextEditingController _pinUpdateCtrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
    _remoteUrlCtrl =
        TextEditingController(text: widget.appState.remoteFeedUrl);
    _authApiCtrl = TextEditingController(text: widget.appState.authApiUrl);
    _emailWebhookCtrl =
        TextEditingController(text: widget.appState.emailWebhookUrl);
    _paymentApiCtrl =
        TextEditingController(text: widget.appState.paymentVerifyApiUrl);
    _merchantKeyCtrl =
        TextEditingController(text: widget.appState.merchantSecretKey);
    _pinUpdateCtrl = TextEditingController(
        text: widget.appState.currentAccount?.parentalPin ?? '1234');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _remoteUrlCtrl.dispose();
    _smartLinkImportCtrl.dispose();
    _vTitleCtrl.dispose();
    _vDescCtrl.dispose();
    _vUrlCtrl.dispose();
    _vPhraseCtrl.dispose();
    _vActivityCtrl.dispose();
    _vEmojiCtrl.dispose();
    _newChildNameCtrl.dispose();
    _parentSuggestionInputCtrl.dispose();
    _authApiCtrl.dispose();
    _emailWebhookCtrl.dispose();
    _paymentApiCtrl.dispose();
    _merchantKeyCtrl.dispose();
    _pinUpdateCtrl.dispose();
    super.dispose();
  }

  void _openEgyptianPaymentCheckoutSheet(SubscriptionPlanModel plan) {
    if (plan.priceEgp == 0) {
      widget.appState.activateOrResetOneDayTrial();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎁 تم تفعيل الفترة التجريبية المجانية لمدة ٢٤ ساعة!'),
          backgroundColor: Color(0xFF14B8A6),
        ),
      );
      return;
    }

    EgyptianPaymentMethodInfo selectedMethod = kEgyptianPaymentMethods.first;
    final TextEditingController walletOrIpaCtrl = TextEditingController();
    final TextEditingController transferRefCtrl = TextEditingController();
    final TextEditingController cardHolderCtrl = TextEditingController();
    final TextEditingController cardNumCtrl = TextEditingController();
    final TextEditingController cardExpiryCtrl = TextEditingController();
    final TextEditingController cardCvvCtrl = TextEditingController();
    final TextEditingController userOtpInputCtrl = TextEditingController();

    String? generatedBankOtp;
    bool otpDispatched = false;
    bool simulateBankRejection = false;
    bool isVerifyingPayment = false;
    String? verificationMessage;
    bool isErrorMessage = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bool isCard = selectedMethod.id == 'visa_mastercard';
            final bool isInstaPay = selectedMethod.id == 'instapay';

            String? validateStepOneInputs() {
              if (isCard) {
                return StrictEgyptianPaymentValidator.validateBankCard(
                  cardNumber: cardNumCtrl.text,
                  expiry: cardExpiryCtrl.text,
                  cvv: cardCvvCtrl.text,
                  cardHolderName: cardHolderCtrl.text,
                );
              } else if (isInstaPay) {
                final err = StrictEgyptianPaymentValidator
                    .validateInstaPayIdentifier(walletOrIpaCtrl.text);
                if (err != null) return err;
                if (transferRefCtrl.text.trim().length < 6) {
                  return 'يرجى إدخال رقم مرجع التحويل اللحظي في إنستا باي (٦ أرقام/حروف على الأقل) بعد إتمام التحويل.';
                }
                return null;
              } else {
                final err =
                    StrictEgyptianPaymentValidator.validateWalletPrefix(
                  selectedMethod.id,
                  walletOrIpaCtrl.text,
                );
                if (err != null) return err;
                if (transferRefCtrl.text.trim().length < 6) {
                  return 'يرجى إدخال رقم العملية / مرجع التحويل من رسالة ${selectedMethod.nameAr} (٦ أرقام على الأقل).';
                }
                return null;
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                right: 22,
                left: 22,
                top: 22,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '🔒 بوابة الدفع والتحقق الفعلي — ${plan.title}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${plan.priceEgp} ج.م',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              size: 18, color: Color(0xFF14B8A6)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'حماية صارمة: لن يتم تفعيل الباقة إلا بعد التحقق الفعلي من بيانات الدفع ورقم المرجع وكود التفويض البنكي (OTP).',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '١. اختر وسيلة الدفع المصرية:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    ...kEgyptianPaymentMethods.map((method) {
                      final isSelected = selectedMethod.id == method.id;
                      return GestureDetector(
                        onTap: () => setModalState(() {
                          selectedMethod = method;
                          verificationMessage = null;
                          otpDispatched = false;
                          generatedBankOtp = null;
                          userOtpInputCtrl.clear();
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? method.brandColor.withOpacity(0.18)
                                : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? method.brandColor
                                  : Colors.white12,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: method.brandColor,
                                radius: 17,
                                child: Icon(method.icon,
                                    color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      method.nameAr,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'حساب الاستقبال: ${method.merchantAccountNumber}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFFDE68A)),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle,
                                    color: Color(0xFF14B8A6)),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selectedMethod.brandColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: selectedMethod.brandColor.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isCard
                                  ? 'أدخل بيانات البطاقة البنكية (١٦ رقماً تخضع لفحص Luhn البنكي وتاريخ سارٍ)'
                                  : 'حوّل مبلغ ${plan.priceEgp} ج.م إلى (${selectedMethod.merchantAccountNumber}) ثم أدخل رقمك ورقم مرجع التحويل:',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text: selectedMethod.merchantAccountNumber));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '📋 تم نسخ رقم/عنوان الاستقبال: ${selectedMethod.merchantAccountNumber}'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy,
                                size: 18, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isCard) ...[
                      TextField(
                        controller: walletOrIpaCtrl,
                        keyboardType: isInstaPay
                            ? TextInputType.emailAddress
                            : TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: isInstaPay
                              ? 'عنوان الدفع (IPA مثل name@instapay) أو رقم هاتفك'
                              : 'رقم محفظتك المحوّل منها (${selectedMethod.nameAr})',
                          hintText: isInstaPay
                              ? 'ahmed@instapay'
                              : selectedMethod.id == 'vodafone_cash'
                                  ? '01012345678'
                                  : selectedMethod.id == 'orange_cash'
                                      ? '01212345678'
                                      : '01112345678',
                          prefixIcon: Icon(selectedMethod.icon),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: transferRefCtrl,
                        decoration: const InputDecoration(
                          labelText:
                              'رقم مرجع التحويل الفعلي (Transaction Reference ID)',
                          hintText: 'مثال: VF98234120 أو IPN774192',
                          prefixIcon: Icon(Icons.receipt_long_outlined),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: cardHolderCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم حامل البطاقة (كما على البطاقة)',
                          hintText: 'AHMED MAHMOUD',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cardNumCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 16,
                        decoration: const InputDecoration(
                          labelText:
                              'رقم البطاقة البنكية (١٦ رقماً — Visa / Mastercard / Meeza)',
                          hintText: '4532015112830366',
                          counterText: '',
                          prefixIcon: Icon(Icons.credit_card),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: cardExpiryCtrl,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ الانتهاء (MM/YY)',
                                hintText: '08/29',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: cardCvvCtrl,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              decoration: const InputDecoration(
                                labelText: 'رمز CVV',
                                hintText: '123',
                                counterText: '',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                            ),
                            onPressed: () {
                              final stepOneError = validateStepOneInputs();
                              if (stepOneError != null) {
                                setModalState(() {
                                  isErrorMessage = true;
                                  verificationMessage = '⚠️ $stepOneError';
                                });
                                return;
                              }
                              final newOtp =
                                  '${100000 + Random().nextInt(899999)}';
                              if (isCard &&
                                  transferRefCtrl.text.trim().isEmpty) {
                                transferRefCtrl.text =
                                    'AUTH-${100000 + Random().nextInt(899999)}';
                              }
                              setModalState(() {
                                generatedBankOtp = newOtp;
                                otpDispatched = true;
                                isErrorMessage = false;
                                verificationMessage =
                                    '📲 تم التحقق المبدئي وإرسال كود التفويض البنكي (OTP) للعملية: [ $newOtp ] — أدخله بالأسفل لتأكيد الخصم والتفعيل.';
                              });
                            },
                            icon: const Icon(Icons.sms_outlined, size: 18),
                            label: Text(
                              otpDispatched
                                  ? 'إعادة إرسال كود التفويض (OTP)'
                                  : '١. طلب كود التحقق البنكي (OTP)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (otpDispatched) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: userOtpInputCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText:
                              '٢. أدخل كود التفويض البنكي المكون من ٦ أرقام (OTP)',
                          hintText: 'أدخل الكود المرسل لتأكيد سداد المبلغ',
                          counterText: '',
                          prefixIcon: const Icon(Icons.security_rounded,
                              color: Color(0xFF14B8A6)),
                          suffixIcon: TextButton(
                            onPressed: () {
                              if (generatedBankOtp != null) {
                                setModalState(() {
                                  userOtpInputCtrl.text = generatedBankOtp!;
                                });
                              }
                            },
                            child: const Text('لصق الكود',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: simulateBankRejection,
                      activeColor: Colors.redAccent,
                      onChanged: (val) => setModalState(() {
                        simulateBankRejection = val;
                      }),
                      title: const Text(
                        'محاكاة رفض العملية من البنك / عدم اكتمال الدفع (للاختبار)',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      subtitle: const Text(
                        'عند تفعيل هذا الخيار سيرفض النظام العملية ولن يتم تفعيل الخطة أبداً',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ),
                    if (verificationMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isErrorMessage
                              ? Colors.redAccent.withOpacity(0.18)
                              : const Color(0xFF14B8A6).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isErrorMessage
                                ? Colors.redAccent
                                : const Color(0xFF14B8A6),
                          ),
                        ),
                        child: Text(
                          verificationMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isErrorMessage
                                ? const Color(0xFFFCA5A5)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedMethod.brandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isVerifyingPayment
                            ? null
                            : () async {
                                final stepOneError = validateStepOneInputs();
                                if (stepOneError != null) {
                                  setModalState(() {
                                    isErrorMessage = true;
                                    verificationMessage =
                                        '❌ لا يمكن تفعيل الخطة: $stepOneError';
                                  });
                                  return;
                                }
                                if (!otpDispatched ||
                                    generatedBankOtp == null) {
                                  setModalState(() {
                                    isErrorMessage = true;
                                    verificationMessage =
                                        '❌ يرجى الضغط أولاً على «طلب كود التحقق البنكي (OTP)» وإدخال الكود للتأكد من إتمام الدفع.';
                                  });
                                  return;
                                }

                                setModalState(() {
                                  isVerifyingPayment = true;
                                  verificationMessage = null;
                                });

                                await Future.delayed(
                                    const Duration(milliseconds: 900));

                                final String payerId = isCard
                                    ? '${cardHolderCtrl.text.trim()} (${cardNumCtrl.text.trim().substring(cardNumCtrl.text.trim().length - 4)})'
                                    : walletOrIpaCtrl.text.trim();

                                final outcome = await widget.appState
                                    .verifyAndActivateEgyptianPayment(
                                  plan: plan,
                                  method: selectedMethod,
                                  payerIdentifier: payerId,
                                  bankTransferRefNum: transferRefCtrl.text,
                                  generatedSessionOtp: generatedBankOtp!,
                                  userEnteredOtp: userOtpInputCtrl.text,
                                  simulateBankRejection: simulateBankRejection,
                                );

                                if (!ctx.mounted) return;
                                setModalState(() {
                                  isVerifyingPayment = false;
                                  isErrorMessage = !outcome.isPaidAndVerified;
                                  verificationMessage = outcome.message;
                                });

                                if (outcome.isPaidAndVerified) {
                                  await Future.delayed(
                                      const Duration(milliseconds: 600));
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(outcome.message),
                                        backgroundColor:
                                            const Color(0xFF14B8A6),
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.verified_user),
                        label: Text(
                          isVerifyingPayment
                              ? 'جاري التحقق البنكي الفعلي من الدفع...'
                              : 'تحقق من الدفع الآن وتفعيل (${plan.title})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _submitManualVideoForm() {
    if (!_manualVideoFormKey.currentState!.validate()) return;

    final String cleanManualTitle =
        SmartVideoLinkAutoImporter.stripPlatformMentions(_vTitleCtrl.text.trim());
    final String cleanManualDesc =
        SmartVideoLinkAutoImporter.stripPlatformMentions(_vDescCtrl.text.trim());
    final newVideo = VideoModel(
      id: 'v_${DateTime.now().millisecondsSinceEpoch}',
      title: cleanManualTitle.isEmpty ? 'قصة حنين التربوية' : cleanManualTitle,
      description: cleanManualDesc.isEmpty
          ? 'قصة هادئة وممتعة لأطفالنا الأبطال.'
          : cleanManualDesc,
      category: _vCategory,
      ageGroup: _vAgeGroup,
      repeatPhrase: _vPhraseCtrl.text.trim().isEmpty
          ? '«أَنَا أَتَعَلَّمُ كُلَّ يَوْمٍ شَيْئاً جَدِيداً»'
          : _vPhraseCtrl.text.trim(),
      activeActivity: _vActivityCtrl.text.trim().isEmpty
          ? 'احكِ لماما أو بابا ماذا أعجبك في هذه القصة!'
          : _vActivityCtrl.text.trim(),
      streamUrl: _vUrlCtrl.text.trim(),
      bgGradientStart: const Color(0xFF1E1B4B),
      bgGradientEnd: const Color(0xFF0F172A),
      emoji: _vEmojiCtrl.text.trim().isEmpty ? '🌟' : _vEmojiCtrl.text.trim(),
      likes: 100,
    );

    widget.appState.addCustomVideo(newVideo);
    _vTitleCtrl.clear();
    _vDescCtrl.clear();
    _vUrlCtrl.clear();
    _vPhraseCtrl.clear();
    _vActivityCtrl.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تمت إضافة الفيديو بنجاح إلى المكتبة المحلية!'),
        backgroundColor: Color(0xFF14B8A6),
      ),
    );
  }

  void _copyExportedJson() {
    final jsonStr = widget.appState.exportVideosAsJson();
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 تم نسخ كود JSON لجميع الفيديوهات إلى الحافظة!'),
        backgroundColor: Color(0xFF14B8A6),
      ),
    );
  }

  Widget _buildRemoteChildMonitorAndLockTab(
      ParentAccount account, ChildProfile activeChild) {
    final TextEditingController lockMsgCtrl = TextEditingController(
      text: activeChild.remoteLockReasonMessage,
    );
    final TextEditingController voiceBroadcastCtrl = TextEditingController();
    final TextEditingController monitorUrlCtrl = TextEditingController(
      text: widget.appState.remoteMonitorApiUrl,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: activeChild.isDeviceRemotelyLocked
                  ? [const Color(0xFF7F1D1D), const Color(0xFF1E293B)]
                  : [const Color(0xFF0F766E), const Color(0xFF1E293B)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: activeChild.isDeviceRemotelyLocked
                  ? Colors.redAccent
                  : const Color(0xFF14B8A6),
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(activeChild.chosenAvatar,
                      style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مراقبة موبايل الطفل: ${activeChild.name}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كود الربط العائلي بين موبايل الأب وموبايل الطفل: ${activeChild.familyPairingCode}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFDE68A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: activeChild.isDeviceRemotelyLocked
                          ? Colors.redAccent
                          : const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      activeChild.isDeviceRemotelyLocked
                          ? '🔒 مقفل عن بُعد'
                          : '🟢 متصل الآن',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📡 ماذا يفعل الطفل الآن على الموبايل؟ (بث الحالة الفوري):',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeChild.currentLiveStatus,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MonitorStatBadge(
                    label: 'وقت المشاهدة',
                    value:
                        '${activeChild.usedMinutesToday}/${activeChild.dailyTimeLimit} د',
                    icon: Icons.timer_outlined,
                  ),
                  _MonitorStatBadge(
                    label: 'نقاط الذكاء',
                    value: '🧠 ${activeChild.intelligencePoints}',
                    icon: Icons.psychology_outlined,
                  ),
                  _MonitorStatBadge(
                    label: 'النجوم والفصاحة',
                    value:
                        '⭐ ${activeChild.starsEarned} (${activeChild.correctPronunciationsCount})',
                    icon: Icons.star_border_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: lockMsgCtrl,
                decoration: const InputDecoration(
                  labelText: 'رسالة القفل التي تظهر على شاشة موبايل الطفل',
                  prefixIcon: Icon(Icons.message_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeChild.isDeviceRemotelyLocked
                              ? const Color(0xFF10B981)
                              : Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final bool nextLock =
                              !activeChild.isDeviceRemotelyLocked;
                          await widget.appState.setRemoteDeviceLockForChild(
                            childId: activeChild.id,
                            lockDevice: nextLock,
                            customLockMessage: lockMsgCtrl.text,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  nextLock
                                      ? '🔒 تم إرسال أمر قفل شاشة موبايل (${activeChild.name}) فوراً!'
                                      : '🟢 تم فتح قفل شاشة موبايل (${activeChild.name}) عن بُعد!',
                                ),
                                backgroundColor: nextLock
                                    ? Colors.redAccent
                                    : const Color(0xFF14B8A6),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          activeChild.isDeviceRemotelyLocked
                              ? Icons.lock_open_rounded
                              : Icons.phonelink_lock_rounded,
                        ),
                        label: Text(
                          activeChild.isDeviceRemotelyLocked
                              ? 'فتح قفل موبايل الطفل الآن'
                              : 'قفل موبايل الطفل الآن من موبايلي 🔒',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (account.children.length > 1) ...[
          const Text(
            '👦👧 التبديل السريع لمراقبة طفل آخر في العائلة:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: account.children.map((c) {
              final bool isCurr = c.id == activeChild.id;
              return ChoiceChip(
                selected: isCurr,
                selectedColor: const Color(0xFF14B8A6),
                label: Text(
                    '${c.chosenAvatar} ${c.name} ${c.isDeviceRemotelyLocked ? "🔒" : "🟢"}'),
                onSelected: (_) => widget.appState.switchActiveChild(c.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '💬 إرسال رسالة نصية عائمة فورية لشاشة الطفل عبر المساعد الذكي',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '✨ يظهر المساعد الذكي نصوصاً عائمة هادئة أعلى شاشة الطفل بدون إزعاج صوتي.',
                style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: voiceBroadcastCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اكتب رسالة عائمة تظهر للطفل فوراً على الشاشة',
                        hintText: 'مثال: يا فارس حان وقت غسل اليدين والعشاء!',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () async {
                      if (voiceBroadcastCtrl.text.trim().isEmpty) return;
                      await widget.appState.sendRemoteVoiceAlertToChild(
                        childId: activeChild.id,
                        messageText: voiceBroadcastCtrl.text,
                      );
                      voiceBroadcastCtrl.clear();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '💬 تم إرسال الرسالة العائمة لشاشة الطفل فوراً!'),
                          ),
                        );
                      }
                    },
                    child: const Text('إرسال نص عائم',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🌐 رابط المزامنة السحابية بين موبايل الأب وموبايل الطفل (اختياري)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'لربط جهازين منفصلين عبر الإنترنت، ضع رابط نقطة المزامنة (Firebase / REST Endpoint) ليتم إرسال أوامر القفل وسجل النشاط لحظياً:',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: monitorUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Remote Monitor & Lock Sync URL',
                        hintText: 'https://your-family-sync.firebaseio.com/lock.json',
                        prefixIcon: Icon(Icons.cloud_queue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      widget.appState
                          .updateRemoteMonitorApiUrl(monitorUrlCtrl.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حفظ رابط مزامنة القفل والمراقبة عن بُعد'),
                        ),
                      );
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '📋 سجل النشاط الحي لما يفعله (${activeChild.name}) على التطبيق:',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...activeChild.liveActivityTimeline.map((entry) {
          return Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8)),
              title: Text(
                entry.actionTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                '${entry.categoryBadge} • ${entry.timestampIso.substring(0, 16).replaceAll("T", " ")}',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showEditChildModal(ChildProfile child) {
    final editNameCtrl = TextEditingController(text: child.name);
    String editAge = child.age;
    String editAvatar = child.chosenAvatar;
    int editLimit = child.dailyTimeLimit;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                right: 24,
                left: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✏️ تعديل ملف الطفل',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: editNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطفل',
                      prefixIcon: Icon(Icons.child_care),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: editAge,
                          decoration:
                              const InputDecoration(labelText: 'الفئة العمرية'),
                          items: const [
                            DropdownMenuItem(
                                value: '2–4 سنوات', child: Text('2–4 سنوات')),
                            DropdownMenuItem(
                                value: '3–6 سنوات', child: Text('3–6 سنوات')),
                            DropdownMenuItem(
                                value: '4–8 سنوات', child: Text('4–8 سنوات')),
                            DropdownMenuItem(
                                value: '6–10 سنوات', child: Text('6–10 سنوات')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => editAge = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: editAvatar,
                        items:
                            ['🦁', '🦋', '🐰', '🐼', '🚀', '🌸', '🐬', '🦊']
                                .map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e,
                                          style: const TextStyle(fontSize: 24)),
                                    ))
                                .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => editAvatar = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('الحد اليومي: $editLimit دقيقة'),
                  Slider(
                    value: editLimit.toDouble(),
                    min: 5,
                    max: 60,
                    divisions: 11,
                    activeColor: const Color(0xFF14B8A6),
                    onChanged: (v) =>
                        setModalState(() => editLimit = v.round()),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14B8A6),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        widget.appState.updateChildProfile(
                          childId: child.id,
                          name: editNameCtrl.text,
                          age: editAge,
                          chosenAvatar: editAvatar,
                          dailyTimeLimit: editLimit,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('حفظ التعديلات'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final account = widget.appState.currentAccount;
        if (account == null) {
          return const SizedBox.shrink();
        }
        final activeChild = account.activeChild;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              'بوابة الوالدين واستوديو حنين كيدز',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF14B8A6),
              labelColor: const Color(0xFF14B8A6),
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(
                    icon: Icon(Icons.phonelink_lock_rounded),
                    text: 'مراقبة وقفل موبايل الطفل'),
                Tab(
                    icon: Icon(Icons.cloud_download_outlined),
                    text: 'استقبال الفيديوهات'),
                Tab(
                    icon: Icon(Icons.workspace_premium_outlined),
                    text: 'الاشتراكات والدفع المصري'),
                Tab(
                    icon: Icon(Icons.mark_email_read_outlined),
                    text: 'تنبيهات الإيميل والوقت'),
                Tab(icon: Icon(Icons.child_care), text: 'ملفات الأطفال'),
                Tab(
                    icon: Icon(Icons.manage_accounts_outlined),
                    text: 'إعدادات الحساب'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildRemoteChildMonitorAndLockTab(account, activeChild),
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF31102F), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFF59E0B), width: 1.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Color(0xFFF59E0B), size: 26),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '🪄 الاستيراد الذكي الفوري (فيديو يوتيوب أو تيك توك / قائمة تشغيل يوتيوب)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'الصق رابط فيديو من يوتيوب أو تيك توك، أو رابط قائمة تشغيل يوتيوب (Playlist)، وسيقوم التطبيق آلياً باستيراده بأعلى جودة (1080p Full HD)، وسحب الوصف الأصلي الصافي (بدون ذكر أسماء المنصات)، وتوليد القسم والفئة العمرية وجملة «ردد معي» ونشاط البطل وضبط المقاس أوتوماتيكياً!',
                          style: TextStyle(
                              fontSize: 12, height: 1.5, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _smartLinkImportCtrl,
                          decoration: InputDecoration(
                            labelText:
                                'الصق رابط فيديو (YouTube / TikTok) أو قائمة تشغيل يوتيوب (Playlist)',
                            hintText:
                                'https://www.youtube.com/watch?v=... أو playlist?list=... أو tiktok.com/...',
                            prefixIcon: const Icon(Icons.bolt_rounded,
                                color: Color(0xFFF59E0B)),
                            suffixIcon: IconButton(
                              tooltip: 'لصق من الحافظة',
                              icon: const Icon(Icons.content_paste_rounded),
                              onPressed: () async {
                                final data =
                                    await Clipboard.getData('text/plain');
                                if (data?.text != null &&
                                    data!.text!.trim().isNotEmpty) {
                                  setState(() {
                                    _smartLinkImportCtrl.text =
                                        data.text!.trim();
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.black87,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _isSmartImporting
                                      ? null
                                      : () async {
                                          final raw =
                                              _smartLinkImportCtrl.text.trim();
                                          if (raw.isEmpty) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'يرجى لصق رابط الفيديو أو القناة أو قائمة التشغيل أولاً!'),
                                                backgroundColor:
                                                    Colors.redAccent,
                                              ),
                                            );
                                            return;
                                          }
                                          setState(
                                              () => _isSmartImporting = true);
                                          final importedBatch = await widget
                                              .appState
                                              .smartAutoImportFromAnyUrlOrPlaylist(
                                                  raw);
                                          if (!mounted) return;
                                          if (importedBatch.isEmpty) {
                                            setState(() =>
                                                _isSmartImporting = false);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    '⚠️ تعذر استخراج بث مباشر من هذا الرابط. تأكد أن الفيديو عام وليس خاصاً وأن الإنترنت متصل.'),
                                                backgroundColor:
                                                    Colors.redAccent,
                                              ),
                                            );
                                            return;
                                          }
                                          final firstVideo =
                                              importedBatch.first;
                                          setState(() {
                                            _isSmartImporting = false;
                                            _lastAutoGeneratedPreview =
                                                firstVideo;
                                            _vTitleCtrl.text = firstVideo.title;
                                            _vUrlCtrl.text =
                                                firstVideo.streamUrl;
                                            _vCategory = firstVideo.category;
                                            _vAgeGroup = firstVideo.ageGroup;
                                            _vDescCtrl.text =
                                                firstVideo.description;
                                            _vPhraseCtrl.text =
                                                firstVideo.repeatPhrase;
                                            _vActivityCtrl.text =
                                                firstVideo.activeActivity;
                                            _vEmojiCtrl.text = firstVideo.emoji;
                                            _smartLinkImportCtrl.clear();
                                          });
                                          CalmVoiceService.instance.speakCalmly(
                                            importedBatch.length > 1
                                                ? 'تم استيراد ${importedBatch.length} قصص من القناة أو قائمة التشغيل وتوليد بياناتها بنجاح!'
                                                : 'تم استيراد القصة وتوليد بياناتها وضبط المقاس تلقائياً: ${firstVideo.title}',
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                importedBatch.length > 1
                                                    ? '✅ تم استيراد ${importedBatch.length} فيديوهات من القناة/القائمة وتوليد بياناتها كاملة!'
                                                    : '✅ تم استيراد وتوليد «${firstVideo.title}» بجودة ${firstVideo.qualityBadge}!',
                                              ),
                                              backgroundColor:
                                                  const Color(0xFF10B981),
                                            ),
                                          );
                                        },
                                  icon: _isSmartImporting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.black87,
                                          ),
                                        )
                                      : const Icon(Icons.auto_fix_high_rounded),
                                  label: Text(
                                    _isSmartImporting
                                        ? 'جاري استيراد الفيديو / القائمة وتوليد البيانات...'
                                        : 'استيراد ذكي (فيديو يوتيوب أو تيك توك / قائمة تشغيل) 🪄',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_lastAutoGeneratedPreview != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withOpacity(0.6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '✅ تم التوليد الآلي بنجاح (${_lastAutoGeneratedPreview!.qualityBadge}): ${_lastAutoGeneratedPreview!.emoji} ${_lastAutoGeneratedPreview!.title}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFFA7F3D0),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '• الوصف الصافي: ${_lastAutoGeneratedPreview!.description} — القسم: ${VideoModel.getCategoryDisplayLabel(_lastAutoGeneratedPreview!.category)} | العمر: ${_lastAutoGeneratedPreview!.ageGroup} — ردد معي: ${_lastAutoGeneratedPreview!.repeatPhrase}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF14B8A6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_sync, color: Color(0xFF14B8A6)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الربط السحابي (JSON Feed URL)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'أدخل رابط ملف JSON المباشر لجلب الفيديوهات سحابياً عبر حزمة http وتحديث المكتبة بضغطة زر.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _remoteUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'رابط ملف JSON المباشر',
                            hintText:
                                'https://example.com/sample_videos_feed.json',
                            prefixIcon: Icon(Icons.link),
                          ),
                        ),
                        if (widget.appState.lastSyncMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            widget.appState.lastSyncMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF14B8A6),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: widget.appState.isSyncingVideos
                                    ? null
                                    : () => widget.appState
                                        .syncVideosFromRemoteUrl(
                                            _remoteUrlCtrl.text),
                                icon: const Icon(Icons.sync),
                                label: Text(
                                  widget.appState.isSyncingVideos
                                      ? 'جاري المزامنة...'
                                      : 'مزامنة الآن',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _copyExportedJson,
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('تصدير JSON'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Form(
                      key: _manualVideoFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '➕ إضافة فيديو (من الموبايل أو يوتيوب المحمّل أو رابط سحابي)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '💡 كيف تضيف فيديوهات يوتيوب وتجربها على محيطك وموبايلك؟',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '١. من الموبايل مباشرة: حمّل أي فيديو من يوتيوب بصيغة MP4 في مجلد التنزيلات (Download) على هاتفك، واضغط زر «مسار مجلد التنزيلات» بالأسفل ثم اكتب اسم الملف (مثل story1.mp4). — ٢. أو ارفع الفيديو على Google Drive أو سيرفر محلي والصق الرابط ليقوم التطبيق تلقائياً بضبط مقاس الفيديو (Auto-Resize) لملء الشاشة!',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _vTitleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'عنوان الفيديو / القصة',
                              prefixIcon: Icon(Icons.title),
                            ),
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                    ? 'يرجى إدخال عنوان القصة'
                                    : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _vUrlCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'مسار الفيديو على الموبايل (/storage/...) أو رابط MP4 / Drive',
                              hintText:
                                  '/storage/emulated/0/Download/my_video.mp4 أو https://...',
                              prefixIcon: Icon(Icons.video_library_outlined),
                            ),
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                    ? 'يرجى إدخال مسار الملف أو رابط البث'
                                    : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                backgroundColor: const Color(0xFF0F172A),
                                avatar: const Icon(Icons.folder_open,
                                    size: 16, color: Color(0xFF14B8A6)),
                                label: const Text(
                                  'إدراج مسار التنزيلات (/Download/)',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _vUrlCtrl.text =
                                        '/storage/emulated/0/Download/video1.mp4';
                                  });
                                },
                              ),
                              ActionChip(
                                backgroundColor: const Color(0xFF0F172A),
                                avatar: const Icon(Icons.wifi_tethering,
                                    size: 16, color: Color(0xFFF59E0B)),
                                label: const Text(
                                  'قالب سيرفر محلي (Wi-Fi LAN)',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _vUrlCtrl.text =
                                        'http://192.168.1.100:8000/video1.mp4';
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _vCategory,
                                  decoration: const InputDecoration(
                                    labelText: 'القسم',
                                  ),
                                  items: kVideoCategories
                                      .where((p) => p['id'] != 'all')
                                      .map((p) => DropdownMenuItem(
                                            value: p['id'],
                                            child: Text(
                                                '${p['icon']} ${p['title']}'),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _vCategory = v);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _vAgeGroup,
                                  decoration: const InputDecoration(
                                    labelText: 'الفئة العمرية',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '2–4 سنوات',
                                        child: Text('2–4 سنوات')),
                                    DropdownMenuItem(
                                        value: '3–6 سنوات',
                                        child: Text('3–6 سنوات')),
                                    DropdownMenuItem(
                                        value: '4–8 سنوات',
                                        child: Text('4–8 سنوات')),
                                    DropdownMenuItem(
                                        value: '6–10 سنوات',
                                        child: Text('6–10 سنوات')),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _vAgeGroup = v);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _vDescCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'وصف القصة (description)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _vPhraseCtrl,
                            decoration: const InputDecoration(
                              labelText: 'جملة «ردد معي» الفصيحة (repeatPhrase)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _vActivityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'نشاط البطل الواقعي (activeActivity)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: Colors.black87,
                              ),
                              onPressed: _submitManualVideoForm,
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text(
                                'حفظ وإضافة الفيديو للمكتبة المحلية',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '📚 مكتبة الفيديوهات (${widget.appState.videos.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.appState.restoreDefaultVideos,
                        child: const Text('استعادة الافتراضي'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...widget.appState.videos.map((v) {
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading:
                            Text(v.emoji, style: const TextStyle(fontSize: 28)),
                        title: Text(
                          v.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${VideoModel.getCategoryDisplayLabel(v.category)} • ${v.ageGroup}\n${v.streamUrl}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white60),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => widget.appState.deleteVideo(v.id),
                        ),
                      ),
                    );
                  }),
                ],
              ),

              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF134E4A), Color(0xFF1E293B)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF14B8A6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified_rounded,
                                color: Color(0xFFF59E0B), size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                account.subscriptionStatusLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'تاريخ انتهاء الصلاحية: ${account.subscriptionExpiryDate.toLocal().toString().substring(0, 16)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '💎 باقات الاشتراك المرنة والجذابة للعائلات',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ادعم طفلك بمحتوى آمن وفصيح واختر الباقة المناسبة مع الدفع الفوري بجميع وسائل الدفع في مصر:',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  ...kSubscriptionPlans.map((plan) {
                    final bool isCurrentPlan =
                        account.subscriptionPlanId == plan.id &&
                            account.isSubscriptionActive;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: plan.isPopular
                              ? const Color(0xFFF59E0B)
                              : plan.accentColor.withOpacity(0.6),
                          width: plan.isPopular ? 2.2 : 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: plan.accentColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  plan.badge,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: plan.accentColor,
                                  ),
                                ),
                              ),
                              if (plan.priceEgp > 0)
                                Row(
                                  children: [
                                    if (plan.originalPriceEgp > plan.priceEgp)
                                      Text(
                                        '${plan.originalPriceEgp} ج.م',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white38,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${plan.priceEgp} ج.م',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const Text(
                                  'مجاناً (٢٤ ساعة)',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            plan.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plan.subtitle,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70),
                          ),
                          const SizedBox(height: 10),
                          ...plan.features.map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      size: 16, color: plan.accentColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      f,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCurrentPlan
                                    ? const Color(0xFF334155)
                                    : plan.accentColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () =>
                                  _openEgyptianPaymentCheckoutSheet(plan),
                              icon: Icon(isCurrentPlan
                                  ? Icons.autorenew
                                  : Icons.payment_rounded),
                              label: Text(
                                isCurrentPlan
                                    ? 'الباقة النشطة حالياً (تمديد إضافي)'
                                    : plan.priceEgp == 0
                                        ? 'تفعيل التجربة المجانية ليوم كامل'
                                        : 'اشترك الآن وادفع بالوسائل المصرية',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text(
                    '🇪🇬 وسائل الدفع المصرية المتاحة والمعتمدة داخل التطبيق:',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kEgyptianPaymentMethods.map((m) {
                      return Chip(
                        backgroundColor: m.brandColor.withOpacity(0.2),
                        avatar: Icon(m.icon, size: 16, color: m.brandColor),
                        label: Text(
                          m.nameAr,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                  if (account.paymentHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '🧾 سجل إيصالات الدفع السابقة:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...account.paymentHistory.map((tx) {
                      final bool ok = tx.isVerified;
                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: ok
                                ? const Color(0xFF14B8A6).withOpacity(0.5)
                                : Colors.redAccent.withOpacity(0.5),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            ok ? Icons.verified_rounded : Icons.cancel_outlined,
                            color: ok
                                ? const Color(0xFF14B8A6)
                                : Colors.redAccent,
                          ),
                          title: Text(
                            '${tx.planTitle} — ${tx.amountEgp} ج.م (${ok ? "مؤكد ومفعّل" : "مرفوض / لم يفعّل"})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: ok ? Colors.white : const Color(0xFFFCA5A5),
                            ),
                          ),
                          subtitle: Text(
                            'الوسيلة: ${tx.paymentMethodName}\nالمرجع: ${tx.referenceCode} • الحساب: ${tx.payerIdentifier}${tx.failureReason.isNotEmpty ? "\nسبب الرفض: ${tx.failureReason}" : ""}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),

              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.mark_email_unread_rounded,
                                color: Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'نظام تنبيهات الإيميل والاقتراحات للآباء (${account.emailOrPhone})',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.appState.generateSmartParentRecommendation(),
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: Color(0xFFFDE68A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: account.emailNotificationsEnabled,
                          activeColor: const Color(0xFF14B8A6),
                          onChanged:
                              widget.appState.toggleParentEmailNotifications,
                          title: const Text(
                            'إرسال تقارير وتنبيهات على الإيميل تلقائياً',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'يرسل تنبيهاً عند انتهاء وقت الشاشة وعند إنجاز الطفل للنجوم والأنشطة',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: account.dailySmartSuggestionsEnabled,
                          activeColor: const Color(0xFFF59E0B),
                          onChanged:
                              widget.appState.toggleDailySmartSuggestions,
                          title: const Text(
                            'اقتراحات ذكية يومية لتحسين تجربة الطفل',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF14B8A6),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              await widget.appState.sendParentEmailAlert(
                                subject:
                                    '📊 تقرير أداء واقتراح ذكي من تطبيق حنين كيدز (${activeChild.name})',
                                bodyMessage:
                                    'شاهد ${activeChild.name} اليوم ${activeChild.usedMinutesToday} دقيقة، وحقق ${activeChild.starsEarned} نجوم، وأتقن ${activeChild.correctPronunciationsCount} جمل عربية فصيحة.',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '📧 تم إرسال التقرير والاقتراح الذكي إلى الإيميل: ${account.emailOrPhone}'),
                                    backgroundColor: const Color(0xFF14B8A6),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.send_rounded),
                            label: const Text(
                                'إرسال تقرير واقتراح ذكي إلى إيميلي الآن'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💡 شاركنا اقتراحك لتحسين تجربة تطبيق حنين كيدز',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _parentSuggestionInputCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'اكتب أي فكرة أو قصة تود إضافتها لطفلك',
                            hintText:
                                'مثال: نرغب في قصص عن بر الوالدين أو تعلم الأرقام بالعربية...',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final text =
                                  _parentSuggestionInputCtrl.text.trim();
                              if (text.isEmpty) return;
                              await widget.appState.sendParentEmailAlert(
                                subject:
                                    '💌 تأكيد استلام اقتراحك لتطوير حنين كيدز',
                                bodyMessage:
                                    'شكراً لمشاركتنا اقتراحك: «$text». سيقوم فريق المحتوى التربوي بمراجعته وإدراجه في التحديث القادم.',
                              );
                              _parentSuggestionInputCtrl.clear();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '✅ تم إرسال اقتراحك وتأكيده عبر الإيميل!'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.lightbulb_outline),
                            label: const Text('إرسال الاقتراح'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⏱️ التحكم في وقت الشاشة اليومي (${activeChild.name})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'استهلك اليوم: ${activeChild.usedMinutesToday} دقيقة من أصل ${activeChild.dailyTimeLimit} دقيقة • شاهد ${activeChild.watchedVideosToday} قصص',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        Slider(
                          value: activeChild.dailyTimeLimit
                              .toDouble()
                              .clamp(5.0, 60.0),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          activeColor: const Color(0xFF14B8A6),
                          label: '${activeChild.dailyTimeLimit} دقيقة',
                          onChanged: (val) => widget.appState
                              .updateDailyTimeLimit(val.round()),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget
                                .appState.resetDailyScreenTimeForActiveChild,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text(
                                'تصفير وقت المشاهدة اليومي وإلغاء ستارة النوم'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '📬 سجل رسائل الإيميل والتنبيهات المرسلة للوالدين:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...account.emailAlertsLog.map((alert) {
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.subject,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF14B8A6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'إلى: ${alert.recipientEmail} • ${alert.sentAt.toLocal().toString().substring(0, 16)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white54),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              alert.bodyMessage,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              alert.smartImprovementSuggestion,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFDE68A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),

              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '👨‍👩‍👧‍👦 إدارة وتعديل ملفات الأطفال',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...account.children.map((child) {
                    final isCurrent = child.id == account.activeChildId;
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isCurrent
                              ? const Color(0xFF14B8A6)
                              : Colors.white12,
                        ),
                      ),
                      child: ListTile(
                        onTap: () =>
                            widget.appState.switchActiveChild(child.id),
                        leading: Text(child.chosenAvatar,
                            style: const TextStyle(fontSize: 32)),
                        title: Text(
                          '${child.name} (${child.age})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'الحصة: ${child.dailyTimeLimit}د • ⭐ ${child.starsEarned} • 🧠 ذكاء: ${child.intelligencePoints} (${child.gamesCompletedCount} ألعاب) • 🗣️ فصاحة: ${child.correctPronunciationsCount}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF14B8A6)),
                              onPressed: () => _showEditChildModal(child),
                            ),
                            if (account.children.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () => widget.appState
                                    .removeChildProfile(child.id),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '➕ إضافة ملف طفل جديد',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14B8A6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newChildNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم الطفل',
                            prefixIcon: Icon(Icons.child_care),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _newChildAge,
                                decoration: const InputDecoration(
                                  labelText: 'الفئة العمرية',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: '2–4 سنوات',
                                      child: Text('2–4 سنوات')),
                                  DropdownMenuItem(
                                      value: '3–6 سنوات',
                                      child: Text('3–6 سنوات')),
                                  DropdownMenuItem(
                                      value: '4–8 سنوات',
                                      child: Text('4–8 سنوات')),
                                  DropdownMenuItem(
                                      value: '6–10 سنوات',
                                      child: Text('6–10 سنوات')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _newChildAge = v);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            DropdownButton<String>(
                              value: _newChildAvatar,
                              items: ['🦁', '🦋', '🐰', '🐼', '🚀', '🌸']
                                  .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e,
                                            style:
                                                const TextStyle(fontSize: 24)),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _newChildAvatar = v);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                            'دقائق المشاهدة اليومية: $_newChildDailyLimit دقيقة'),
                        Slider(
                          value: _newChildDailyLimit.toDouble(),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          activeColor: const Color(0xFF14B8A6),
                          onChanged: (v) =>
                              setState(() => _newChildDailyLimit = v.round()),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF14B8A6),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              if (_newChildNameCtrl.text.trim().isEmpty) return;
                              widget.appState.addChildProfile(
                                name: _newChildNameCtrl.text,
                                age: _newChildAge,
                                chosenAvatar: _newChildAvatar,
                                dailyTimeLimit: _newChildDailyLimit,
                              );
                              _newChildNameCtrl.clear();
                            },
                            child: const Text('حفظ ملف الطفل'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF14B8A6),
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(
                            account.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Text(
                            'البريد / الهاتف: ${account.emailOrPhone}\nطريقة الدخول: ${account.authProvider == 'google' ? 'حساب Google الموثق' : 'بريد إلكتروني'}\nالرمز الأبوي الحالي (PIN): ${account.parentalPin}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: account.voiceAssistantEnabled,
                          activeColor: const Color(0xFF14B8A6),
                          onChanged: widget.appState.toggleVoiceAssistant,
                          title: const Text(
                            '🤖 تفعيل المساعد الصوتي الذكي للطفل',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'يقدم تنبيهات صوتية هادئة واقتراحات قصص مناسبة للطفل',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 24),
                        const Text(
                          '🔐 تحديث الرمز السري الأبوي (PIN من 4 أرقام)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _pinUpdateCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                decoration: const InputDecoration(
                                  labelText: 'رمز PIN الجديد',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14B8A6),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                if (_pinUpdateCtrl.text.trim().length == 4) {
                                  widget.appState
                                      .updateParentalPin(_pinUpdateCtrl.text);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم تحديث رمز PIN الأبوي'),
                                    ),
                                  );
                                }
                              },
                              child: const Text('حفظ PIN'),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white12, height: 28),
                        const Text(
                          '📧 رابط سيرفر إرسال تنبيهات الإيميل (Webhook / Email API اختياري)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailWebhookCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email Notification Webhook URL',
                            hintText: 'https://api.yourdomain.com/email-alerts',
                            prefixIcon: Icon(Icons.mark_email_read_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () {
                              widget.appState.updateEmailWebhookUrl(
                                  _emailWebhookCtrl.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('تم حفظ رابط سيرفر تنبيهات الإيميل'),
                                ),
                              );
                            },
                            child: const Text('حفظ إعداد الإيميل'),
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 28),
                        const Text(
                          '💳 ربط سيرفر التحقق الحي لبوابات الدفع المصرية (Paymob / Fawry / Kashier API)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _paymentApiCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'رابط التحقق من الدفع (Payment Verification API URL)',
                            hintText:
                                'https://api.yourdomain.com/payments/verify',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _merchantKeyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'مفتاح التاجر السري (Merchant API Secret Key)',
                            hintText: 'pk_live_...',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () {
                              widget.appState.updatePaymentGatewayConfig(
                                verifyUrl: _paymentApiCtrl.text,
                                secretKey: _merchantKeyCtrl.text,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'تم حفظ إعدادات بوابة التحقق من الدفع'),
                                ),
                              );
                            },
                            child: const Text('حفظ إعدادات بوابة الدفع'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        await widget.appState.logout();
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'تسجيل الخروج من الحساب',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonitorStatBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MonitorStatBadge({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF14B8A6)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class CuteHeroCharacterModel {
  final String id;
  final String nameAr;
  final String titleBadge;
  final String avatarEmoji;
  final Color primaryColor;
  final Color secondaryColor;
  final List<String> encouragingAlerts;

  const CuteHeroCharacterModel({
    required this.id,
    required this.nameAr,
    required this.titleBadge,
    required this.avatarEmoji,
    required this.primaryColor,
    required this.secondaryColor,
    required this.encouragingAlerts,
  });
}

const List<CuteHeroCharacterModel> kCuteSuperheroCharacters = [
  CuteHeroCharacterModel(
    id: 'spidey_hero',
    nameAr: 'سبايدي البطل اللطيف',
    titleBadge: 'بطل خفة الحركة والذكاء 🕸️',
    avatarEmoji: '🕷️🦸‍♂️',
    primaryColor: Color(0xFFEF4444),
    secondaryColor: Color(0xFF3B82F6),
    encouragingAlerts: [
      'أحسنت يا صديقي البطل! حاستك العنكبوتية الذكية تكتشف الإجابات الصحيحة بسرعة مذهلة!',
      'تذكير لطيف من سبايدي: البطل الحقيقي يرتب غرفته ويستأذن من ماما وبابا دائماً!',
      'ما شاء الله! تركيزك عالٍ جداً اليوم، هيا نكمل المرحلة التالية بهدوء وذكاء!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'bat_knight',
    nameAr: 'فارس الليل الذكي (بات هيرو)',
    titleBadge: 'محقق الألغاز والمنطق 🦇',
    avatarEmoji: '🦇🦸',
    primaryColor: Color(0xFFF59E0B),
    secondaryColor: Color(0xFF334155),
    encouragingAlerts: [
      'تحليل عبقري يا بطل! قوة ملاحظتك تشبه أعظم المحققين الأذكياء!',
      'تنبيه تشجيعي: خذ نفساً عميقاً وهادئاً، فالعقل الهادئ يحل أصعب الألغاز!',
      'رائع! كل مرحلة تنجزها تزيد نقاط ذكائك وتجعلك بطلاً في الأخلاق والعلم!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'super_star',
    nameAr: 'سوبر نور الخارق',
    titleBadge: 'بطل القوة والأخلاق الجميلة ⭐',
    avatarEmoji: '🦸‍♂️✨',
    primaryColor: Color(0xFF06B6D4),
    secondaryColor: Color(0xFFEC4899),
    encouragingAlerts: [
      'أنت تطير نحو القمة بذكائك وفصاحتك العربية الجميلة يا بطل حنين!',
      'تذكير البطل الخارق: الكلمة الطيبة والابتسامة هما أعظم قوة خارقة في العالم!',
      'فخور بك جداً! استمر في التقدم نحو المرحلة ١٠٠ بهدوء وثقة!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'elsa_princess',
    nameAr: 'أميرة الثلج الحكيمة',
    titleBadge: 'أميرة الهدوء والإبداع ❄️',
    avatarEmoji: '👸❄️',
    primaryColor: Color(0xFF38BDF8),
    secondaryColor: Color(0xFF818CF8),
    encouragingAlerts: [
      'قلبك صافي وجميل مثل بلورات الثلج اللامعة! رسمك وإجاباتك في قمة الروعة!',
      'همسة لطيفة: الهدوء واللطف مع إخوتك يجعلان البيت مملكة سعيدة!',
      'ما أجمل خطك وتفكيرك! أنتِ نجمة متألقة في واحة الذكاء!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'sponge_smile',
    nameAr: 'سبونج المبتسم المرح',
    titleBadge: 'صديق البهجة والنشاط 🧽',
    avatarEmoji: '🧽🌟',
    primaryColor: Color(0xFFFACC15),
    secondaryColor: Color(0xFF14B8A6),
    encouragingAlerts: [
      'أنا مستعد! أنا مستعد! وأنت أيضاً مستعد لحل المرحلة الجديدة بابتسامة كبيرة!',
      'تنبيه مبهج: لا تنسَ شرب الماء وغسل يديك بالصابون لتبقى نشيطاً طوال اليوم!',
      'يا سلام! إجابتك ذكية جداً وتستحق نجمة ذهبية لامعة!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'pika_spark',
    nameAr: 'بيكا الذكي المضيء',
    titleBadge: 'شرارة الحماس والذاكرة ⚡',
    avatarEmoji: '⚡🐭',
    primaryColor: Color(0xFFFBBF24),
    secondaryColor: Color(0xFFF97316),
    encouragingAlerts: [
      'بيكا بيكا! ذاكرتك تلمع بالذكاء والنشاط مثل البرق اللطيف!',
      'نصيحة لطيفة: أرح عينيك قليلاً وانظر بعيداً ثم عد لنكمل المغامرة الممتعة!',
      'إنجاز مدهش! لقد جمعت نقاط ذكاء رائعة في هذه المرحلة!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'dora_explorer',
    nameAr: 'المستكشفة الصغيرة المغامرة',
    titleBadge: 'بطلة الاكتشاف واللغات 🎒',
    avatarEmoji: '👧🎒',
    primaryColor: Color(0xFFEC4899),
    secondaryColor: Color(0xFFA855F7),
    encouragingAlerts: [
      'عمل رائع (ممتاز)! لقد اكتشفت الحل الصحيح بنفسك يا مستكشفنا الذكي!',
      'تذكير المستكشفة: قل «شكراً» و«من فضلك» دائماً لكل من يساعدك في يومك!',
      'هيا بنا إلى المرحلة التالية! لدينا ١٠٠ مغامرة ذكية بانتظارنا!',
    ],
  ),
  CuteHeroCharacterModel(
    id: 'simba_cub',
    nameAr: 'الشبل الشجاع سيمبا',
    titleBadge: 'بطل الشجاعة والصدق 🦁',
    avatarEmoji: '🦁👑',
    primaryColor: Color(0xFFF97316),
    secondaryColor: Color(0xFF10B981),
    encouragingAlerts: [
      'زئير الأبطال الهادئ! شجاعتك في المحاولة والتعلم تجعلك ملك الغابة الذكي!',
      'تنبيه البطل الشجاع: الصدق والأمانة هما تاج البطولة الحقيقي!',
      'أحسنت يا بطل! خطوة بعد خطوة تقترب من إنهاء الـ ١٠٠ مرحلة كاملة!',
    ],
  ),
];

class Interactive3DSuperheroAvatar extends StatefulWidget {
  final CuteHeroCharacterModel hero;
  final double size;
  final bool isJumping;
  final VoidCallback? onTap;

  const Interactive3DSuperheroAvatar({
    super.key,
    required this.hero,
    this.size = 56,
    this.isJumping = false,
    this.onTap,
  });

  @override
  State<Interactive3DSuperheroAvatar> createState() =>
      _Interactive3DSuperheroAvatarState();
}

class _Interactive3DSuperheroAvatarState
    extends State<Interactive3DSuperheroAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  bool _localBurst = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _localBurst = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _localBurst = false);
    });
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, _) {
          final double t = _animCtrl.value * 2 * pi;
          final bool excited = widget.isJumping || _localBurst;
          final double hoverOffset =
              excited ? -sin(t * 3).abs() * 7.0 : sin(t) * 3.2;
          final double tiltY = sin(t) * 0.22;
          final double tiltX = cos(t * 0.5) * 0.10;
          final double scaleBoost = excited ? 1.14 : 1.0;

          final Matrix4 perspectiveMatrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..rotateY(tiltY)
            ..rotateX(tiltX)
            ..scale(scaleBoost);

          return Transform.translate(
            offset: Offset(0, hoverOffset),
            child: Transform(
              alignment: Alignment.center,
              transform: perspectiveMatrix,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _Superhero3DCharacterPainter(
                    hero: widget.hero,
                    phase: t,
                    isExcited: excited,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Superhero3DCharacterPainter extends CustomPainter {
  final CuteHeroCharacterModel hero;
  final double phase;
  final bool isExcited;

  const _Superhero3DCharacterPainter({
    required this.hero,
    required this.phase,
    required this.isExcited,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = min(size.width, size.height) * 0.34;

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.91),
        width: r * (1.2 - sin(phase) * 0.15),
        height: r * 0.28,
      ),
      shadowPaint,
    );

    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          hero.primaryColor.withOpacity(isExcited ? 0.65 : 0.42),
          hero.secondaryColor.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.45));
    canvas.drawCircle(Offset(cx, cy), r * 1.42, auraPaint);

    final Path capePath = Path();
    final double capeWave = sin(phase * 1.5) * (r * 0.22);
    capePath.moveTo(cx - r * 0.55, cy - r * 0.1);
    capePath.quadraticBezierTo(
      cx - r * 0.85 + capeWave,
      cy + r * 0.55,
      cx - r * 0.50 + capeWave,
      cy + r * 0.92,
    );
    capePath.lineTo(cx + r * 0.50 + capeWave * 0.6, cy + r * 0.90);
    capePath.quadraticBezierTo(
      cx + r * 0.80,
      cy + r * 0.45,
      cx + r * 0.55,
      cy - r * 0.1,
    );
    capePath.close();
    final Paint capePaint = Paint()
      ..shader = LinearGradient(
        colors: [hero.secondaryColor, hero.primaryColor.withOpacity(0.85)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawPath(capePath, capePaint);

    final Rect torsoRect = Rect.fromCenter(
      center: Offset(cx, cy + r * 0.46),
      width: r * 1.05,
      height: r * 0.82,
    );
    final Paint torsoPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.95,
        colors: [
          Color.lerp(hero.primaryColor, Colors.white, 0.35)!,
          hero.primaryColor,
          Color.lerp(hero.primaryColor, Colors.black, 0.35)!,
        ],
      ).createShader(torsoRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, Radius.circular(r * 0.42)),
      torsoPaint,
    );

    final Paint emblemPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy + r * 0.42), r * 0.18, emblemPaint);

    final double leftArmAngle = -0.35 + cos(phase) * 0.15;
    canvas.save();
    canvas.translate(cx - r * 0.52, cy + r * 0.25);
    canvas.rotate(leftArmAngle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-r * 0.22, 0, r * 0.22, r * 0.52),
        Radius.circular(r * 0.12),
      ),
      torsoPaint,
    );
    canvas.restore();

    final double waveSpeed = isExcited ? 3.0 : 1.8;
    final double rightArmWaveAngle = -2.25 + sin(phase * waveSpeed) * 0.48;
    canvas.save();
    canvas.translate(cx + r * 0.48, cy + r * 0.22);
    canvas.rotate(rightArmWaveAngle);
    final Paint arm3DPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(hero.primaryColor, Colors.white, 0.3)!,
          hero.primaryColor,
        ],
      ).createShader(Rect.fromLTWH(0, 0, r * 0.28, r * 0.65));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-r * 0.12, 0, r * 0.24, r * 0.58),
        Radius.circular(r * 0.12),
      ),
      arm3DPaint,
    );
    final Paint glovePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Colors.white, Color(0xFFFDE047)],
      ).createShader(
          Rect.fromCircle(center: Offset(0, r * 0.62), radius: r * 0.18));
    canvas.drawCircle(Offset(0, r * 0.62), r * 0.16, glovePaint);
    canvas.restore();

    final Offset headCenter = Offset(cx, cy - r * 0.18);
    final double headRadius = r * 0.62;
    final Paint head3DPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.38),
        radius: 0.95,
        colors: [
          const Color(0xFFFFF1E6),
          hero.id == 'sponge_smile' || hero.id == 'pika_spark'
              ? const Color(0xFFFDE047)
              : (hero.id == 'spidey_hero'
                  ? const Color(0xFFEF4444)
                  : const Color(0xFFFDBA74)),
          Color.lerp(hero.primaryColor, Colors.black, 0.25)!,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(
          Rect.fromCircle(center: headCenter, radius: headRadius));
    canvas.drawCircle(headCenter, headRadius, head3DPaint);

    if (hero.id == 'bat_knight' ||
        hero.id == 'pika_spark' ||
        hero.id == 'simba_cub') {
      final Paint earPaint = Paint()
        ..color = hero.id == 'bat_knight'
            ? const Color(0xFF1E293B)
            : hero.primaryColor;
      final Path leftEar = Path()
        ..moveTo(headCenter.dx - headRadius * 0.7, headCenter.dy - headRadius * 0.5)
        ..lineTo(headCenter.dx - headRadius * 0.9, headCenter.dy - headRadius * 1.15)
        ..lineTo(headCenter.dx - headRadius * 0.25, headCenter.dy - headRadius * 0.8)
        ..close();
      final Path rightEar = Path()
        ..moveTo(headCenter.dx + headRadius * 0.7, headCenter.dy - headRadius * 0.5)
        ..lineTo(headCenter.dx + headRadius * 0.9, headCenter.dy - headRadius * 1.15)
        ..lineTo(headCenter.dx + headRadius * 0.25, headCenter.dy - headRadius * 0.8)
        ..close();
      canvas.drawPath(leftEar, earPaint);
      canvas.drawPath(rightEar, earPaint);
    }

    if (hero.id == 'elsa_princess' || hero.id == 'simba_cub') {
      final Paint crownPaint = Paint()..color = const Color(0xFFFACC15);
      final Path crown = Path()
        ..moveTo(headCenter.dx - headRadius * 0.45, headCenter.dy - headRadius * 0.82)
        ..lineTo(headCenter.dx - headRadius * 0.35, headCenter.dy - headRadius * 1.18)
        ..lineTo(headCenter.dx - headRadius * 0.12, headCenter.dy - headRadius * 0.92)
        ..lineTo(headCenter.dx, headCenter.dy - headRadius * 1.25)
        ..lineTo(headCenter.dx + headRadius * 0.12, headCenter.dy - headRadius * 0.92)
        ..lineTo(headCenter.dx + headRadius * 0.35, headCenter.dy - headRadius * 1.18)
        ..lineTo(headCenter.dx + headRadius * 0.45, headCenter.dy - headRadius * 0.82)
        ..close();
      canvas.drawPath(crown, crownPaint);
    }

    final Rect maskRect = Rect.fromCenter(
      center: Offset(headCenter.dx, headCenter.dy - headRadius * 0.06),
      width: headRadius * 1.55,
      height: headRadius * 0.65,
    );
    final Paint maskPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          hero.primaryColor.withOpacity(0.92),
          hero.secondaryColor.withOpacity(0.92),
        ],
      ).createShader(maskRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(maskRect, Radius.circular(headRadius * 0.32)),
      maskPaint,
    );

    final bool isBlinking = (sin(phase * 2.2) > 0.94);
    final double eyeH = isBlinking ? headRadius * 0.05 : headRadius * 0.26;
    final Paint eyeWhite = Paint()..color = Colors.white;
    final Paint pupilPaint = Paint()..color = const Color(0xFF0F172A);

    final Offset leftEyeCenter =
        Offset(headCenter.dx - headRadius * 0.32, headCenter.dy - headRadius * 0.06);
    final Offset rightEyeCenter =
        Offset(headCenter.dx + headRadius * 0.32, headCenter.dy - headRadius * 0.06);

    canvas.drawOval(
      Rect.fromCenter(
          center: leftEyeCenter, width: headRadius * 0.30, height: eyeH),
      eyeWhite,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: rightEyeCenter, width: headRadius * 0.30, height: eyeH),
      eyeWhite,
    );

    if (!isBlinking) {
      final double lookOffset = sin(phase) * (headRadius * 0.05);
      canvas.drawCircle(
        leftEyeCenter.translate(lookOffset, 0),
        headRadius * 0.11,
        pupilPaint,
      );
      canvas.drawCircle(
        rightEyeCenter.translate(lookOffset, 0),
        headRadius * 0.11,
        pupilPaint,
      );
      canvas.drawCircle(
        leftEyeCenter.translate(lookOffset - headRadius * 0.04, -headRadius * 0.04),
        headRadius * 0.04,
        eyeWhite,
      );
      canvas.drawCircle(
        rightEyeCenter.translate(lookOffset - headRadius * 0.04, -headRadius * 0.04),
        headRadius * 0.04,
        eyeWhite,
      );
    }

    final Paint smilePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, headRadius * 0.09)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(headCenter.dx, headCenter.dy + headRadius * 0.24),
        width: headRadius * 0.65,
        height: headRadius * 0.42,
      ),
      0.15,
      pi - 0.3,
      false,
      smilePaint,
    );

    final Paint specularPaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
            headCenter.dx - headRadius * 0.35, headCenter.dy - headRadius * 0.48),
        width: headRadius * 0.32,
        height: headRadius * 0.16,
      ),
      specularPaint,
    );

    final int starCount = isExcited ? 6 : 4;
    for (int i = 0; i < starCount; i++) {
      final double angle = phase * 1.4 + (i * 2 * pi / starCount);
      final double orbitR = r * (1.18 + 0.15 * sin(phase * 2 + i));
      final Offset p = Offset(
        cx + cos(angle) * orbitR,
        cy + sin(angle) * orbitR * 0.75,
      );
      final Paint sparkPaint = Paint()
        ..color = i.isEven ? const Color(0xFFFDE047) : Colors.white;
      canvas.drawCircle(p, isExcited ? r * 0.10 : r * 0.07, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Superhero3DCharacterPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.isExcited != isExcited ||
        oldDelegate.hero.id != hero.id;
  }
}

class CuteSuperheroCompanionBanner extends StatefulWidget {
  final AppStateManager appState;
  final bool compactMode;
  final String? customCheerMessage;

  const CuteSuperheroCompanionBanner({
    super.key,
    required this.appState,
    this.compactMode = false,
    this.customCheerMessage,
  });

  @override
  State<CuteSuperheroCompanionBanner> createState() =>
      _CuteSuperheroCompanionBannerState();
}

class _CuteSuperheroCompanionBannerState
    extends State<CuteSuperheroCompanionBanner> {
  int _heroIndex = 0;
  int _alertIndex = 0;
  bool _isJumping = false;

  void _cycleNextHero() {
    setState(() {
      _heroIndex = (_heroIndex + 1) % kCuteSuperheroCharacters.length;
      _alertIndex = (_alertIndex + 1) % 3;
      _isJumping = true;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _isJumping = false);
    });
  }

  void _triggerHeroWaveAndCheer() {
    setState(() {
      _alertIndex = (_alertIndex + 1) % 3;
      _isJumping = true;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _isJumping = false);
    });
  }

  void _openHeroFriendsGalleryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('🦸‍♂️✨', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'أصدقاؤك الأبطال الخارقون (مجسمات 3D متحركة ومتفاعلة)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'اضغط على أي بطل 3D ليلوّح بيده ويقفز ويرافقك على الشاشة بنصوص عائمة مبهجة!',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 390,
                    child: ListView.builder(
                      itemCount: kCuteSuperheroCharacters.length,
                      itemBuilder: (ctx, i) {
                        final h = kCuteSuperheroCharacters[i];
                        final bool isSelected = _heroIndex == i;
                        final String alertMsg = h.encouragingAlerts[
                            _alertIndex % h.encouragingAlerts.length];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _heroIndex = i;
                              _isJumping = true;
                            });
                            setModalState(() {});
                            Future.delayed(const Duration(milliseconds: 700),
                                () {
                              if (mounted) setState(() => _isJumping = false);
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  h.primaryColor.withOpacity(0.28),
                                  h.secondaryColor.withOpacity(0.18),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? h.primaryColor
                                    : Colors.white12,
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Interactive3DSuperheroAvatar(
                                  hero: h,
                                  size: 64,
                                  isJumping: isSelected,
                                  onTap: () {
                                    setState(() {
                                      _heroIndex = i;
                                      _isJumping = true;
                                    });
                                    setModalState(() {});
                                  },
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              h.nameAr,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black26,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '3D متفاعل 👋',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: h.primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '💬 «$alertMsg»',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFFDE68A),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hero = kCuteSuperheroCharacters[
        _heroIndex % kCuteSuperheroCharacters.length];
    final String message = widget.customCheerMessage ??
        hero.encouragingAlerts[_alertIndex % hero.encouragingAlerts.length];

    return GestureDetector(
      onTap: _openHeroFriendsGalleryModal,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compactMode ? 9 : 12,
          vertical: widget.compactMode ? 3 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              hero.primaryColor.withOpacity(widget.compactMode ? 0.26 : 0.34),
              hero.secondaryColor.withOpacity(widget.compactMode ? 0.18 : 0.25),
              const Color(0xFF1E293B)
                  .withOpacity(widget.compactMode ? 0.80 : 0.92),
            ],
          ),
          borderRadius: BorderRadius.circular(widget.compactMode ? 14 : 20),
          border: Border.all(
            color: hero.primaryColor.withOpacity(0.7),
            width: widget.compactMode ? 1.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: hero.primaryColor.withOpacity(0.25),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Interactive3DSuperheroAvatar(
              hero: hero,
              size: widget.compactMode ? 36 : 58,
              isJumping: _isJumping,
              onTap: _triggerHeroWaveAndCheer,
            ),
            SizedBox(width: widget.compactMode ? 8 : 12),
            Expanded(
              child: GestureDetector(
                onTap: _triggerHeroWaveAndCheer,
                child: widget.compactMode
                    ? Text(
                        '👋 ${hero.nameAr}: $message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '👋 ${hero.nameAr}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFDE68A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '• ${hero.titleBadge}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '💬 $message',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _cycleNextHero,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compactMode ? 7 : 9,
                  vertical: widget.compactMode ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 0.7),
                ),
                child: Text(
                  widget.compactMode ? '3D 🔄' : 'بطل 3D آخر 🔄',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EtiquetteStrokePath {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  const EtiquetteStrokePath({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

class EtiquetteDrawingCanvasPainter extends CustomPainter {
  final List<EtiquetteStrokePath> strokes;
  final int templateIndex;

  const EtiquetteDrawingCanvasPainter({
    required this.strokes,
    required this.templateIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = min(size.width, size.height) * 0.34;

    switch (templateIndex % 8) {
      case 0:
        final Path heartPath = Path();
        heartPath.moveTo(center.dx, center.dy + radius * 0.75);
        heartPath.cubicTo(
          center.dx - radius * 1.3,
          center.dy + radius * 0.1,
          center.dx - radius * 0.8,
          center.dy - radius * 0.95,
          center.dx,
          center.dy - radius * 0.3,
        );
        heartPath.cubicTo(
          center.dx + radius * 0.8,
          center.dy - radius * 0.95,
          center.dx + radius * 1.3,
          center.dy + radius * 0.1,
          center.dx,
          center.dy + radius * 0.75,
        );
        canvas.drawPath(heartPath, guidePaint);
        break;
      case 1:
        canvas.drawCircle(center, radius, guidePaint);
        canvas.drawCircle(
            Offset(center.dx - radius * 0.35, center.dy - radius * 0.25),
            radius * 0.12,
            guidePaint);
        canvas.drawCircle(
            Offset(center.dx + radius * 0.35, center.dy - radius * 0.25),
            radius * 0.12,
            guidePaint);
        final Rect smileRect = Rect.fromCircle(
            center: Offset(center.dx, center.dy + radius * 0.05),
            radius: radius * 0.55);
        canvas.drawArc(smileRect, 0.2, pi - 0.4, false, guidePaint);
        break;
      case 2:
        final Path starPath = Path();
        const int pointsCount = 5;
        for (int i = 0; i < pointsCount * 2; i++) {
          final double r = (i.isEven) ? radius : radius * 0.45;
          final double angle = (i * pi / pointsCount) - (pi / 2);
          final Offset pt = Offset(
            center.dx + r * cos(angle),
            center.dy + r * sin(angle),
          );
          if (i == 0) {
            starPath.moveTo(pt.dx, pt.dy);
          } else {
            starPath.lineTo(pt.dx, pt.dy);
          }
        }
        starPath.close();
        canvas.drawPath(starPath, guidePaint);
        break;
      case 3:
        for (int i = 0; i < 6; i++) {
          final double angle = i * pi / 3;
          canvas.drawCircle(
            Offset(center.dx + radius * 0.55 * cos(angle),
                center.dy + radius * 0.55 * sin(angle)),
            radius * 0.38,
            guidePaint,
          );
        }
        canvas.drawCircle(center, radius * 0.3, guidePaint);
        canvas.drawLine(
          Offset(center.dx, center.dy + radius * 0.6),
          Offset(center.dx, size.height - 20),
          guidePaint,
        );
        break;
      case 4:
        final Rect houseBody = Rect.fromCenter(
          center: Offset(center.dx, center.dy + radius * 0.25),
          width: radius * 1.4,
          height: radius * 1.1,
        );
        canvas.drawRect(houseBody, guidePaint);
        final Path roof = Path()
          ..moveTo(houseBody.left - 15, houseBody.top)
          ..lineTo(center.dx, center.dy - radius * 0.85)
          ..lineTo(houseBody.right + 15, houseBody.top)
          ..close();
        canvas.drawPath(roof, guidePaint);
        break;
      case 5:
        canvas.drawCircle(center, radius, guidePaint);
        for (int i = 0; i < 8; i++) {
          final double angle = i * pi / 4;
          canvas.drawLine(
            Offset(center.dx + radius * 1.1 * cos(angle),
                center.dy + radius * 1.1 * sin(angle)),
            Offset(center.dx + radius * 1.45 * cos(angle),
                center.dy + radius * 1.45 * sin(angle)),
            guidePaint,
          );
        }
        break;
      case 6:
        final Path crown = Path()
          ..moveTo(center.dx - radius, center.dy + radius * 0.5)
          ..lineTo(center.dx - radius * 0.8, center.dy - radius * 0.5)
          ..lineTo(center.dx - radius * 0.3, center.dy)
          ..lineTo(center.dx, center.dy - radius * 0.7)
          ..lineTo(center.dx + radius * 0.3, center.dy)
          ..lineTo(center.dx + radius * 0.8, center.dy - radius * 0.5)
          ..lineTo(center.dx + radius, center.dy + radius * 0.5)
          ..close();
        canvas.drawPath(crown, guidePaint);
        break;
      default:
        final Rect bookRect = Rect.fromCenter(
          center: center,
          width: radius * 1.7,
          height: radius * 1.2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bookRect, const Radius.circular(12)),
          guidePaint,
        );
        canvas.drawLine(
          Offset(center.dx, bookRect.top),
          Offset(center.dx, bookRect.bottom),
          guidePaint,
        );
        break;
    }

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final Paint p = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth;

      final Path path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant EtiquetteDrawingCanvasPainter oldDelegate) =>
      true;
}

class HundredLevelGamesGenerator {
  static const List<Map<String, dynamic>> _categoryClusters = [
    {
      'name': 'الفواكه الطازجة',
      'items': ['🍎', '🍌', '🍇', '🍉', '🍓', '🍒', '🍑', '🍍', '🥝', '🍊'],
    },
    {
      'name': 'حيوانات الغابة والمزرعة',
      'items': ['🦁', '🐰', '🐱', '🐶', '🐼', '🐨', '🐯', '🦊', '🐮', '🐑'],
    },
    {
      'name': 'وسائل النقل والمواصلات',
      'items': ['🚗', '🚌', '🚂', '✈️', '🚀', '🚁', '🚢', '🚲', '🚜', '🚑'],
    },
    {
      'name': 'عجائب السماء والفضاء',
      'items': ['☀️', '🌙', '⭐', '🌟', '🌈', '☁️', '⚡', '🪐', '☄️', '🌍'],
    },
    {
      'name': 'الأدوات المدرسية والتعلم',
      'items': ['✏️', '📘', '🖍️', '📏', '📐', '🎒', '✂️', '🖊️', '📓', '🔍'],
    },
    {
      'name': 'الكائنات البحرية',
      'items': ['🐬', '🐠', '🐙', '🐳', '🦀', '🦈', '🐡', '🦐', '🦑', '🐚'],
    },
    {
      'name': 'النباتات والزهور',
      'items': ['🌸', '🌹', '🌻', '🌷', '🌲', '🌳', '🌴', '🌵', '🍀', '🌿'],
    },
    {
      'name': 'الأشكال الهندسية والألوان',
      'items': ['🟥', '🟦', '🟩', '🟨', '🟪', '🟧', '🔵', '🟢', '🟡', '🔺'],
    },
    {
      'name': 'الخضروات الصحية',
      'items': ['🥕', '🥒', '🥦', '🍅', '🌽', '🍆', '🥔', '🥬', '🫑', '🧄'],
    },
    {
      'name': 'الرياضة والنشاط البدني',
      'items': ['⚽', '🏀', '🎾', '🏐', '🏈', '⚾', '🏓', '🏸', '🥊', '🏆'],
    },
  ];

  static Map<String, dynamic> getEtiquetteDrawingLevel(int index) {
    final int levelNum = (index % 100) + 1;
    const List<Map<String, String>> baseLessons = [
      {
        'shape': 'قلب المحبة والرحمة ❤️',
        'badge': 'آداب العائلة وبر الوالدين',
        'lesson':
            'من أجمل الآداب أن نبتسم في وجه ماما وبابا ونقول لهما بقلب محب: شكراً لكما، أنا أحبكما كثيراً!',
        'phrase': '«رَبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيراً»',
      },
      {
        'shape': 'الوجه المبتسم وإلقاء السلام 😊',
        'badge': 'آداب التحية والابتسامة',
        'lesson':
            'الطفل المؤدب يبدأ من يقابله بابتسامة لطيفة ويقول بصوت هادئ: السلام عليكم ورحمة الله.',
        'phrase': '«السَّلَامُ عَلَيْكُمْ وَرَحْمَةُ اللَّهِ»',
      },
      {
        'shape': 'نجمة الصدق والأمانة ⭐',
        'badge': 'الأخلاق الحميدة',
        'lesson':
            'الصدق يجعلنا مضيئين مثل النجمة اللامعة في السماء! البطل يقول الحقيقة دائماً ويحافظ على الأمانة.',
        'phrase': '«أَنَا صَادِقٌ وَأَمِينٌ دَائِماً»',
      },
      {
        'shape': 'زهرة النظافة والنظام 🌸',
        'badge': 'آداب النظافة والطهارة',
        'lesson':
            'النظافة من الإيمان! نغسل أيدينا بالماء والصابون قبل الأكل وبعده، ونحافظ على نظافة غرفتنا.',
        'phrase': '«الطُّهُورُ شَطْرُ الإِيمَانِ»',
      },
      {
        'shape': 'بيت الكرم والاستئذان 🏠',
        'badge': 'آداب الاستئذان والضيافة',
        'lesson':
            'نطرق الباب برفق ثلاث مرات ونستأذن قبل الدخول، ونرحب بضيوفنا بابتسامة وكرم.',
        'phrase': '«أَسْتَأْذِنُ بِأَدَبٍ قَبْلَ الدُّخُولِ»',
      },
      {
        'shape': 'شمس النشاط وذكر الصباح ☀️',
        'badge': 'آداب الاستيقاظ والنشاط',
        'lesson':
            'ننام مبكراً ونستيقظ بنشاط فنرتب فراشنا ونفرش أسناننا ونشكر الله على نعمه.',
        'phrase': '«الحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا»',
      },
      {
        'shape': 'تاج الكلمة الطيبة والشكر 👑',
        'badge': 'آداب الحديث والشكر',
        'lesson':
            'من يصنع لنا معروفاً نقول له: جزاك الله خيراً وشكراً لك، ونتحدث دائماً بصوت هادئ وجميل.',
        'phrase': '«الكَلِمَةُ الطَّيِّبَةُ صَدَقَةٌ»',
      },
      {
        'shape': 'كتاب العلم والحكمة 📘',
        'badge': 'آداب طالب العلم',
        'lesson':
            'نستمع لمعلمنا ولوالدينا بإنصات، ونحافظ على كتبنا وأدواتنا لنصبح علماء وأبطالاً نافعين.',
        'phrase': '«وَقُلْ رَبِّ زِدْنِي عِلْماً»',
      },
      {
        'shape': 'قلب إماطة الأذى عن الطريق 💚',
        'badge': 'آداب الطريق والبيئة',
        'lesson':
            'لا نلقي الأوراق في الشارع أبداً، بل نضعها في سلة المهملات ونبعد أي أذى عن طريق الناس.',
        'phrase': '«إِمَاطَةُ الأَذَى عَنِ الطَّرِيقِ صَدَقَةٌ»',
      },
      {
        'shape': 'ابتسامة المشاركة والتعاون مع الأصدقاء 🤝',
        'badge': 'آداب الصداقة والتعاون',
        'lesson':
            'نشارك ألعابنا مع إخوتنا وأصدقائنا بحب، ونساعد من يحتاج إلى المساعدة.',
        'phrase': '«المُؤْمِنُ لِلْمُؤْمِنِ كَالبُنْيَانِ يَشُدُّ بَعْضُهُ بَعْضاً»',
      },
    ];
    final item = baseLessons[index % baseLessons.length];
    return {
      'levelNumber': levelNum,
      'title': 'لوحة الآداب رقم $levelNum من ١٠٠: ${item['shape']}',
      'badge': item['badge']!,
      'etiquetteLesson': item['lesson']!,
      'arabicDuaOrPhrase': item['phrase']!,
      'instruction':
          'لوّن وارسم بيدك اللوحة رقم ($levelNum) واستمع لتشجيع الأبطال الخارقين!',
    };
  }

  static Map<String, dynamic> getOddOneOutLevel(int index) {
    final int levelNum = (index % 100) + 1;
    final int mainClusterIdx = index % _categoryClusters.length;
    final int oddClusterIdx =
        (mainClusterIdx + 1 + (index ~/ 10)) % _categoryClusters.length;

    final mainCluster = _categoryClusters[mainClusterIdx];
    final oddCluster = _categoryClusters[oddClusterIdx];

    final List<String> mainItems = List<String>.from(mainCluster['items'] as List);
    final List<String> oddItems = List<String>.from(oddCluster['items'] as List);

    final int offset = (index * 3) % mainItems.length;
    final String m1 = mainItems[offset % mainItems.length];
    final String m2 = mainItems[(offset + 1) % mainItems.length];
    final String m3 = mainItems[(offset + 2) % mainItems.length];
    final String oddItem = oddItems[(index * 2) % oddItems.length];

    final List<String> choices = [m1, m2, m3, oddItem];
    final int pos = index % 4;
    final String temp = choices[pos];
    choices[pos] = choices[3];
    choices[3] = temp;

    return {
      'levelNumber': levelNum,
      'category': '${mainCluster['name']} × ${oddCluster['name']}',
      'visualTheme': index % 4,
      'title':
          'المرحلة $levelNum من ١٠٠: أخرج الرمز المختلف عن مجموعة (${mainCluster['name']}):',
      'items': choices,
      'odd': oddItem,
      'explanation':
          'الرمز ($oddItem) ينتمي إلى (${oddCluster['name']})، بينما البقية من (${mainCluster['name']})!',
    };
  }

  static Map<String, dynamic> getPatternLogicLevel(int index) {
    final int levelNum = (index % 100) + 1;
    final clusterA = _categoryClusters[index % _categoryClusters.length];
    final clusterB = _categoryClusters[(index + 2) % _categoryClusters.length];
    final List<String> listA = List<String>.from(clusterA['items'] as List);
    final List<String> listB = List<String>.from(clusterB['items'] as List);

    final String a = listA[index % listA.length];
    final String b = listA[(index + 3) % listA.length];
    final String c = listB[index % listB.length];
    final String d = listB[(index + 4) % listB.length];

    final int patternType = index % 4;
    List<String> sequence;
    String answer;
    String hint;

    if (patternType == 0) {
      sequence = [a, b, a, b, a];
      answer = b;
      hint = 'اللغز $levelNum من ١٠٠: نمط متبادل ($a ثم $b ثم $a ثم $b)... ما التالي؟';
    } else if (patternType == 1) {
      sequence = [a, a, b, a, a];
      answer = b;
      hint = 'اللغز $levelNum من ١٠٠: عنصران متشابهان ($a $a) ثم ($b)... أكمل النمط!';
    } else if (patternType == 2) {
      sequence = [a, b, c, a, b];
      answer = c;
      hint = 'اللغز $levelNum من ١٠٠: ثلاثية مرتبة ($a ثم $b ثم $c)... ما العنصر الثالث؟';
    } else {
      sequence = [a, b, b, a, b];
      answer = b;
      hint = 'اللغز $levelNum من ١٠٠: ($a) يتبعه مرتان ($b $b)... ماذا يأتي الآن؟';
    }

    final List<String> options = [a, b, c, d];
    return {
      'levelNumber': levelNum,
      'sequence': sequence,
      'options': options,
      'answer': answer,
      'hint': hint,
    };
  }

  static List<String> getMemoryBoardForLevel(int levelNumber) {
    final int idx = (levelNumber - 1).clamp(0, 99);
    final cluster1 = _categoryClusters[idx % _categoryClusters.length];
    final cluster2 = _categoryClusters[(idx + 1) % _categoryClusters.length];
    final List<String> pool = [
      ...List<String>.from(cluster1['items'] as List),
      ...List<String>.from(cluster2['items'] as List),
    ];
    final int start = (idx * 2) % (pool.length - 6);
    final List<String> chosen6 = pool.sublist(start, start + 6);
    final List<String> pairs = [];
    for (final item in chosen6) {
      pairs.add(item);
      pairs.add(item);
    }
    pairs.shuffle(Random(levelNumber * 97));
    return pairs;
  }

  static Map<String, dynamic> getVisualMathLevel(int index) {
    final int levelNum = (index % 100) + 1;
    final cluster = _categoryClusters[index % _categoryClusters.length];
    final List<String> items = List<String>.from(cluster['items'] as List);
    final String emoji = items[index % items.length];

    final bool isAdd = (index % 2 == 1);
    int target;
    int a = 1;
    int b = 1;
    if (!isAdd) {
      target = (index % 9) + 2;
    } else {
      a = (index % 5) + 1;
      b = ((index ~/ 2) % 5) + 1;
      target = a + b;
    }

    final List<int> options = [
      target,
      max(1, target - 1),
      target + 1,
      target + 2,
    ];
    final int swapPos = index % 4;
    final int tmp = options[swapPos];
    options[swapPos] = options[0];
    options[0] = tmp;

    return {
      'levelNumber': levelNum,
      'mode': isAdd ? 'add' : 'count',
      'a': a,
      'b': b,
      'target': target,
      'emoji': emoji,
      'options': options,
    };
  }

  static const List<Map<String, dynamic>> _baseArabicVocabulary = [
    {'emoji': '🦁', 'word': 'أَسَد', 'missing': 'ـسَد', 'ans': 'أ', 'opts': ['أ', 'ب', 'ت', 'س']},
    {'emoji': '🏠', 'word': 'بَيْت', 'missing': 'ـيْت', 'ans': 'ب', 'opts': ['ب', 'ت', 'ث', 'ن']},
    {'emoji': '🍎', 'word': 'تُفَّاحَة', 'missing': 'ـفَّاحَة', 'ans': 'ت', 'opts': ['ج', 'ت', 'خ', 'م']},
    {'emoji': '🦊', 'word': 'ثَعْلَب', 'missing': 'ـعْلَب', 'ans': 'ث', 'opts': ['ب', 'ت', 'ث', 'ف']},
    {'emoji': '🐪', 'word': 'جَمَل', 'missing': 'ـمَل', 'ans': 'ج', 'opts': ['ج', 'ح', 'خ', 'ع']},
    {'emoji': '🕊️', 'word': 'حَمَامَة', 'missing': 'ـمَامَة', 'ans': 'ح', 'opts': ['ج', 'ح', 'خ', 'هـ']},
    {'emoji': '🐑', 'word': 'خَرُوف', 'missing': 'ـرُوف', 'ans': 'خ', 'opts': ['ح', 'خ', 'غ', 'ق']},
    {'emoji': '🐻', 'word': 'دُبّ', 'missing': 'ـبّ', 'ans': 'د', 'opts': ['د', 'ذ', 'ر', 'ز']},
    {'emoji': '🌽', 'word': 'ذُرَة', 'missing': 'ـرَة', 'ans': 'ذ', 'opts': ['د', 'ذ', 'ز', 'ظ']},
    {'emoji': ' pomegranate', 'word': 'رُمَّان', 'missing': 'ـمَّان', 'ans': 'ر', 'opts': ['د', 'ر', 'ز', 'و']},
    {'emoji': '🦒', 'word': 'زَرَافَة', 'missing': 'ـرَافَة', 'ans': 'ز', 'opts': ['ر', 'ز', 'س', 'ص']},
    {'emoji': '🐟', 'word': 'سَمَكَة', 'missing': 'ـمَكَة', 'ans': 'س', 'opts': ['ش', 'س', 'ص', 'ز']},
    {'emoji': '☀️', 'word': 'شَمْس', 'missing': 'ـمْس', 'ans': 'ش', 'opts': ['س', 'ش', 'ص', 'ض']},
    {'emoji': '🦅', 'word': 'صَقْر', 'missing': 'ـقْر', 'ans': 'ص', 'opts': ['س', 'ش', 'ص', 'ط']},
    {'emoji': '🐸', 'word': 'ضِفْدَع', 'missing': 'ـفْدَع', 'ans': 'ض', 'opts': ['ص', 'ض', 'ط', 'ظ']},
    {'emoji': '✈️', 'word': 'طَائِرَة', 'missing': 'ـائِرَة', 'ans': 'ط', 'opts': ['ت', 'ط', 'ظ', 'د']},
    {'emoji': '✉️', 'word': 'ظَرْف', 'missing': 'ـرْف', 'ans': 'ظ', 'opts': ['ذ', 'ز', 'ط', 'ظ']},
    {'emoji': '🍇', 'word': 'عِنَب', 'missing': 'ـنَب', 'ans': 'ع', 'opts': ['ع', 'غ', 'ف', 'ق']},
    {'emoji': '☁️', 'word': 'غَيْمَة', 'missing': 'ـيْمَة', 'ans': 'غ', 'opts': ['ع', 'غ', 'خ', 'ق']},
    {'emoji': '🦋', 'word': 'فَرَاشَة', 'missing': 'ـرَاشَة', 'ans': 'ف', 'opts': ['ص', 'ض', 'ف', 'ن']},
    {'emoji': '🌙', 'word': 'قَمَر', 'missing': 'ـمَر', 'ans': 'ق', 'opts': ['ف', 'ق', 'ك', 'ل']},
    {'emoji': '📘', 'word': 'كِتَاب', 'missing': 'ـتَاب', 'ans': 'ك', 'opts': ['ق', 'ك', 'ل', 'م']},
    {'emoji': '🍋', 'word': 'لَيْمُون', 'missing': 'ـيْمُون', 'ans': 'ل', 'opts': ['ك', 'ل', 'م', 'ن']},
    {'emoji': '🍌', 'word': 'مَوْز', 'missing': 'ـوْز', 'ans': 'م', 'opts': ['ل', 'م', 'ن', 'هـ']},
    {'emoji': '🐝', 'word': 'نَحْلَة', 'missing': 'ـحْلَة', 'ans': 'ن', 'opts': ['ب', 'ت', 'ن', 'ي']},
    {'emoji': '🎁', 'word': 'هَدِيَّة', 'missing': 'ـدِيَّة', 'ans': 'هـ', 'opts': ['ع', 'هـ', 'و', 'ي']},
    {'emoji': '🌹', 'word': 'وَرْدَة', 'missing': 'ـرْدَة', 'ans': 'و', 'opts': ['ر', 'ز', 'و', 'ي']},
    {'emoji': '🖐️', 'word': 'يَد', 'missing': 'ـد', 'ans': 'ي', 'opts': ['ب', 'ت', 'ن', 'ي']},
  ];

  static Map<String, dynamic> getArabicWordLevel(int index) {
    final int levelNum = (index % 100) + 1;
    final item = _baseArabicVocabulary[index % _baseArabicVocabulary.length];
    final String emoji = (item['emoji'] as String).trim() == 'pomegranate'
        ? '🍎'
        : item['emoji'] as String;
    final String word = item['word'] as String;
    return {
      'levelNumber': levelNum,
      'emoji': emoji,
      'word': word,
      'missingDisplay': item['missing'] as String,
      'prompt': 'المرحلة $levelNum من ١٠٠ — اختر الحرف الأول لكلمة ($word):',
      'options': List<String>.from(item['opts'] as List),
      'answer': item['ans'] as String,
    };
  }
}

class BrainGamesHubScreen extends StatefulWidget {
  final AppStateManager appState;
  const BrainGamesHubScreen({super.key, required this.appState});

  @override
  State<BrainGamesHubScreen> createState() => _BrainGamesHubScreenState();
}

class _BrainGamesHubScreenState extends State<BrainGamesHubScreen> {
  int _selectedGameIndex = 0;
  String? _heroReactionMessage;

  int _etiquetteBoardIndex = 0;
  final List<EtiquetteStrokePath> _drawingStrokes = [];
  Color _selectedBrushColor = const Color(0xFF14B8A6);
  double _selectedBrushSize = 8.0;
  int _drawnPointsCount = 0;

  int _oddQuestionIndex = 0;
  String? _oddFeedback;
  bool _oddCorrect = false;

  int _patternQuestionIndex = 0;
  String? _patternFeedback;
  bool _patternCorrect = false;

  int _memoryLevel = 1;
  int _memoryMoves = 0;
  int _memoryMatches = 0;
  List<String> _memoryBoard = [];
  List<bool> _memoryRevealed = [];
  List<bool> _memorySolved = [];
  int? _firstFlippedIndex;
  bool _memoryBusy = false;

  int _mathQuestionIndex = 0;
  String? _mathFeedback;
  bool _mathAnswered = false;

  int _wordQuestionIndex = 0;
  String? _wordFeedback;
  bool _wordCorrect = false;

  @override
  void initState() {
    super.initState();
    _initMemoryGame();
    widget.appState.logChildRealtimeActivity(
      statusSummary: '🧠 يتفاعل داخل واحة الـ ١٠٠ مرحلة لألعاب الذكاء والآداب',
      actionLogText: 'دخل إلى واحة ألعاب الذكاء (١٠٠ مرحلة لكل لعبة)',
      categoryBadge: 'ألعاب الذكاء',
    );
    final childName =
        widget.appState.currentAccount?.activeChild.name ?? 'بطل حنين';
    CalmVoiceService.instance.speakCalmly(
      'أهلاً بك يا $childName! كل لعبة هنا تحتوي على مئة مرحلة مشوقة، وأصدقاؤك الأبطال الخارقون يشجعونك في كل خطوة!',
    );
  }

  void _initMemoryGame() {
    final List<String> pairs =
        HundredLevelGamesGenerator.getMemoryBoardForLevel(_memoryLevel);
    setState(() {
      _memoryBoard = pairs;
      _memoryRevealed = List<bool>.filled(pairs.length, false);
      _memorySolved = List<bool>.filled(pairs.length, false);
      _firstFlippedIndex = null;
      _memoryMoves = 0;
      _memoryMatches = 0;
      _memoryBusy = false;
    });
  }

  Future<void> _onMemoryCardTap(int index) async {
    if (_memoryBusy || _memoryRevealed[index] || _memorySolved[index]) return;

    setState(() {
      _memoryRevealed[index] = true;
    });

    if (_firstFlippedIndex == null) {
      _firstFlippedIndex = index;
      return;
    }

    final int firstIdx = _firstFlippedIndex!;
    _firstFlippedIndex = null;
    _memoryMoves++;

    if (_memoryBoard[firstIdx] == _memoryBoard[index]) {
      setState(() {
        _memorySolved[firstIdx] = true;
        _memorySolved[index] = true;
        _memoryMatches++;
      });

      if (_memoryMatches == _memoryBoard.length ~/ 2) {
        await widget.appState.recordBrainGameWin(
          gameId: 'memory_match_lvl_$_memoryLevel',
          gameTitle: 'الذاكرة البصرية (المرحلة $_memoryLevel من ١٠٠)',
          earnedIqPoints: 20,
          earnedStars: 2,
        );
        setState(() {
          _heroReactionMessage =
              '🎉 الأبطال الخارقون يصفقون لك! أتممت المرحلة $_memoryLevel من ١٠٠ في لعبة الذاكرة!';
        });
        CalmVoiceService.instance.speakCalmly(
          'ما شاء الله! أنهيت المرحلة $_memoryLevel من مئة في لعبة الذاكرة البصرية بنجاح!',
        );
      } else {
        CalmVoiceService.instance.speakCalmly('تطابق رائع!');
      }
    } else {
      _memoryBusy = true;
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        setState(() {
          _memoryRevealed[firstIdx] = false;
          _memoryRevealed[index] = false;
          _memoryBusy = false;
        });
      }
    }
  }

  Widget _buildHundredLevelSelectorBar({
    required int currentLevelZeroBased,
    required Color accentColor,
    required void Function(int newZeroBasedIndex) onSelectLevel,
  }) {
    final int currentDisplay = (currentLevelZeroBased % 100) + 1;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '🏆 المرحلة $currentDisplay من ١٠٠',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final int prev = (currentLevelZeroBased - 1 + 100) % 100;
                    onSelectLevel(prev);
                  },
                  icon: const Icon(Icons.arrow_back_ios_new, size: 15),
                ),
                Text(
                  '$currentDisplay / 100',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final int next = (currentLevelZeroBased + 1) % 100;
                    onSelectLevel(next);
                  },
                  icon: const Icon(Icons.arrow_forward_ios, size: 15),
                ),
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: currentDisplay.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            activeColor: accentColor,
            label: 'المرحلة $currentDisplay',
            onChanged: (v) => onSelectLevel(v.round() - 1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final child = widget.appState.currentAccount?.activeChild;
        if (child == null) return const SizedBox.shrink();

        final List<Map<String, dynamic>> gamesMeta = [
          {
            'title': 'مرسم الآداب (١٠٠ لوحة)',
            'icon': '🎨',
            'skill': '١٠٠ لوحة رسم وتلوين لتعلم الآداب والأخلاق',
            'color': const Color(0xFF10B981),
          },
          {
            'title': 'قوة الملاحظة (١٠٠ مرحلة)',
            'icon': '🔍',
            'skill': '١٠٠ مرحلة لتصنيف الأشكال واكتشاف المختلف',
            'color': const Color(0xFFEC4899),
          },
          {
            'title': 'الألغاز والمنطق (١٠٠ لغز)',
            'icon': '🧩',
            'skill': '١٠٠ لغز لاستنتاج الأنماط والتسلسل المنطقي',
            'color': const Color(0xFFF59E0B),
          },
          {
            'title': 'الذاكرة البصرية (١٠٠ مرحلة)',
            'icon': '🃏',
            'skill': '١٠٠ مستوى متدرج لتقوية الذاكرة والتركيز',
            'color': const Color(0xFF14B8A6),
          },
          {
            'title': 'الحساب والجمع (١٠٠ مرحلة)',
            'icon': '🔢',
            'skill': '١٠٠ مسألة عدّ وجمع بصري لتنمية الذكاء الرياضي',
            'color': const Color(0xFF38BDF8),
          },
          {
            'title': 'الحروف والكلمات (١٠٠ مرحلة)',
            'icon': '🔤',
            'skill': '١٠٠ تحدٍ للذكاء اللغوي ومخارج الحروف العربية',
            'color': const Color(0xFFA855F7),
          },
        ];

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              '🧠 واحة الـ ١٠٠ مرحلة والأبطال الخارقين',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: CuteSuperheroCompanionBanner(
                      appState: widget.appState,
                      compactMode: false,
                      customCheerMessage: _heroReactionMessage,
                    ),
                  ),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: gamesMeta.length,
                      itemBuilder: (ctx, i) {
                        final g = gamesMeta[i];
                        final bool isSelected = _selectedGameIndex == i;
                        final Color accent = g['color'] as Color;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedGameIndex = i;
                              _heroReactionMessage = null;
                            });
                            widget.appState.logChildRealtimeActivity(
                              statusSummary: '🎮 يلعب الآن: ${g['title']}',
                              actionLogText: 'انتقل إلى لعبة (${g['title']})',
                              categoryBadge: 'ألعاب الذكاء',
                            );
                            CalmVoiceService.instance.speakCalmly(
                              '${g['title']}، ${g['skill']}',
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 158,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 4),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      colors: [
                                        accent.withOpacity(0.38),
                                        const Color(0xFF1E293B),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color:
                                  isSelected ? null : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? accent : Colors.white12,
                                width: isSelected ? 2.2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(g['icon'] as String,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(height: 4),
                                Text(
                                  g['title'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: _buildActiveBrainGameCard(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveBrainGameCard() {
    switch (_selectedGameIndex) {
      case 0:
        return _buildEtiquetteDrawingStudioGame();
      case 1:
        return _buildOddOneOutGame();
      case 2:
        return _buildPatternLogicGame();
      case 3:
        return _buildMemoryMatchGame();
      case 4:
        return _buildVisualMathGame();
      case 5:
        return _buildArabicWordBuilderGame();
      default:
        return _buildEtiquetteDrawingStudioGame();
    }
  }

  Widget _buildEtiquetteDrawingStudioGame() {
    final lesson = HundredLevelGamesGenerator.getEtiquetteDrawingLevel(
        _etiquetteBoardIndex);
    final int levelNum = lesson['levelNumber'] as int;
    final String title = lesson['title'] as String;
    final String badge = lesson['badge'] as String;
    final String etiquetteText = lesson['etiquetteLesson'] as String;
    final String phrase = lesson['arabicDuaOrPhrase'] as String;
    final String instruction = lesson['instruction'] as String;

    final List<Color> palette = [
      const Color(0xFF14B8A6),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF38BDF8),
      const Color(0xFFA855F7),
      const Color(0xFFEF4444),
      const Color(0xFF22C55E),
      Colors.white,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981), width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _etiquetteBoardIndex,
            accentColor: const Color(0xFF10B981),
            onSelectLevel: (newIdx) {
              setState(() {
                _etiquetteBoardIndex = newIdx;
                _drawingStrokes.clear();
                _drawnPointsCount = 0;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🎨 $badge ($levelNum / 100)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA7F3D0),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'استمع لدرس الأدب بصوت هادئ',
                onPressed: () {
                  CalmVoiceService.instance.speakCalmly(
                    '$title. $etiquetteText. $phrase',
                    rate: 0.35,
                  );
                },
                icon: const Icon(Icons.volume_up_rounded,
                    color: Color(0xFFFDE68A)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            etiquetteText,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
            ),
            child: Text(
              '🗣️ عبارة الأدب: $phrase',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFDE68A),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '✏️ $instruction',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 230,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _drawingStrokes.add(
                      EtiquetteStrokePath(
                        points: [details.localPosition],
                        color: _selectedBrushColor,
                        strokeWidth: _selectedBrushSize,
                      ),
                    );
                    _drawnPointsCount++;
                  });
                },
                onPanUpdate: (details) {
                  if (_drawingStrokes.isEmpty) return;
                  setState(() {
                    _drawingStrokes.last.points.add(details.localPosition);
                    _drawnPointsCount++;
                  });
                },
                child: CustomPaint(
                  size: const Size(double.infinity, 230),
                  painter: EtiquetteDrawingCanvasPainter(
                    strokes: _drawingStrokes,
                    templateIndex: _etiquetteBoardIndex,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('الألوان: ', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: palette.map((c) {
                    final bool isSel = _selectedBrushColor == c;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedBrushColor = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.white24,
                            width: isSel ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              IconButton(
                tooltip: 'مسح اللوحة',
                onPressed: () {
                  setState(() {
                    _drawingStrokes.clear();
                    _drawnPointsCount = 0;
                  });
                },
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.redAccent),
              ),
            ],
          ),
          Row(
            children: [
              const Text('حجم الفرشاة:', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _selectedBrushSize,
                  min: 4.0,
                  max: 18.0,
                  activeColor: _selectedBrushColor,
                  onChanged: (v) => setState(() => _selectedBrushSize = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    if (_drawnPointsCount < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              '🎨 ارسم ولوّن أولاً داخل اللوحة بأصبعك لتكسب نقاط الذكاء والآداب!'),
                          backgroundColor: Color(0xFFF59E0B),
                        ),
                      );
                      return;
                    }
                    await widget.appState.recordBrainGameWin(
                      gameId: 'etiquette_draw_$levelNum',
                      gameTitle: 'مرسم الآداب (لوحة $levelNum من ١٠٠)',
                      earnedIqPoints: 20,
                      earnedStars: 2,
                    );
                    setState(() {
                      _heroReactionMessage =
                          '🌟 الأبطال الخارقون فخورون بلوحتك رقم $levelNum وتعلمك لعبارة: $phrase!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'لوحة فنية رائعة يا فنان الآداب! أتممت اللوحة رقم $levelNum من مئة!',
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'حفظ الرسمة (+20 ذكاء)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _etiquetteBoardIndex = (_etiquetteBoardIndex + 1) % 100;
                    _drawingStrokes.clear();
                    _drawnPointsCount = 0;
                  });
                },
                icon: const Icon(Icons.navigate_next),
                label: const Text('اللوحة التالية'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOddOneOutGame() {
    final q = HundredLevelGamesGenerator.getOddOneOutLevel(_oddQuestionIndex);
    final int levelNum = q['levelNumber'] as int;
    final String category = q['category'] as String;
    final int themeIdx = q['visualTheme'] as int;
    final String title = q['title'] as String;
    final List<String> items = List<String>.from(q['items'] as List);
    final String odd = q['odd'] as String;
    final String explanation = q['explanation'] as String;

    final List<List<Color>> themeGradients = [
      [const Color(0xFF31102F), const Color(0xFF1E293B)],
      [const Color(0xFF0F3D3E), const Color(0xFF1E293B)],
      [const Color(0xFF1E1B4B), const Color(0xFF172554)],
      [const Color(0xFF3B1D0A), const Color(0xFF1E293B)],
    ];
    final List<Color> themeBorders = [
      const Color(0xFFEC4899),
      const Color(0xFF14B8A6),
      const Color(0xFF38BDF8),
      const Color(0xFFF59E0B),
    ];

    final Color activeBorder = themeBorders[themeIdx % themeBorders.length];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: themeGradients[themeIdx % themeGradients.length],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: activeBorder, width: 1.8),
      ),
      child: Column(
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _oddQuestionIndex,
            accentColor: activeBorder,
            onSelectLevel: (newIdx) {
              setState(() {
                _oddQuestionIndex = newIdx;
                _oddCorrect = false;
                _oddFeedback = null;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🔍 $category',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: activeBorder,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => CalmVoiceService.instance.speakCalmly(title),
                icon: Icon(Icons.volume_up_rounded, color: activeBorder),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final String itemEmoji = items[i];
              final bool isRoundedTheme = themeIdx % 2 == 1;
              return GestureDetector(
                onTap: () async {
                  if (itemEmoji == odd) {
                    setState(() {
                      _oddCorrect = true;
                      _oddFeedback = '✅ ملاحظة ذكية جداً! $explanation';
                      _heroReactionMessage =
                          '🦸‍♂️ سبايدي وفارس الليل يقولان لك: قوة ملاحظتك خارقة في المرحلة $levelNum!';
                    });
                    await widget.appState.recordBrainGameWin(
                      gameId: 'odd_one_out_$levelNum',
                      gameTitle: 'قوة الملاحظة (المرحلة $levelNum من ١٠٠)',
                      earnedIqPoints: 15,
                      earnedStars: 1,
                    );
                    CalmVoiceService.instance.speakCalmly(
                      'أحسنت الملاحظة في المرحلة $levelNum! $explanation',
                    );
                  } else {
                    setState(() {
                      _oddCorrect = false;
                      _oddFeedback =
                          '👀 هذا العنصر يشبه أصدقاءه في المجموعة، ابحث عن العنصر المختلف تماماً!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'انظر بدقة يا بطل وابحث عن الشكل المختلف عن المجموعة.',
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF0F172A),
                        activeBorder.withOpacity(0.18),
                      ],
                    ),
                    borderRadius:
                        BorderRadius.circular(isRoundedTheme ? 34 : 18),
                    border: Border.all(
                      color: activeBorder.withOpacity(0.65),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      itemEmoji,
                      style: const TextStyle(fontSize: 42),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_oddFeedback != null) ...[
            const SizedBox(height: 12),
            Text(
              _oddFeedback!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _oddCorrect
                    ? const Color(0xFF14B8A6)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: activeBorder,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _oddQuestionIndex = (_oddQuestionIndex + 1) % 100;
                  _oddCorrect = false;
                  _oddFeedback = null;
                });
              },
              icon: const Icon(Icons.navigate_next),
              label: Text(
                'المرحلة التالية (${(levelNum % 100) + 1} من ١٠٠)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternLogicGame() {
    final q =
        HundredLevelGamesGenerator.getPatternLogicLevel(_patternQuestionIndex);
    final int levelNum = q['levelNumber'] as int;
    final List<String> seq = List<String>.from(q['sequence'] as List);
    final List<String> opts = List<String>.from(q['options'] as List);
    final String ans = q['answer'] as String;
    final String hint = q['hint'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _patternQuestionIndex,
            accentColor: const Color(0xFFF59E0B),
            onSelectLevel: (newIdx) {
              setState(() {
                _patternQuestionIndex = newIdx;
                _patternFeedback = null;
                _patternCorrect = false;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🧩 مختبر المنطق والأنماط ($levelNum / 100)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => CalmVoiceService.instance.speakCalmly(hint),
                icon: const Icon(Icons.volume_up_rounded,
                    color: Color(0xFFF59E0B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [
                ...seq.map(
                    (s) => Text(s, style: const TextStyle(fontSize: 32))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: const Text('؟',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: opts.map((option) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                onPressed: () async {
                  if (option == ans) {
                    setState(() {
                      _patternCorrect = true;
                      _patternFeedback =
                          '✅ تفكير منطقي عبقري في اللغز $levelNum! الإجابة ($option) صحيحة (+15 ذكاء)';
                      _heroReactionMessage =
                          '🦇 فارس الليل يحييك: استنتاج منطقي مذهل في المرحلة $levelNum من ١٠٠!';
                    });
                    await widget.appState.recordBrainGameWin(
                      gameId: 'pattern_logic_$levelNum',
                      gameTitle: 'الألغاز والمنطق (لغز $levelNum من ١٠٠)',
                      earnedIqPoints: 15,
                      earnedStars: 1,
                    );
                    CalmVoiceService.instance.speakCalmly(
                      'أحسنت التفكير المنطقي في المرحلة $levelNum!',
                    );
                  } else {
                    setState(() {
                      _patternCorrect = false;
                      _patternFeedback =
                          '💡 تأمل الترتيب مرة أخرى بهدوء وحاول مجدداً!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'فكر بهدوء يا بطل، لاحظ الترتيب وحاول مرة أخرى.',
                    );
                  }
                },
                child: Text(option, style: const TextStyle(fontSize: 30)),
              );
            }).toList(),
          ),
          if (_patternFeedback != null) ...[
            const SizedBox(height: 12),
            Text(
              _patternFeedback!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _patternCorrect
                    ? const Color(0xFF14B8A6)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black87,
              ),
              onPressed: () {
                setState(() {
                  _patternQuestionIndex = (_patternQuestionIndex + 1) % 100;
                  _patternFeedback = null;
                  _patternCorrect = false;
                });
              },
              icon: const Icon(Icons.navigate_next),
              label: Text(
                'اللغز التالي (${(levelNum % 100) + 1} من ١٠٠)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryMatchGame() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _memoryLevel - 1,
            accentColor: const Color(0xFF14B8A6),
            onSelectLevel: (newIdx) {
              setState(() {
                _memoryLevel = newIdx + 1;
              });
              _initMemoryGame();
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🃏 الذاكرة البصرية (المرحلة $_memoryLevel من ١٠٠)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _memoryLevel = (_memoryLevel % 100) + 1;
                  });
                  _initMemoryGame();
                },
                icon: const Icon(Icons.skip_next, size: 16),
                label: const Text('المرحلة التالية'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Chip(
                backgroundColor: const Color(0xFF0F172A),
                label: Text('المحاولات: $_memoryMoves'),
              ),
              Chip(
                backgroundColor: const Color(0xFF0F172A),
                label: Text(
                    'التطابقات: $_memoryMatches / ${_memoryBoard.length ~/ 2}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: _memoryBoard.length,
            itemBuilder: (ctx, index) {
              final bool isUp =
                  _memoryRevealed[index] || _memorySolved[index];
              final bool isSolved = _memorySolved[index];
              return GestureDetector(
                onTap: () => _onMemoryCardTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: isSolved
                        ? const Color(0xFF14B8A6).withOpacity(0.3)
                        : isUp
                            ? const Color(0xFF334155)
                            : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSolved
                          ? const Color(0xFF14B8A6)
                          : isUp
                              ? const Color(0xFFF59E0B)
                              : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isUp ? _memoryBoard[index] : '🌟',
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisualMathGame() {
    final mathData =
        HundredLevelGamesGenerator.getVisualMathLevel(_mathQuestionIndex);
    final int levelNum = mathData['levelNumber'] as int;
    final bool isAdd = (mathData['mode'] as String) == 'add';
    final int a = mathData['a'] as int;
    final int b = mathData['b'] as int;
    final int target = mathData['target'] as int;
    final String emoji = mathData['emoji'] as String;
    final List<int> options = List<int>.from(mathData['options'] as List);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _mathQuestionIndex,
            accentColor: const Color(0xFF38BDF8),
            onSelectLevel: (newIdx) {
              setState(() {
                _mathQuestionIndex = newIdx;
                _mathFeedback = null;
                _mathAnswered = false;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isAdd
                      ? '🔢 الجمع المصور (المرحلة $levelNum من ١٠٠)'
                      : '🔢 العدّ البصري (المرحلة $levelNum من ١٠٠)',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => CalmVoiceService.instance.speakCalmly(
                  isAdd
                      ? 'المرحلة $levelNum: اجمع $a زائد $b يساوي كم؟'
                      : 'المرحلة $levelNum: عدّ الأشكال بهدوء واختر الرقم الصحيح!',
                ),
                icon: const Icon(Icons.volume_up_rounded,
                    color: Color(0xFF38BDF8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: isAdd
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(
                            a,
                            (_) => Text(emoji,
                                style: const TextStyle(fontSize: 30)),
                          ),
                        ),
                      ),
                      const Text(
                        '➕',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B)),
                      ),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(
                            b,
                            (_) => Text(emoji,
                                style: const TextStyle(fontSize: 30)),
                          ),
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(
                      target,
                      (_) => Text(emoji, style: const TextStyle(fontSize: 34)),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: options.map((numOpt) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                ),
                onPressed: () async {
                  if (numOpt == target) {
                    if (!_mathAnswered) {
                      _mathAnswered = true;
                      await widget.appState.recordBrainGameWin(
                        gameId: 'visual_math_$levelNum',
                        gameTitle: 'الحساب البصري (المرحلة $levelNum من ١٠٠)',
                        earnedIqPoints: 15,
                        earnedStars: 1,
                      );
                    }
                    setState(() {
                      _mathFeedback =
                          '🎉 عبقري في الحساب! الناتج ($numOpt) صحيح (+15 ذكاء)';
                      _heroReactionMessage =
                          '⚡ بيكا وسوبر نور يهتفان لك: إجابة حسابية متقنة في المرحلة $levelNum!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'رائع يا بطل الحساب! الإجابة هي $numOpt!',
                    );
                  } else {
                    setState(() {
                      _mathFeedback =
                          '🔢 عدّ الأشكال بأصابعك مرة أخرى بهدوء وحاول مجدداً!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'هيا نعدّ الأشكال معاً ببطء ونحاول مرة أخرى.',
                    );
                  }
                },
                child: Text(
                  '$numOpt',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),
          if (_mathFeedback != null) ...[
            const SizedBox(height: 12),
            Text(
              _mathFeedback!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black87,
              ),
              onPressed: () {
                setState(() {
                  _mathQuestionIndex = (_mathQuestionIndex + 1) % 100;
                  _mathFeedback = null;
                  _mathAnswered = false;
                });
              },
              icon: const Icon(Icons.navigate_next),
              label: Text(
                'المرحلة الحسابية التالية (${(levelNum % 100) + 1} من ١٠٠)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArabicWordBuilderGame() {
    final q =
        HundredLevelGamesGenerator.getArabicWordLevel(_wordQuestionIndex);
    final int levelNum = q['levelNumber'] as int;
    final String emoji = q['emoji'] as String;
    final String fullWord = q['word'] as String;
    final String missingDisplay = q['missingDisplay'] as String;
    final String prompt = q['prompt'] as String;
    final List<String> opts = List<String>.from(q['options'] as List);
    final String ans = q['answer'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _buildHundredLevelSelectorBar(
            currentLevelZeroBased: _wordQuestionIndex,
            accentColor: const Color(0xFFA855F7),
            onSelectLevel: (newIdx) {
              setState(() {
                _wordQuestionIndex = newIdx;
                _wordCorrect = false;
                _wordFeedback = null;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🔤 الذكاء اللغوي ($levelNum / 100)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => CalmVoiceService.instance.speakCalmly(
                  '$prompt الكلمة هي $fullWord',
                  rate: 0.34,
                ),
                icon: const Icon(Icons.volume_up_rounded,
                    color: Color(0xFFA855F7)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(emoji, style: const TextStyle(fontSize: 54)),
          const SizedBox(height: 6),
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _wordCorrect ? fullWord : '؟ $missingDisplay',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFDE68A),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: opts.map((letter) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFA855F7)),
                  ),
                ),
                onPressed: () async {
                  if (letter == ans) {
                    setState(() {
                      _wordCorrect = true;
                      _wordFeedback =
                          '✅ أحسنت يا فصيح! حرف ($letter) يكمل كلمة ($fullWord) (+15 ذكاء)';
                      _heroReactionMessage =
                          '👧🎒 المستكشفة الصغيرة والشبل سيمبا يحيون فصاحتك في المرحلة $levelNum!';
                    });
                    await widget.appState.recordBrainGameWin(
                      gameId: 'arabic_word_$levelNum',
                      gameTitle: 'الذكاء اللغوي (المرحلة $levelNum من ١٠٠)',
                      earnedIqPoints: 15,
                      earnedStars: 1,
                    );
                    CalmVoiceService.instance.speakCalmly(
                      'ممتاز! حرف $letter، $fullWord!',
                      rate: 0.35,
                    );
                  } else {
                    setState(() {
                      _wordCorrect = false;
                      _wordFeedback =
                          '🗣️ استمع لصوت الكلمة مرة أخرى وجرب حرفاً آخر!';
                    });
                    CalmVoiceService.instance.speakCalmly(
                      'استمع جيداً لصوت أول الكلمة: $fullWord',
                      rate: 0.34,
                    );
                  }
                },
                child: Text(
                  letter,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),
          if (_wordFeedback != null) ...[
            const SizedBox(height: 12),
            Text(
              _wordFeedback!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFFA855F7)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _wordQuestionIndex = (_wordQuestionIndex + 1) % 100;
                  _wordCorrect = false;
                  _wordFeedback = null;
                });
              },
              icon: const Icon(Icons.navigate_next),
              label: Text(
                'الكلمة التالية (${(levelNum % 100) + 1} من ١٠٠)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
