# 手机各界面滑动开销复核

## 范围与结论边界

用户澄清卡顿发生在手机各个界面，因此继续检查共享页面容器、卡片绘制和首页数据加载。本轮以 `eeb1a2e` 为基础，保留上一轮拖动取消按压缩放、滚动结束入场动画的修复。

当前未连接 Android 或 iOS 真机；用户的安装版/手机版网页、机型和运行模式尚未提供。此次结论来自代码复核、绘制与构建次数测试及功能回归，不代表真机帧率已经达到 60/120 FPS，也不能证明所有机型上的卡顿已消失。

## 检查结果

| 区域 | 现状与本轮处理 |
| --- | --- |
| Android 渲染配置 | 已开启硬件加速和 Impeller，没有把渲染引擎开关作为未经测量的修复 |
| 首页标签页 | 原先进入记账页也会挂载账本和统计子树；改为首次访问时挂载，访问后保留状态 |
| 首页全账本汇总 | 原先在 HomePage 根部订阅，初始记账也读取所有账本流水并汇总；移到首次访问时挂载的账本页 Consumer |
| 记账及编辑表单 | SingleChildScrollView 中的静止卡片会随滚动重复记录绘制；共享 AppSectionCard 增加重绘边界 |
| 账本列表 | 已使用 ReorderableListView.builder 惰性构建；保留该结构 |
| 流水与统计列表 | 已使用 SliverList.builder、CustomScrollView；保留惰性构建，共享卡片缓存同时覆盖统计图表内容 |
| 账户及附属面板 | 保留既有 ListView/滚动结构，使用共享卡片的区域获得相同的重绘隔离 |

## 可复现的工作次数变化

在 390×844 的 widget 测试视口中，把 5 张真实 AppSectionCard 放入 SingleChildScrollView，内容保持不变，滚动 12 个测试帧：

| 指标 | 修复前 | 修复后 |
| --- | --- | --- |
| 每张卡片内容的 paint 调用次数 | 12 | 0 |
| 5 张卡片内容的 paint 调用总数 | 60 | 0 |
| 首页初始 index=0 时的标签子树构建 | `[1, 1, 1]` | `[1, 0, 0]` |
| 初始记账时全账本汇总 provider 的 build 次数 | 1 | 0 |

绘制次数下降意味着减少重复记录静止内容的工作，不能直接换算为 GPU 帧耗时或 FPS。金额变化后相应卡片仍会重新绘制，其他静止卡片不重新绘制。

## 实现与行为保障

- AppSectionCard 缓存卡片的独立绘制层；尺寸、装饰、主题和内容改变时仍由 Flutter 的正常失效机制更新。
- AppAnimatedIndexedStack 记录已访问索引，首次只挂载选中的标签。已访问子树保持原位，继续使用原有轻微切换动画、输入屏蔽、语义屏蔽和 TickerMode。
- 账本汇总由账本页 Consumer 订阅，不再让汇总状态变化重建整个 HomePage。加载和错误时仍显示使用空汇总的账本列表。
- 首页键盘回归测试更新为检查：从账户首次进入账本时，账本内容可见、未访问的记账输入未挂载、键盘保持隐藏。

## 验证

- 新增 3 项回归测试分别验证静止绘制复用与内容更新、标签按访问挂载且保留输入/滚动位置、全账本汇总延迟加载；相关断言已先在旧代码中出现预期失败。
- `flutter test --no-pub --reporter expanded`：450 项通过。
- `flutter analyze --no-pub`：无问题。
- `flutter build web --release --no-pub`：成功，输出 `build/web`。
- `git diff --check`：通过。

独立代码复核未发现阻断问题，并补充验证了首次淡入和减少动画设置、隐藏汇总失效后切回显示最新数据，以及 loading/error/data 切换时保持账本列表状态。

## 真机复测

安装版应在具体手机上运行 profile 版本，分别采集记账、账本、统计、账户和流水页面的慢速拖动与快速惯性滚动，记录 UI 与 raster 帧耗时。手机版网页应使用发布版，并通过浏览器性能记录定位主线程或绘制开销。还需结合机型、刷新率、数据量和具体运行版本判断后续瓶颈。

参考：[Flutter 性能分析](https://docs.flutter.dev/perf/ui-performance)、[RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)、[Impeller 渲染说明](https://docs.flutter.dev/perf/impeller)。

本轮仅本地集成，不推送或部署。
