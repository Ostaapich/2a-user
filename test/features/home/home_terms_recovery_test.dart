import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/client_terms_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/client_terms_snapshot.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/rule_item.dart';
import 'package:twoalogisticcabineuser/src/features/shell/application/shell_branch_provider.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false);
  void ready() =>
      state = const AuthState(isLoading: false, isLoggedIn: true, clientId: 17);
}

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: [], activeCode: null);
}

void main() {
  testWidgets(
    'home retries failed rules and waits for active branch after auth readiness',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(_Auth.new),
          clientAgentIdProvider.overrideWithValue(9),
          activeClientCodeProvider.overrideWithValue(null),
          clientCodesControllerProvider.overrideWith(_Codes.new),
          clientProfileProvider.overrideWith((_) async => null),
          clientTermsServiceProvider.overrideWithValue(
            _TermsService(() => ++calls),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.tracks);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HomeScreen())),
        ),
      );
      await tester.pumpAndSettle();
      (container.read(authProvider.notifier) as _Auth).ready();
      await tester.pumpAndSettle();
      expect(calls, 0);
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.home);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Повторить проверку правил'), findsOneWidget);
      showDialog<void>(
        context: tester.element(find.byType(HomeScreen)),
        builder: (context) => AlertDialog(
          content: const Text('User form'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close form'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.tracks);
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.home);
      await tester.pumpAndSettle();
      expect(find.text('User form'), findsOneWidget);
      expect(find.text('Соглашаюсь'), findsNothing);
      expect(calls, 1);
      await tester.tap(find.text('Close form'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Повторить проверку правил'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Соглашаюсь'), findsOneWidget);
      await tester.ensureVisible(find.text('Соглашаюсь'));
      await tester.tap(find.text('Соглашаюсь'));
      await tester.pumpAndSettle();
      expect(find.text('Соглашаюсь'), findsNothing);
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.tracks);
      container
          .read(activeShellBranchIndexProvider.notifier)
          .setIndex(ShellBranchIndex.home);
      await tester.pumpAndSettle();
      expect(find.text('Соглашаюсь'), findsNothing);
      expect(calls, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _TermsService extends ClientTermsService {
  _TermsService(this.onFetch) : super(ApiClient());
  final int Function() onFetch;
  bool accepted = false;
  @override
  Future<ClientTermsSnapshot> fetch({
    required int clientId,
    required int agentId,
  }) async {
    if (onFetch() == 1) throw StateError('503');
    return ClientTermsSnapshot(
      clientId: clientId,
      agentId: agentId,
      available: true,
      accepted: accepted,
      revision: List.filled(64, 'a').join(),
      rules: const [
        RuleItem(
          slug: '1',
          title: 'Условия',
          excerpt: '',
          content: 'Existing actual terms',
          order: 1,
        ),
      ],
    );
  }

  @override
  Future<void> accept(ClientTermsSnapshot snapshot) async {
    accepted = true;
  }
}
