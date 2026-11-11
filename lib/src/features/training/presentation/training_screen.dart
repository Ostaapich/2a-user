import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/utils/locale_text.dart';
import '../data/training_progress.dart';
import 'training_lessons.dart';
import 'training_ui.dart';

class TrainingScreen extends StatefulWidget {
  final TrainingProgressStore store;
  final double topPadding;
  final String? initialLessonId;
  final bool initialPractice;
  final VoidCallback? onStartTour;
  final VoidCallback? onStartPractice;
  final void Function(String lessonId, int step)? onShowInApp;

  const TrainingScreen({
    super.key,
    required this.store,
    this.topPadding = 0,
    this.initialLessonId,
    this.initialPractice = false,
    this.onStartTour,
    this.onStartPractice,
    this.onShowInApp,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late TrainingProgress _progress;
  final _scroll = ScrollController();
  String? _lessonId;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.store.read();
    _lessonId = widget.initialLessonId;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _save(TrainingProgress next) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    var success = false;
    try {
      success = await widget.store.save(next);
    } catch (_) {
      success = false;
    }
    if (!mounted) return false;
    setState(() {
      _saving = false;
      _saveFailed = !success;
      _progress = next;
    });
    return success;
  }

  void _scrollTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _open(TrainingLesson lesson) async {
    final step = (_progress.steps[lesson.id] ?? 0).clamp(
      0,
      lesson.steps.length - 1,
    );
    await _save(_progress.visit(lesson.id, step));
    if (!mounted) return;
    setState(() {
      _lessonId = lesson.id;
    });
    _scrollTop();
  }

  Future<void> _move(TrainingLesson lesson, int step) async {
    await _save(_progress.visit(lesson.id, step));
    if (!mounted) return;
    _scrollTop();
  }

  Future<void> _finish(
    TrainingLesson lesson,
    TrainingLessonStatus status,
  ) async {
    await _save(
      _progress.visit(
        lesson.id,
        _progress.steps[lesson.id] ?? 0,
        status: status,
      ),
    );
    if (!mounted) return;
    _scrollTop();
  }

  void _catalog() {
    setState(() {
      _lessonId = null;
    });
    _scrollTop();
  }

  String _statusText(TrainingLessonStatus? status) => switch (status) {
    null => tr(context, ru: 'Не начато', zh: '尚未开始'),
    TrainingLessonStatus.inProgress => tr(context, ru: 'В процессе', zh: '学习中'),
    TrainingLessonStatus.read => tr(context, ru: 'Прочитано', zh: '已阅读'),
    TrainingLessonStatus.skipped => tr(context, ru: 'Пропущено', zh: '已跳过'),
    TrainingLessonStatus.practiced => tr(
      context,
      ru: 'Упражнение выполнено',
      zh: '练习已完成',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final lessons = trainingLessons(context);
    final index = lessons.indexWhere((lesson) => lesson.id == _lessonId);
    final lesson = index < 0 ? null : lessons[index];
    return Theme(
      data: TrainingUi.theme(context),
      child: DefaultTextStyle(
        style: TrainingUi.body,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppLayout.contentMaxWidth(context),
            ),
            child: PopScope(
              canPop: lesson == null && !_saving,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && !_saving) _catalog();
              },
              child: AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    widget.topPadding + 16,
                    16,
                    32 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    if (_saving) const LinearProgressIndicator(),
                    if (_saveFailed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          tr(
                            context,
                            ru: 'Прогресс пока сохранён только в этом окне. Можно продолжать чтение и повторить сохранение.',
                            zh: '进度暂时仅保存在当前页面中。您可以继续阅读并重试保存。',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_saveFailed)
                      TextButton.icon(
                        key: const Key('training-retry-save'),
                        onPressed: () => _save(_progress),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          tr(context, ru: 'Повторить сохранение', zh: '重新保存'),
                        ),
                      ),
                    if (lesson == null)
                      ..._buildCatalog(lessons)
                    else
                      ..._buildLesson(lesson, index, lessons),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCatalog(List<TrainingLesson> lessons) {
    final completed = lessons.where((lesson) {
      final status = _progress.statuses[lesson.id];
      return status == TrainingLessonStatus.read ||
          status == TrainingLessonStatus.practiced;
    }).length;
    final resumeIndex = lessons.indexWhere(
      (lesson) => lesson.id == _progress.lastLessonId,
    );
    return [
      _panel([
        Icon(Icons.school_rounded, size: 36, color: context.brandPrimary),
        const SizedBox(height: 12),
        Text(
          tr(context, ru: 'Обучение и возможности', zh: '学习与功能介绍'),
          style: TrainingUi.title.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            ru:
                'Познакомьтесь со всем приложением или выберите нужную тему. '
                'Отправку на сборку можно попробовать на учебных посылках.',
            zh: '了解整个应用，或选择所需主题。您可以使用示例包裹练习创建集运包裹。',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr(
            context,
            ru: 'Изучено $completed из ${lessons.length} тем',
            zh: '已学习 $completed / ${lessons.length} 个主题',
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: completed / lessons.length),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('training-continue'),
          onPressed:
              widget.onStartTour ??
              () => _open(lessons[resumeIndex < 0 ? 0 : resumeIndex]),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            tr(
              context,
              ru: resumeIndex < 0 ? 'Пройти экскурсию' : 'Продолжить экскурсию',
              zh: resumeIndex < 0 ? '开始导览' : '继续导览',
            ),
          ),
        ),
        if (widget.onStartTour != null)
          TextButton(
            onPressed: () => _open(lessons[resumeIndex < 0 ? 0 : resumeIndex]),
            child: Text(tr(context, ru: 'Читать инструкции', zh: '阅读操作指南')),
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            ru: 'Прогресс сохраняется для вашего аккаунта на этом устройстве.',
            zh: '进度会保存在此设备上，并与您的账户关联。',
          ),
          style: TrainingUi.caption,
        ),
      ]),
      const SizedBox(height: 20),
      Text(
        tr(context, ru: 'Все темы', zh: '所有主题'),
        style: TrainingUi.title,
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < lessons.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DecoratedBox(
            decoration: TrainingUi.cardDecoration,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: ListTile(
                titleTextStyle: TrainingUi.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                subtitleTextStyle: TrainingUi.caption,
                key: ValueKey('training-lesson-${lessons[i].id}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Icon(lessons[i].icon, color: context.brandPrimary),
                title: Text('${i + 1}. ${lessons[i].title}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${lessons[i].summary}\n'
                    '${_statusText(_progress.statuses[lessons[i].id])}',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(lessons[i]),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildLesson(
    TrainingLesson lesson,
    int index,
    List<TrainingLesson> lessons,
  ) {
    final stepIndex = (_progress.steps[lesson.id] ?? 0).clamp(
      0,
      lesson.steps.length - 1,
    );
    final step = lesson.steps[stepIndex];
    final isLast = stepIndex == lesson.steps.length - 1;
    final status = _progress.statuses[lesson.id];
    final finished =
        status == TrainingLessonStatus.read ||
        status == TrainingLessonStatus.practiced;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('training-catalog'),
          onPressed: _catalog,
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(tr(context, ru: 'Все темы', zh: '所有主题')),
        ),
      ),
      Text(lesson.title, style: TrainingUi.title.copyWith(fontSize: 22)),
      const SizedBox(height: 8),
      Text(_statusText(status), style: TrainingUi.caption),
      const SizedBox(height: 16),
      if (lesson.id == 'assembly' && widget.onStartPractice != null) ...[
        FilledButton.icon(
          key: const Key('training-practice'),
          onPressed: widget.onStartPractice,
          icon: const Icon(Icons.inventory_2_rounded),
          label: Text(
            tr(context, ru: 'Попробовать учебную сборку', zh: '练习创建集运包裹'),
          ),
        ),
        const SizedBox(height: 12),
      ] else if (widget.onShowInApp != null) ...[
        FilledButton.icon(
          key: const Key('training-show-in-app'),
          onPressed: () => widget.onShowInApp!(lesson.id, stepIndex),
          icon: const Icon(Icons.touch_app_rounded),
          label: Text(tr(context, ru: 'Показать в приложении', zh: '在应用中演示')),
        ),
        const SizedBox(height: 12),
      ],
      _panel([
        Text(
          tr(
            context,
            ru: 'Шаг ${stepIndex + 1} из ${lesson.steps.length}',
            zh: '第 ${stepIndex + 1} 步，共 ${lesson.steps.length} 步',
          ),
          style: TrainingUi.caption.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(step.title, style: TrainingUi.title),
        const SizedBox(height: 12),
        Text(step.body),
        const SizedBox(height: 16),
        Text(
          tr(context, ru: 'Что сделать', zh: '操作提示'),
          style: TrainingUi.body.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(step.action),
      ]),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (stepIndex > 0)
            OutlinedButton(
              key: const Key('training-previous'),
              onPressed: () => _move(lesson, stepIndex - 1),
              child: Text(tr(context, ru: 'Назад', zh: '上一步')),
            ),
          if (!isLast)
            FilledButton(
              key: const Key('training-next'),
              onPressed: () => _move(lesson, stepIndex + 1),
              child: Text(tr(context, ru: 'Далее', zh: '下一步')),
            )
          else if (!finished)
            FilledButton(
              key: const Key('training-mark-read'),
              onPressed: () => _finish(lesson, TrainingLessonStatus.read),
              child: Text(tr(context, ru: 'Прочитано', zh: '已阅读')),
            ),
          TextButton(
            key: const Key('training-skip'),
            onPressed: () async {
              await _finish(lesson, TrainingLessonStatus.skipped);
              if (!mounted || _saveFailed) return;
              if (index + 1 < lessons.length) {
                await _open(lessons[index + 1]);
              } else {
                _catalog();
              }
            },
            child: Text(tr(context, ru: 'Пропустить тему', zh: '跳过此主题')),
          ),
        ],
      ),
      if (finished && isLast) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('training-next-lesson'),
          onPressed: index + 1 < lessons.length
              ? () => _open(lessons[index + 1])
              : _catalog,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            tr(
              context,
              ru: index + 1 < lessons.length
                  ? 'Следующая тема'
                  : 'К оглавлению',
              zh: index + 1 < lessons.length ? '下一个主题' : '返回目录',
            ),
          ),
        ),
      ],
    ];
  }

  Widget _panel(List<Widget> children) => Container(
    padding: const EdgeInsets.all(20),
    decoration: TrainingUi.cardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
