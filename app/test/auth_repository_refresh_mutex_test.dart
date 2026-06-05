import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/auth/data/auth_api.dart';
import 'package:clique_pix/features/auth/domain/auth_repository.dart';
import 'package:clique_pix/features/auth/domain/background_token_service.dart';
import 'package:clique_pix/services/token_storage_service.dart';

// ITEM A3: all main-isolate silent-refresh entry points coalesce onto ONE
// in-flight acquireTokenSilent via refreshTokenDetailed(). The acquireOverride
// seam lets us exercise the coalescing without a live SingleAccountPca (it
// short-circuits before any PCA / secure-storage call).
AuthRepository makeRepo() => AuthRepository(
      api: AuthApi(Dio()),
      tokenStorage: TokenStorageService(),
      backgroundTokenService: BackgroundTokenService(),
    );

void main() {
  group('AuthRepository.refreshTokenDetailed coalescing (A3)', () {
    test('two concurrent calls invoke the acquisition EXACTLY once', () async {
      final repo = makeRepo();
      var calls = 0;
      final gate = Completer<RefreshResult>();
      repo.acquireOverride = () {
        calls++;
        return gate.future;
      };

      final f1 = repo.refreshTokenDetailed();
      final f2 = repo.refreshTokenDetailed();
      gate.complete(const RefreshResult(success: true));
      final r1 = await f1;
      final r2 = await f2;

      expect(calls, 1, reason: 'second concurrent caller must coalesce');
      expect(r1.success, true);
      expect(r2.success, true);
    });

    test('refreshToken() (bool) coalesces with refreshTokenDetailed()', () async {
      final repo = makeRepo();
      var calls = 0;
      final gate = Completer<RefreshResult>();
      repo.acquireOverride = () {
        calls++;
        return gate.future;
      };

      final fBool = repo.refreshToken();
      final fDetailed = repo.refreshTokenDetailed();
      gate.complete(const RefreshResult(success: true));

      expect(await fBool, true);
      expect((await fDetailed).success, true);
      expect(calls, 1);
    });

    test('field clears after completion → a LATER call starts a new acquisition', () async {
      final repo = makeRepo();
      var calls = 0;
      repo.acquireOverride = () async {
        calls++;
        return const RefreshResult(success: true);
      };

      await repo.refreshTokenDetailed();
      await repo.refreshTokenDetailed();

      expect(calls, 2, reason: 'sequential (non-overlapping) calls must NOT coalesce');
    });

    test('a FAILING acquisition still clears the in-flight field', () async {
      final repo = makeRepo();
      var calls = 0;
      repo.acquireOverride = () async {
        calls++;
        return const RefreshResult(success: false, errorCode: 'AADSTS700082');
      };

      expect((await repo.refreshTokenDetailed()).success, false);
      expect((await repo.refreshTokenDetailed()).success, false);
      expect(calls, 2);
    });

    test('coalesced callers observe the SAME errorCode', () async {
      final repo = makeRepo();
      final gate = Completer<RefreshResult>();
      repo.acquireOverride = () => gate.future;

      final f1 = repo.refreshTokenDetailed();
      final f2 = repo.refreshTokenDetailed();
      gate.complete(const RefreshResult(success: false, errorCode: 'AADSTS700082'));

      expect((await f1).errorCode, 'AADSTS700082');
      expect((await f2).errorCode, 'AADSTS700082');
    });
  });
}
