import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../persistence/shared_preferences_provider.dart';

// ─── Enum ─────────────────────────────────────────────────────────────────────

enum ShowcaseBlock {
  // ── Главная ──────────────────────────────────────
  homeQuickCards,
  homeDigest,
  homePhotos,

  // ── Треки ────────────────────────────────────────
  tracksFilters,
  tracksItem,
  tracksAddButton,

  // ── Фотоотчёты ───────────────────────────────────
  photosStats,
  photosDateFilter,
  photosGrid,

  // ── Счета ────────────────────────────────────────
  invoicesFilters,
  invoicesItem,

  // ── Профиль ──────────────────────────────────────
  profilePersonalData,
  profileStats,
  profileExport,
  profileLogout,

  // ── Новости ──────────────────────────────────────
  newsHeader,
  newsCard,

  // ── Правила ──────────────────────────────────────
  rulesHeader,
  rulesCard,

  // ── Чат с поддержкой ─────────────────────────────
  supportMessages,
  supportInput,

  // ── Чат по оплате ────────────────────────────────
  paymentChatInfoBanner,
  paymentChatInput,

  // ── Добавить треки ───────────────────────────────
  addTracksInput,
  addTracksSubmit,

  // ── Поиск ────────────────────────────────────────
  searchInput,

  // ── СП Сборки ────────────────────────────────────
  spAssemblyCard,
  spAssemblyStats,
  spAssemblyParticipants,
  spAssemblyTracks,

  // ── СП Редактирование трека ───────────────────────
  spTrackEditParticipant,
  spTrackEditPrices,
  spTrackEditSave,

  // ── Реферальная программа ────────────────────────
  referralInfo,

  // ── Калькулятор ──────────────────────────────────
  calculatorForm,

  // ── Тарифы ───────────────────────────────────────
  tariffsList,
}

// ─── Backward-compat alias ────────────────────────────────────────────────────
/// @deprecated Use ShowcaseBlock instead
enum ShowcasePage {
  home,
  tracks,
  invoices,
  profile,
  photos,
  addTracks,
  support,
  paymentChat,
  search,
  news,
  rules,
  notifications,
  spAssemblies,
  spAssemblyDetail,
  spTrackEdit,
}

// ─── Tutorial helpers ─────────────────────────────────────────────────────────

/// Создаёт TargetFocus для tutorial_coach_mark с единым стилем приложения.
TargetFocus buildTutorialTarget({
  required GlobalKey key,
  required String title,
  required String description,
  ContentAlign align = ContentAlign.bottom,
  double radius = 12.0,
  ShapeLightFocus shape = ShapeLightFocus.RRect,
}) {
  return TargetFocus(
    keyTarget: key,
    shape: shape,
    radius: radius,
    alignSkip: Alignment.bottomRight,
    enableOverlayTab: true,
    contents: [
      TargetContent(
        align: align,
        child: _TutorialContent(title: title, description: description),
      ),
    ],
  );
}

class _TutorialContent extends StatelessWidget {
  final String title;
  final String description;

