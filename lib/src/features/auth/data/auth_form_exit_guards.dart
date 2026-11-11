import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Route-level guards cover Back as well as GoRouter.go and shell navigation.
/// Forms register only while mounted and never retain their controllers here.
class AuthFormExitGuards {
  Future<bool> Function()? registration;
  Future<bool> Function()? profile;
}

final authFormExitGuardsProvider = Provider((ref) => AuthFormExitGuards());
