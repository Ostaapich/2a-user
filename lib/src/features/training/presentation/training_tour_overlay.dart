import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../data/training_tour_controller.dart';
import 'training_target.dart';
import 'training_modal_ownership.dart';
import 'training_tour_steps.dart';
import 'training_ui.dart';

enum TrainingServiceAccess { available, checking, unavailable, failed }

/// Spotlight with delayed, explicitly registered navigation actions.
/// User decisions and business submissions are never inferred or auto-clicked.
class TrainingTourOverlay extends StatefulWidget {
  final Widget child;
  final TrainingTourController controller;
  final TrainingTargetRegistry registry;
  final TrainingModalOwnership? modalOwnership;
  final TrainingTourStep step;
  final TrainingServiceAccess access;
  final String currentPath;
  final ValueChanged<String> navigate;
  final VoidCallback onExit;
  final VoidCallback onPractice;
  final VoidCallback onRetryAccess;
  final bool guidedPractice;
  final bool advanceRequested;

  const TrainingTourOverlay({
    super.key,
    required this.child,
    required this.controller,
    required this.registry,
    this.modalOwnership,
    required this.step,
    required this.access,
    required this.currentPath,
    required this.navigate,
    required this.onExit,
    required this.onPractice,
    required this.onRetryAccess,
    this.guidedPractice = false,
    this.advanceRequested = false,
  });

  @override
  State<TrainingTourOverlay> createState() => _TrainingTourOverlayState();
}