  const _TutorialContent({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ShowcaseService {
  static const String _prefix = 'showcase_seen_';
  static const String _blockPrefix = 'sc_block_';
  static const String _firstLoginKey = 'showcase_first_login_done';
  static const String _termsAcceptedKey = 'terms_accepted';
  static const String _onboardingOfferedKey = 'onboarding_offered';

  final SharedPreferences _prefs;

  ShowcaseService(this._prefs);

  // ── Per-block API ────────────────────────────────────────────────────────

  bool shouldShowBlock(ShowcaseBlock block) {
    return !(_prefs.getBool('$_blockPrefix${block.name}') ?? false);
  }

  Future<void> markBlockAsSeen(ShowcaseBlock block) async {
    await _prefs.setBool('$_blockPrefix${block.name}', true);
  }

  Future<void> markAllBlocksSeen() async {
    for (final block in ShowcaseBlock.values) {
      await _prefs.setBool('$_blockPrefix${block.name}', true);
    }
  }

  Future<void> resetAllBlocks() async {
    for (final block in ShowcaseBlock.values) {
      await _prefs.remove('$_blockPrefix${block.name}');
    }
  }

  // ── Legacy page API ──────────────────────────────────────────────────────

  bool shouldShowShowcase(ShowcasePage page) {
    return !(_prefs.getBool('$_prefix${page.name}') ?? false);
  }

  Future<void> markPageAsSeen(ShowcasePage page) async {
    await _prefs.setBool('$_prefix${page.name}', true);
  }

  Future<void> resetTutorials() async {
    for (final block in ShowcaseBlock.values) {
      await _prefs.remove('$_blockPrefix${block.name}');
    }
    for (final page in ShowcasePage.values) {
      await _prefs.remove('$_prefix${page.name}');
    }
    await _prefs.remove(_firstLoginKey);
    await resetAllTutorials();
  }

  Future<void> resetTermsAcceptance() async {
    await _prefs.remove(_termsAcceptedKey);
  }

  Future<void> resetAllShowcases() async {
    await resetTutorials();
    await resetTermsAcceptance();
  }

  Future<void> resetShowcase(ShowcasePage page) async {
    await _prefs.remove('$_prefix${page.name}');
  }

  // ── Terms & first login ──────────────────────────────────────────────────

  bool get isFirstLogin => !(_prefs.getBool(_firstLoginKey) ?? false);

  Future<void> markFirstLoginDone() async {
    await _prefs.setBool(_firstLoginKey, true);
  }

  String _scopedTermsKey(String accountScope, String revision) =>
      'terms_accepted_v2:${Uri.encodeComponent(accountScope)}:$revision';

  bool hasAcceptedTermsFor({
    required String accountScope,
    required String revision,
  }) => _prefs.containsKey(_scopedTermsKey(accountScope, revision));

  Future<void> acceptTermsFor({
    required String accountScope,
    required String revision,
  }) async {
    final saved = await _prefs.setString(
      _scopedTermsKey(accountScope, revision),
      DateTime.now().toUtc().toIso8601String(),
    );
    if (!saved) throw StateError('Terms acceptance was not saved');
  }

  bool get hasAcceptedTerms => _prefs.getBool(_termsAcceptedKey) ?? false;

  Future<void> acceptTerms() async {
    await _prefs.setBool(_termsAcceptedKey, true);
  }

  bool get hasSeenOnboardingOffer =>
      _prefs.getBool(_onboardingOfferedKey) ?? false;

  Future<void> markOnboardingOffered() async {
    await _prefs.setBool(_onboardingOfferedKey, true);
  }

  // ── Tutorial per-screen API ──────────────────────────────────────────────

  bool hasSeenTutorial(String screenKey) =>
      _prefs.getBool('tutorial_$screenKey') ?? false;

  Future<void> markTutorialSeen(String screenKey) async {
    await _prefs.setBool('tutorial_$screenKey', true);
  }

  Future<void> resetAllTutorials() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('tutorial_'));
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  // ── Tour navigation ──────────────────────────────────────────────────────

  /// Ordered list of (screenKey, route) pairs for the guided tour.
  static const _tourOrder = [
    ('home', '/'),
    ('tracks', '/tracks'),
    ('invoices', '/invoices'),
    ('photos', '/photos'),
    ('calculator', '/calculator'),
    ('search', '/search'),
    ('referral', '/referral'),
    ('tariffs', '/tariffs'),
    ('news_list', '/news'),
    ('rules', '/rules'),
    ('support', '/support'),
    ('payment_chat', '/payment-chat'),
    ('profile', '/profile'),
    ('sp_assemblies', '/sp-finance'), // последний экран тура
  ];

  /// Returns the route of the next unvisited tutorial screen after [currentKey],
  /// or null if all screens have been seen.
  String? nextTourRoute(String currentKey) {
    final idx = _tourOrder.indexWhere((e) => e.$1 == currentKey);
    if (idx == -1) return null;
    for (var i = idx + 1; i < _tourOrder.length; i++) {
      if (!hasSeenTutorial(_tourOrder[i].$1)) {
        return _tourOrder[i].$2;
      }
    }
    // Wrap-around: check screens before currentKey too
    for (var i = 0; i < idx; i++) {
      if (!hasSeenTutorial(_tourOrder[i].$1)) {
        return _tourOrder[i].$2;
      }
    }
    return null;
  }

  /// Returns true if all tour screens have been visited.
  bool isTourComplete() {
    return _tourOrder.every((e) => hasSeenTutorial(e.$1));
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final showcaseServiceProvider = Provider<ShowcaseService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ShowcaseService(prefs);
});

/// Сигнал для сброса обучения — инкрементируется при нажатии "Сбросить обучение".
class ShowcaseTutorialResetNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final showcaseTutorialResetProvider =
    NotifierProvider<ShowcaseTutorialResetNotifier, int>(
      ShowcaseTutorialResetNotifier.new,
    );

/// Реактивный провайдер: возвращает shouldShow для конкретного блока.
final showcaseBlockProvider = Provider.family<bool, ShowcaseBlock>((
  ref,
  block,
) {
  final service = ref.watch(showcaseServiceProvider);
  return service.shouldShowBlock(block);
});

// ─── Legacy providers ─────────────────────────────────────────────────────────

class ShowcaseState {
  final bool shouldShow;
  final List<GlobalKey> keys;

  const ShowcaseState({required this.shouldShow, this.keys = const []});

  ShowcaseState copyWith({bool? shouldShow, List<GlobalKey>? keys}) {
    return ShowcaseState(
      shouldShow: shouldShow ?? this.shouldShow,
      keys: keys ?? this.keys,
    );
  }
}

final showcaseProvider = Provider.family<ShowcaseState, ShowcasePage>((
  ref,
  page,
) {
  final service = ref.watch(showcaseServiceProvider);
  return ShowcaseState(shouldShow: service.shouldShowShowcase(page));
});

final showcaseNotifierProvider =
    Provider.family<_ShowcaseController, ShowcasePage>((ref, page) {
      return _ShowcaseController(ref, page);
    });

class _ShowcaseController {
  final Ref _ref;
  final ShowcasePage _page;

  _ShowcaseController(this._ref, this._page);

  bool get shouldShow =>
      _ref.read(showcaseServiceProvider).shouldShowShowcase(_page);

  Future<void> markAsSeen() async {
    await _ref.read(showcaseServiceProvider).markPageAsSeen(_page);
    _ref.invalidate(showcaseProvider(_page));
  }

  Future<void> reset() async {
    await _ref.read(showcaseServiceProvider).resetShowcase(_page);
    _ref.invalidate(showcaseProvider(_page));
  }
}

final showcaseBlockNotifierProvider =
    Provider.family<_ShowcaseBlockController, ShowcaseBlock>((ref, block) {
      return _ShowcaseBlockController(ref, block);
    });

class _ShowcaseBlockController {
  final Ref _ref;
  final ShowcaseBlock _block;

  _ShowcaseBlockController(this._ref, this._block);

  bool get shouldShow =>
      _ref.read(showcaseServiceProvider).shouldShowBlock(_block);

  Future<void> markAsSeen() async {
    await _ref.read(showcaseServiceProvider).markBlockAsSeen(_block);
    _ref.invalidate(showcaseBlockProvider(_block));
  }
}
