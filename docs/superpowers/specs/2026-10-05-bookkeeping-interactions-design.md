# 记账交互统一设计

用户已认可本轮建议；手机优先，兼顾电脑。继续在 `feat/ai-bookkeeping` 工作区实现。

## 保存反馈

成功反馈统一使用现有 AppNotice，手机顶部安全区域，宽屏右上角。内容显示记账类型、分类、原币金额，只有一个业务操作“撤销”，默认保留 6 秒。开启无障碍导航且带操作时不自动消失。连续保存替换旧提示，撤销绑定最新提示对应的记录 UUID 和保存时账户范围；“查看流水”继续使用已有入口。错误保持输入及现有字段错误提示。

## 币种

全应用 CurrencyLabel 显示符号、ISO 代码和中文名，保留辅助国旗。美元、港币等使用 US$/HK$ 等符号。未知币种用代码兜底。

一种币种显示静态标签；两种币种在金额旁直接点选，包括窄屏。窄选项至少保留代码、符号，完整名称由无障碍标签提供。更多选项在空间充足时沿用快捷选项，否则手机底部列表、电脑紧凑对话框。列表支持名称、代码、符号搜索，点选立即返回，取消不改原值。不改变输入的数字，也不新增换算规则。

## 日期与时间

统一 TransactionDateControl，供手动新增、编辑和 AI 复核共用。一个入口显示相对日期/完整日期及 HH:mm；未指定时间的 AI 草稿显示“未指定时间”。

手机使用底部面板，电脑使用靠近入口的紧凑浮层。面板有今天、昨天、前天快捷选择及可展开的 CalendarDatePicker。保留原来的不能选择未来日期约束；修改日期保留时间和更细精度。

时间按需指定，Android/电脑直接输入 24 小时制小时、分钟，iOS 使用 Cupertino 时间滚轮。面板只有一次“完成”提交。取消、点击外部、下滑关闭均不修改原值；未修改的手动新记录仍在保存时取当前时间。AI 的 DAY/TIME 精度单独回传，不能因为更改日期而伪造精确时间。

所有内容在窄屏、大字号和键盘出现时可以滚动；完成按钮保持可达。

## 验证

基线 Flutter 419 项测试通过。新增行为测试覆盖顶部提示位置与持续时间、连续保存后撤销最新记录、符号及直接选择、日期取消/提交/非法时间、DAY 精度、手机与电脑布局。更新旧双弹窗预期，运行全部 Flutter 测试、静态分析和 Web 构建；使用组件截图检查实际布局。

## 参考

- https://github.com/jameskokoska/Cashew
- https://github.com/payam-zahedi/toastification
- https://help.realbyteapps.com/hc/en-us/articles/360042988234-How-to-add-sub-currencies
- https://api.flutter.dev/flutter/material/showTimePicker.html
- https://api.flutter.dev/flutter/cupertino/CupertinoDatePicker-class.html

采用 Flutter 官方组件和本项目主题，不新增 UI 依赖。
