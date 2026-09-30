# Ledger UI/UX Implementation Plan

> **For agentic workers:** Use the approved specification and execute tasks with isolated file ownership; use dispatching-parallel-agents for independent domains and verification-before-completion for integration.

**Goal:** Complete all approved bookkeeping, ledger, statistics, and visual UX improvements in one release.

**Architecture:** Keep existing Flutter/Material and Riverpod repositories. Share transaction controls, preserve domain semantics and global theme roles, and integrate responsive navigation in HomePage. Work in the existing `feat/ai-bookkeeping` worktree.

**Tech Stack:** Flutter, Riverpod, fl_chart, shared_preferences, existing local/remote repositories.

## Task 1: Transaction workflow (transaction_ux)

**Files:** `lib/features/transactions/presentation/widgets/bookkeeping_tab.dart`, `edit_transaction_sheet.dart`, `ai_draft_review.dart`, `transaction_form_components.dart`; corresponding tests.

- [x] Add failing behavior tests for choosing a historical date, correcting invalid amount/participants, live split summary, and save/undo.
- [x] Implement shared controls and field validation; preserve unknown-name and unknown-category confirmation.
- [x] Replace success dialog with lightweight save feedback and repository-backed undo.
- [x] Add optional navigation contracts:

```dart
final VoidCallback? onCreateLedger;
final ValueChanged<Ledger>? onOpenLedger;
```

- [x] Add direct empty-state create action and latest three transactions with view shortcut.
- [x] Run targeted transaction suites with TEMP/TMP on D; update only intentional changed expectations.

## Task 2: Ledger and statistics (ledger_statistics_ux)

**Files:** `lib/features/ledgers/presentation/screens/ledger_dashboard_page.dart`, `lib/features/statistics/presentation/widgets/statistics_tab.dart`, date helpers and corresponding tests.

- [x] Add failing tests for date-range endpoints, year-aware groups, category drilldown/back, comparison with zero previous total.
- [x] Move search/filter ahead of summaries, group transactions by day, and expose clear filters for empty results.
- [x] Add month navigation, custom date range, scope labels, daily trend and previous-period comparison.
- [x] Make category rows open matching transaction details, preserving filter and display-currency context.
- [x] Adapt available wide screen space and run targeted suites.

## Task 3: App shell and visual system (root)

**Files:** `lib/features/home/presentation/screens/home_page.dart`, `lib/core/theme/app_theme.dart`, `lib/core/widgets/app_components.dart`, `lib/features/ledgers/presentation/widgets/create_ledger_sheet.dart`, `ledger_list_tab.dart`; corresponding tests.

- [x] Test narrow bottom navigation and wide NavigationRail, plus create-from-bookkeeping return flow.
- [x] Wire callbacks and select newly created ledger via existing preference:

```dart
await LastSelectedLedgerPreference.setUuid(newLedger.uuid);
setState(() => _currentIndex = 0);
```

- [x] Normalize theme typography and numeric figures; preserve semantic colors and selected-state clarity.
- [x] Use one sheet drag handle; replace disabled CNY rate input with informative text.
- [x] Consolidate secondary ledger actions in a menu and keep name readable; expose identity details intentionally.
- [x] Respect reduced motion in shared animated components and validate interaction/keyboard layouts.

## Task 4: Integration and delivery

- [x] Review specification coverage, cross-component contracts, date arithmetic, currency formatting and undo behavior.
- [x] Run `flutter analyze` and `flutter test`; fix actual regressions and meaningful review findings.
- [x] Run `flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:18080` and inspect populated narrow/wide screens.
- [ ] Commit, fast-forward master, verify merged result and restart local web preview with healthy API.

All Flutter verification commands use `$env:TEMP='D:\workplace\projects\simon-ledger\.tmp\flutter-color-check'; $env:TMP=$env:TEMP` because C drive has insufficient free space. No package upgrades or unrelated refactors.

## 验证记录（2026-10-01）

- 全套 `flutter test --reporter expanded`：331 项通过。
- `flutter analyze --no-pub`：No issues found。
- `flutter build web --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:18080`：成功。
- 280、390、1280px 有数据布局及键盘、AI 复核截图已检查；截图存放于工作区外部临时验收目录 `.tmp/ux-review`。
- 浏览器构建预览加载成功，检查宽屏侧栏及首次创建入口。
- 独立复核发现并修复撤销的云端编号变化、上传中取消、响应丢失、删除重试、新保存/编辑同步竞态，以及宽屏键盘遮挡问题。对应回归测试通过。
- 所有新增样式继续通过 ColorScheme / AppColors 使用全局语义颜色。

分析额外设置 `LOCALAPPDATA` 到 D 盘临时目录，避开本机 C 盘 Dart 性能日志清理异常。
