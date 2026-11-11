// Native, network-free acceptance of the actual shared keyboard components.
// Build with --target=test/native/keyboard_acceptance.dart; never a release entry.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

final _frameworkErrors = <String>[];

void main() {
  FlutterError.onError = (details) {
    _frameworkErrors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  runApp(
    MaterialApp(
      builder: (_, child) => AppKeyboardDismissRegion(child: child!),
      home: const NativeKeyboardAcceptance(),
    ),
  );
}

class NativeKeyboardAcceptance extends StatefulWidget {
  const NativeKeyboardAcceptance({super.key});
  @override
  State<NativeKeyboardAcceptance> createState() => _AcceptanceState();
}

class _AcceptanceState extends State<NativeKeyboardAcceptance> {
  final _focus = FocusNode();
  final _controller = TextEditingController(text: '123.45');
  final _field = GlobalKey();
  final _outside = GlobalKey();
  String _result = 'Native keyboard acceptance: preparing';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _waitFor(bool Function() predicate) async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) throw StateError('acceptance disposed');
      if (predicate()) return;
    }
    throw StateError('native keyboard state timed out');
  }

  Future<void> _run() async {
    final evidence = <String, dynamic>{
      'platform': Theme.of(context).platform.name,
    };
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      unawaited(
        showBlurredModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SizedBox(
            height: 900,
            child: Column(
              children: [
                const SizedBox(
                  height: 32,
                  child: Center(child: Text('Keyboard acceptance')),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 480),
                      TextField(
                        key: _field,
                        focusNode: _focus,
                        controller: _controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Native numeric field',
                        ),
                      ),
                      const SizedBox(height: 160),
                    ],
                  ),
                ),
                ColoredBox(
                  key: _outside,
                  color: Colors.white,
                  child: const SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: Center(child: Text('Tap outside input')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _focus.requestFocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await _waitFor(() => View.of(context).viewInsets.bottom > 0);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final view = View.of(context);
      final keyboardTop =
          (view.physicalSize.height - view.viewInsets.bottom) /
          view.devicePixelRatio;
      final box = _field.currentContext!.findRenderObject()! as RenderBox;
      final fieldBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      evidence.addAll({
        'keyboardInset': view.viewInsets.bottom / view.devicePixelRatio,
        'keyboardTop': keyboardTop,
        'fieldBottom': fieldBottom,
        'fieldVisible': fieldBottom <= keyboardTop + 1,
      });
      if (fieldBottom > keyboardTop + 1) throw StateError('field obscured');
      // Fixture-only capture window for native screenshot evidence.
      // ignore: avoid_print
      print('KEYBOARD_VISIBLE ${jsonEncode(evidence)}');
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      final outside = _outside.currentContext!.findRenderObject()! as RenderBox;
      final position = outside.localToGlobal(outside.size.center(Offset.zero));
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(
          pointer: 77,
          position: position,
          kind: PointerDeviceKind.touch,
        ),
      );
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(
          pointer: 77,
          position: position,
          kind: PointerDeviceKind.touch,
        ),
      );
      await _waitFor(() => View.of(context).viewInsets.bottom == 0);
      if (_frameworkErrors.isNotEmpty) {
        throw StateError(
          'Flutter rendering errors: ${_frameworkErrors.join('; ')}',
        );
      }
      if (_focus.hasFocus || _controller.text != '123.45') {
        throw StateError('touch dismissal or text retention failed');
      }
      evidence.addAll({
        'touchOutsideDismissed': !_focus.hasFocus,
        'textPreserved': _controller.text == '123.45',
        'passed': true,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (_frameworkErrors.isNotEmpty) {
        throw StateError(
          'Flutter rendering errors: ${_frameworkErrors.join('; ')}',
        );
      }
      setState(() => _result = 'PASS native keyboard\n${jsonEncode(evidence)}');
    } catch (error) {
      evidence.addAll({'passed': false, 'error': error.toString()});
      if (mounted) {
        setState(
          () => _result = 'FAIL native keyboard\n${jsonEncode(evidence)}',
        );
      }
    }
    // Contains fixture values only, never production data.
    // ignore: avoid_print
    print('KEYBOARD_ACCEPTANCE ${jsonEncode(evidence)}');
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_result)),
      ),
    ),
  );
}
