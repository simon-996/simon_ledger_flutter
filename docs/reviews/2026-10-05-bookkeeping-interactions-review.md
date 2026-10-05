# 记账交互改造复核与验证

## 最终行为

- 保存反馈统一为顶部 AppNotice，宽屏右上角。6 秒撤销、连续保存替换、记录 UUID/账户范围校验、无障碍操作提示持续显示及 Overlay 卸载取消计时器。
- CurrencyLabel 统一符号/ISO/中文名称；两币种窄屏直接切换；完整列表按代码/名称/符号搜索，取消不改变币种，输入数字保持原值。
- 手动新增、编辑和 AI 复核共用日期时间入口。快捷日期、日历、24 小时输入/iOS 滚轮暂存后一次提交。未改动的新记录保留保存时当前时间；AI DAY/TIME 精度先更新再发出一次草稿变化事件。

## 独立复核

`requesting-code-review` 只读复核指出两个 P2，均已先复现失败、修复后验证，并由复核者重新确认：

1. iOS 时间滚轮编辑后关闭再开启会恢复旧显示值，但提交新值。同步 `_date`、小时和分钟，回归覆盖 off→on 及最终提交。
2. 币种搜索在 600×360 横屏、底部键盘 inset 220 时固定标题/输入区溢出 20 像素。使用实际布局约束计算高度，整个内容进入滚动区域，回归验证滚动选择成功。

另通过失败测试修正已展开日历不响应快捷日期选择的问题：CalendarDatePicker 的 initialDate 只用于初始化，按日期改变 key 以同步选中日。

## 自动化验证

- 基线：`flutter test --reporter expanded`，419 项通过。
- 最终：`flutter test --reporter expanded --dart-define=UX_CAPTURE_DIR=D:/workplace/projects/simon-ledger/.tmp/bookkeeping-interactions`，440 项通过，退出码 0。
- `flutter analyze`：No issues found，退出码 0。
- `flutter build web --no-wasm-dry-run`：Built build/web，退出码 0。
- 逐文件 `dart format` 与 `git diff --check`。

真实中文字体截图覆盖手机/电脑日期时间、展开日历、320 px 大字号键盘、保存提示、记账/编辑/AI 复核。截图位置：`D:/workplace/projects/simon-ledger/.tmp/bookkeeping-interactions/`。

这是组件级自动化和构建验证；本轮未进行 Android/iOS 真机操作，也未推送或部署。实现保留在 `feat/ai-bookkeeping` 工作区。