class _TrainingTourOverlayState extends State<TrainingTourOverlay> {
  final _surfaceKey = GlobalKey();
  final _coachScroll = ScrollController();
  Timer? _timer;
  Timer? _automaticTimer;
  String? _automaticTargetId;
  BuildContext? _automaticContext;
  Rect? _automaticRect;
  final Map<String, int> _automaticAttempts = {};
  Rect? _target;
  BuildContext? _lastTargetContext;
  TrainingTourPreparation? _preparation;
  bool _collapsed = false;
  bool _previousWindowBlocked = false;
  bool _scrolled = false;
  bool _waitExpired = false;
  bool _targetSeen = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _prepareStep();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _locate(),
    );
  }

  @override
  void didUpdateWidget(TrainingTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.id != widget.step.id ||
        oldWidget.access != widget.access) {
      _prepareStep();
    } else if (oldWidget.currentPath != widget.currentPath) {
      _cancelAutomatic();
      unawaited(widget.modalOwnership?.closeOwned());
      _target = null;
      _lastTargetContext = null;
      _preparation = null;
      _scrolled = false;
      _waitExpired = false;
      _ticks = 0;
    }
  }

  void _prepareStep() {
    _cancelAutomatic();
    _automaticAttempts.clear();
    _target = null;
    _lastTargetContext = null;
    _preparation = null;
    _scrolled = false;
    _waitExpired = false;
    _ticks = 0;
    _targetSeen = false;
    _collapsed = false;
    final id = widget.step.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final closed = await widget.modalOwnership?.closeOwned() ?? true;
      if (!mounted || widget.step.id != id || widget.controller.complete) {
        return;
      }
      setState(() => _previousWindowBlocked = !closed);
      if (!closed) return;
      if (_coachScroll.hasClients) _coachScroll.jumpTo(0);
      if (widget.access == TrainingServiceAccess.available &&
          !widget.step.matchesPath(widget.currentPath)) {
        widget.navigate(widget.step.route);
      }
      _locate();
    });
  }

  bool get _onRoute => widget.step.matchesPath(widget.currentPath);

  void _missingTarget() {
    _cancelAutomatic(rebuild: true);
    _ticks++;
    if (_target != null ||
        _preparation != null ||
        (!_waitExpired && _ticks >= 8)) {
      setState(() {
        _target = null;
        _preparation = null;
        _waitExpired = _ticks >= 8;
      });
    }
  }

  void _locate() {
    if (!mounted || widget.controller.currentId != widget.step.id) return;
    if (_previousWindowBlocked &&
        !(widget.modalOwnership?.hasOwnedActive ?? false)) {
      setState(() => _previousWindowBlocked = false);
      if (!_onRoute) widget.navigate(widget.step.route);
    }
    if (!widget.controller.active ||
        !_onRoute ||
        widget.access != TrainingServiceAccess.available ||
        widget.controller.complete) {
      _cancelAutomatic(rebuild: true);
      if (_target != null) {
        setState(() => _target = null);
      }
      return;
    }
    if (_previousWindowBlocked) {
      if (widget.modalOwnership?.hasOwnedActive ?? false) return;
      setState(() => _previousWindowBlocked = false);
      if (!_onRoute) widget.navigate(widget.step.route);
    }
    final advanceTarget = widget.step.advanceTargetId;
    if (widget.advanceRequested ||
        (advanceTarget != null &&
            widget.registry.contextFor(advanceTarget) != null)) {
      widget.controller.next();
      return;
    }
    var targetContext = widget.step.readyTargetId == null
        ? null
        : widget.registry.contextFor(widget.step.readyTargetId!);
    targetContext ??= widget.registry.contextFor(widget.step.targetId);
    TrainingTourPreparation? preparation;
    if (targetContext == null) {
      for (final candidate in widget.step.preparations) {
        targetContext = widget.registry.contextFor(candidate.targetId);
        if (targetContext != null) {
          preparation = candidate;
          break;
        }
      }
    }
    if (targetContext == null) {
      _lastTargetContext = null;
      _scrolled = false;
      _missingTarget();
      return;
    }
    if (_lastTargetContext != targetContext) {
      _lastTargetContext = targetContext;
      _scrolled = false;
    }
    if (!_scrolled) {
      _scrolled = true;
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.15,
          duration: const Duration(milliseconds: 220),
        ),
      );
    }
    final render = targetContext.findRenderObject();
    final surface = _surfaceKey.currentContext?.findRenderObject();
    if (render == null || surface is! RenderBox || !surface.hasSize) {
      _missingTarget();
      return;
    }
    Rect global;
    if (render is RenderBox) {
      if (!render.hasSize) {
        _missingTarget();
        return;
      }
      global = render.localToGlobal(Offset.zero) & render.size;
    } else {
      global = MatrixUtils.transformRect(
        render.getTransformTo(null),
        render.paintBounds,
      );
    }
    if (!global.isFinite || global.isEmpty) {
      _missingTarget();
      return;
    }
    final local = global.shift(-surface.localToGlobal(Offset.zero));
    final clipped = local.intersect(Offset.zero & surface.size);
    if (clipped.isEmpty || clipped.width <= 4 || clipped.height <= 4) {
      _missingTarget();
      return;
    }
    final next = clipped.deflate(2);
    _ticks = 0;
    if (_preparation != preparation && _coachScroll.hasClients) {
      _coachScroll.jumpTo(0);
    }
    if (_target != next ||
        _waitExpired ||
        _preparation != preparation ||
        (!_targetSeen && preparation == null)) {
      setState(() {
        _target = next;
        _preparation = preparation;
        _waitExpired = false;
        if (preparation == null) _targetSeen = true;
      });
    }
    _scheduleAutomatic(preparation, targetContext, next);
  }

  void _cancelAutomatic({bool rebuild = false}) {
    final pending = _automaticTargetId != null;
    _automaticTimer?.cancel();
    _automaticTimer = null;
    _automaticTargetId = null;
    _automaticContext = null;
    _automaticRect = null;
    if (pending && rebuild && mounted) setState(() {});
  }

  void _scheduleAutomatic(
    TrainingTourPreparation? preparation,
    BuildContext targetContext,
    Rect rect,
  ) {
    final id = preparation?.targetId ?? widget.step.targetId;
    final limit = preparation?.maxAutomaticActivations ?? 1;
    final allowed =
        !widget.guidedPractice &&
        !_collapsed &&
        (preparation != null
            ? !preparation.blocked
            : widget.step.autoActivateTarget) &&
        (_automaticAttempts[id] ?? 0) < limit &&
        widget.registry.activationFor(id, targetContext) != null;
    if (!allowed) {
      _cancelAutomatic(rebuild: true);
      return;
    }
    if (_automaticTargetId == id &&
        identical(_automaticContext, targetContext) &&
        _automaticRect == rect) {
      return;
    }
    _cancelAutomatic();
    final stepId = widget.step.id;
    setState(() {
      _automaticTargetId = id;
      _automaticContext = targetContext;
      _automaticRect = rect;
    });
    // Let users see which control is about to be used. Moving/hidden targets
    // restart/cancel the timer; callbacks never use stale screen coordinates.
    _automaticTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _cancelAutomatic(rebuild: true);
      if (!widget.controller.active ||
          widget.controller.complete ||
          widget.controller.currentId != stepId ||
          widget.step.id != stepId ||
          !_onRoute ||
          _collapsed ||
          widget.guidedPractice ||
          widget.access != TrainingServiceAccess.available) {
        return;
      }
      final action = widget.registry.activationFor(id, targetContext);
      if (action == null) return;
      _automaticAttempts[id] = (_automaticAttempts[id] ?? 0) + 1;
      final ownership = widget.modalOwnership;
      if (ownership == null) {
        action();
      } else {
        ownership.runOwned(action);
      }
    });
  }

  @override
  void dispose() {
    _cancelAutomatic();
    _timer?.cancel();
    _coachScroll.dispose();
    // Defer Navigator operations until the tree has finished this transition.
    final ownership = widget.modalOwnership;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ownership?.closeOwned());
    });
    super.dispose();
  }

  String? _notice() {
    if (_previousWindowBlocked) {
      return tr(
        context,
        ru: 'Закройте открытое окно предыдущего шага, чтобы продолжить экскурсию. Несохранённая форма не закрывается автоматически.',
        zh: '请先关闭上一步打开的窗口再继续导览。未保存的表单不会被自动关闭。',
      );
    }
    if (widget.access == TrainingServiceAccess.checking) {
      return tr(
        context,
        ru: 'Проверяем доступность раздела…',
        zh: '正在检查此功能是否可用…',
      );
    }
    if (widget.access == TrainingServiceAccess.unavailable) {
      return tr(
        context,
        ru: 'Сейчас этот сервис недоступен вашему кабинету. Ознакомьтесь с возможностью и продолжите экскурсию; доступ можно уточнить у менеджера.',
        zh: '您的账户目前无法使用此服务。您可以了解功能后继续导览，或向客服咨询开通条件。',
      );
    }
    if (widget.access == TrainingServiceAccess.failed) {
      return tr(
        context,
        ru: 'Не удалось проверить доступность. Повторите проверку или пропустите шаг.',
        zh: '无法检查此功能是否可用。请重试或跳过此步骤。',
      );
    }
    if (!_onRoute) {
      return tr(
        context,
        ru: 'Вы открыли другой экран. Можно вернуться к этому шагу или продолжить экскурсию.',
        zh: '您已打开其他页面。可返回此步骤或继续导览。',
      );
    }
    if (_automaticTargetId != null) {
      return tr(
        context,
        ru: 'Сейчас нажмём выделенный элемент автоматически. Можно нажать и самостоятельно.',
        zh: '即将自动点击高亮控件，您也可以自行点击。',
      );
    }
    if (_target == null) {
      return tr(
        context,
        ru: _waitExpired
            ? 'Нужный элемент пока не показан: дождитесь загрузки, откройте указанную карточку или закройте форму предыдущего шага. Если данных ещё нет, шаг можно пропустить.'
            : 'Ищем нужный элемент на экране…',
        zh: _waitExpired
            ? '所需控件尚未显示。请等待加载、打开提示中的详情，或关闭上一步的表单。暂无数据时可跳过此步骤。'
            : '正在定位页面控件…',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height =
        media.size.height - media.padding.vertical - media.viewInsets.bottom;
    final safeTop = media.padding.top + 12;
    final safeBottom =
        media.size.height - media.padding.bottom - media.viewInsets.bottom - 12;
    final above = _target == null
        ? 0.0
        : (_target!.top - safeTop - 12).clamp(0.0, height);
    final below = _target == null
        ? 0.0
        : (safeBottom - _target!.bottom - 12).clamp(0.0, height);
    final atTop = _target != null && above > below;
    final available = _target == null || _collapsed
        ? height * 0.48
        : (atTop ? above : below);
    final coachHeight = available.clamp(96.0, 440.0);
    final completed = widget.controller.complete;
    final notice = completed ? null : _notice();
    final preparing = _preparation != null;
    final waiting = !_targetSeen && !preparing;
    final canContinue =
        _targetSeen &&
        _automaticTargetId == null &&
        _onRoute &&
        widget.access == TrainingServiceAccess.available;
    return Stack(
      key: _surfaceKey,
      children: [
        widget.child,
        if (_target != null && !completed && !_collapsed)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('tour-spotlight'),
                painter: _TrainingSpotlightPainter(
                  _target!,
                  context.brandPrimary,
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          top: atTop && !_collapsed ? media.padding.top + 12 : null,
          bottom: atTop && !_collapsed
              ? null
              : media.padding.bottom + media.viewInsets.bottom + 12,
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: coachHeight,
              ),
              child: DecoratedBox(
                decoration: TrainingUi.cardDecoration,
                child: Theme(
                  data: TrainingUi.theme(context),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: DefaultTextStyle(
                      style: TrainingUi.body,
                      child: SingleChildScrollView(
                        key: const Key('training-coach-card'),
                        controller: _coachScroll,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: context.brandPrimary.withValues(
                                      alpha: 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    completed
                                        ? Icons.check_rounded
                                        : Icons.school_rounded,
                                    color: context.brandPrimary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    completed
                                        ? tr(
                                            context,
                                            ru: widget.guidedPractice
                                                ? 'Практика завершена'
                                                : 'Экскурсия завершена',
                                            zh: '导览已完成',
                                          )
                                        : tr(
                                            context,
                                            ru: '${widget.guidedPractice ? 'Учебный пример' : 'Экскурсия'} · ${widget.controller.index + 1}/${widget.controller.length}',
                                            zh: '导览 · ${widget.controller.index + 1}/${widget.controller.length}',
                                          ),
                                    style: TrainingUi.caption.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const Key('tour-collapse'),
                                  tooltip: tr(
                                    context,
                                    ru: _collapsed
                                        ? 'Развернуть подсказку'
                                        : 'Свернуть подсказку',
                                    zh: _collapsed ? '展开提示' : '收起提示',
                                  ),
                                  onPressed: () =>
                                      setState(() => _collapsed = !_collapsed),
                                  icon: Icon(
                                    _collapsed
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  key: const Key('tour-exit'),
                                  tooltip: tr(
                                    context,
                                    ru: 'Выйти из экскурсии',
                                    zh: '退出导览',
                                  ),
                                  onPressed: widget.onExit,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            if (!_collapsed) ...[
                              const SizedBox(height: 14),
                              Semantics(
                                header: true,
                                liveRegion: true,
                                child: Text(
                                  completed
                                      ? tr(
                                          context,
                                          ru: widget.guidedPractice
                                              ? 'Вы создали учебную сборку'
                                              : 'Теперь возможности легче найти',
                                          zh: widget.guidedPractice
                                              ? '您已创建练习集运单'
                                              : '现在更容易找到所需功能了',
                                        )
                                      : preparing
                                      ? _preparation!.title ??
                                            tr(
                                              context,
                                              ru: _automaticTargetId != null
                                                  ? 'Открываем нужный элемент'
                                                  : 'Сначала откройте нужный элемент',
                                              zh: _automaticTargetId != null
                                                  ? '正在打开所需控件'
                                                  : '请先打开所需控件',
                                            )
                                      : waiting
                                      ? tr(
                                          context,
                                          ru: 'Подготовка шага',
                                          zh: '准备步骤',
                                        )
                                      : widget.step.title,
                                  key: const Key('tour-title'),
                                  style: TrainingUi.title,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                completed
                                    ? tr(
                                        context,
                                        ru: widget.guidedPractice
                                            ? 'Вы прошли настоящую форму: выбрали треки, тариф, параметры и упаковку, проверили данные и нашли результат в сборках. Данные этого примера локальные, заявка на склад не отправлена.'
                                            : 'Можно вернуться к любой теме в разделе «Обучение». Просмотр экскурсии не создаёт заявки и не подтверждает выполнение операций.',
                                        zh: widget.guidedPractice
                                            ? '您已通过实际表单选择运单、运价、参数和包装，核对信息并查看集运结果。本次使用本地示例数据，未向仓库提交申请。'
                                            : '您可以随时在“学习”中重新查看各主题。观看导览不会创建申请，也不代表已完成实际操作。',
                                      )
                                    : preparing && _preparation!.blocked
                                    ? tr(
                                        context,
                                        ru: 'Сейчас этот элемент недоступен. Условия показаны на экране; шаг можно пропустить и вернуться к нему позже.',
                                        zh: '此控件暂不可用，条件已显示在页面中。可跳过并稍后返回。',
                                      )
                                    : preparing
                                    ? tr(
                                        context,
                                        ru: _automaticTargetId != null
                                            ? 'Чтобы показать «${widget.step.title}», сейчас автоматически нажмём выделенный элемент.'
                                            : 'Чтобы посмотреть «${widget.step.title}», выполните действие ниже. Затем подсказка покажет нужный элемент.',
                                        zh: _automaticTargetId != null
                                            ? '即将自动点击高亮控件，以显示“${widget.step.title}”。'
                                            : '要查看“${widget.step.title}”，请完成以下操作。提示将在打开的窗口中继续。',
                                      )
                                    : waiting
                                    ? widget.step.missingMessage ??
                                          tr(
                                            context,
                                            ru: 'Для шага «${widget.step.title}» сначала должен появиться нужный элемент. Дождитесь загрузки или откройте его по подсказке.',
                                            zh: '查看“${widget.step.title}”前需要先显示对应控件。请等待加载或按提示打开。',
                                          )
                                    : widget.step.body,
                              ),
                              if (!completed) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.035,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    _preparation?.instruction ??
                                        (waiting
                                            ? tr(
                                                context,
                                                ru: 'Продолжение станет доступно после показа элемента. Можно явно пропустить этот шаг и вернуться к нему позже.',
                                                zh: '显示控件后即可继续。也可主动跳过此步骤，稍后再查看。',
                                              )
                                            : widget.step.action),
                                    key: const Key('tour-action'),
                                    style: TrainingUi.body.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                              if (notice != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  notice,
                                  key: const Key('tour-notice'),
                                  style: TrainingUi.caption,
                                ),
                              ],
                              if (widget.controller.saveFailed)
                                TextButton(
                                  onPressed: widget.controller.retrySave,
                                  child: Text(
                                    tr(
                                      context,
                                      ru: 'Прогресс не сохранён. Повторить',
                                      zh: '进度未保存，重试',
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (completed)
                                    FilledButton(
                                      onPressed: widget.onExit,
                                      child: Text(
                                        tr(
                                          context,
                                          ru: 'К обучению',
                                          zh: '返回学习',
                                        ),
                                      ),
                                    )
                                  else ...[
                                    if (widget.controller.index > 0 &&
                                        !widget.guidedPractice)
                                      OutlinedButton(
                                        key: const Key('tour-previous'),
                                        onPressed: widget.controller.previous,
                                        child: Text(
                                          tr(context, ru: 'Назад', zh: '上一步'),
                                        ),
                                      ),
                                    if (!widget.step.waitForAction)
                                      FilledButton(
                                        key: const Key('tour-next'),
                                        onPressed: canContinue
                                            ? widget.controller.next
                                            : null,
                                        child: Text(
                                          tr(context, ru: 'Далее', zh: '下一步'),
                                        ),
                                      ),
                                    if (!widget.guidedPractice)
                                      TextButton(
                                        key: const Key('tour-skip'),
                                        onPressed: () =>
                                            widget.controller.next(skip: true),
                                        child: Text(
                                          tr(
                                            context,
                                            ru: 'Пропустить',
                                            zh: '跳过',
                                          ),
                                        ),
                                      ),
                                    if (widget.access ==
                                            TrainingServiceAccess.available &&
                                        !_onRoute)
                                      TextButton(
                                        onPressed: () =>
                                            widget.navigate(widget.step.route),
                                        child: Text(
                                          tr(
                                            context,
                                            ru: 'Вернуться к шагу',
                                            zh: '返回此步骤',
                                          ),
                                        ),
                                      ),
                                    if (_waitExpired &&
                                        _onRoute &&
                                        widget.access ==
                                            TrainingServiceAccess.available)
                                      TextButton(
                                        key: const Key('tour-reveal'),
                                        onPressed: () {
                                          _scrolled = false;
                                          _locate();
                                        },
                                        child: Text(
                                          tr(
                                            context,
                                            ru: 'Показать элемент',
                                            zh: '显示控件',
                                          ),
                                        ),
                                      ),
                                    if (widget.access ==
                                            TrainingServiceAccess.failed ||
                                        widget.access ==
                                            TrainingServiceAccess.checking)
                                      TextButton(
                                        onPressed: widget.onRetryAccess,
                                        child: Text(
                                          tr(
                                            context,
                                            ru: 'Повторить проверку',
                                            zh: '重新检查',
                                          ),
                                        ),
                                      ),
                                    if (widget.step.lessonId == 'assembly')
                                      TextButton(
                                        key: const Key('tour-practice'),
                                        onPressed: widget.onPractice,
                                        child: Text(
                                          tr(
                                            context,
                                            ru: 'Учебная сборка',
                                            zh: '集运练习',
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrainingSpotlightPainter extends CustomPainter {
  final Rect target;
  final Color color;

  _TrainingSpotlightPainter(this.target, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Keep both strokes outside the control, including small status labels.
    // The measured target is inset by 2px; +8px leaves a 2px clear gap
    // between the real content and the inner edge of the 8px outer stroke.
    final cutout = RRect.fromRectAndRadius(
      target.inflate(8),
      const Radius.circular(12),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.46),
    );
    // The white outer edge separates the focus ring from any page background.
    canvas.drawRRect(
      cutout,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    // Light agent colors still need a clearly visible edge against white cards.
    final outline = TrainingUi.contrastingAccent(color);
    canvas.drawRRect(
      cutout,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_TrainingSpotlightPainter oldDelegate) =>
      target != oldDelegate.target || color != oldDelegate.color;
}
