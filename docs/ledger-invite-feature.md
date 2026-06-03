# 账本邀请功能说明

本文档说明 Simon Ledger 的账本邀请功能。它用于在失去上下文后快速理解当前功能边界、代码入口和后续维护注意事项。

## 功能目标

账本所有者可以生成邀请码或邀请链接，其他用户先查看账本信息，再确认是否加入共享账本。

核心原则：

- 邀请不是直接加入，用户必须看到邀请页并主动确认。
- 分享不再使用弹窗，而是完整页面，避免信息拥挤。
- 加入也不再使用底部弹窗，而是完整页面，方便展示账本名称、编号、币种、成员、角色和有效期。
- 同一个邀请入口兼容 Android、iOS、Web 和手动粘贴。

## 用户流程

### 发起分享

1. 用户进入账本列表。
2. 对已同步到云端的账本点击分享。
3. App 调用后端创建邀请码。
4. 打开分享页面。
5. 用户可以复制：
   - 单独邀请码
   - 邀请链接
   - 完整邀请文本

邀请链接格式：

```text
https://ledger.simon996.com/invite/{code}
```

邀请码统一为 8 位大写字母或数字。

### 查看邀请

用户可以通过以下入口进入邀请确认页：

- 点击邀请链接。
- Web 端直接访问 `/invite/{code}`。
- 在“我的”页面手动输入邀请码。
- 在“我的”页面粘贴包含邀请码或邀请链接的文本。
- Android / iOS 前台检测剪贴板中存在 Simon Ledger 邀请内容时，顶部提示“查看”。

邀请确认页会展示：

- 账本名称
- 账本显示编号
- 邀请码
- 账本币种
- 共享成员数量和成员头像昵称
- 邀请角色
- 过期时间
- 是否已达到使用次数上限

### 加入账本

1. 未登录用户看到“登录后加入”。
2. 登录后用户点击“确认加入”。
3. App 调用后端加入接口。
4. 加入成功后刷新账本列表、统计和同步概览。
5. 页面关闭或回到首页。

## 代码入口

### 路由与链接接入

文件：

- `lib/app.dart`
- `lib/main.dart`
- `lib/core/services/invite_link_service.dart`

职责：

- `InviteLinks` 负责邀请码规范化、链接生成、文本解析和路由解析。
- `MaterialApp.onGenerateRoute` 处理 `/invite/{code}`。
- Android / iOS 使用 `app_links` 接收系统深链。
- App 启动和回到前台时，会尝试读取剪贴板里的邀请内容。
- Web 使用 path URL strategy，支持直接访问 `/invite/{code}`。

### 分享页与加入页

文件：

- `lib/features/ledgers/presentation/widgets/ledger_invite_widgets.dart`

主要组件：

- `LedgerInviteSharePage`
  - 展示邀请信息。
  - 复制邀请码、邀请链接、完整邀请文本。
- `LedgerInviteJoinPage`
  - 加载邀请详情。
  - 展示确认加入界面。
  - 未登录时跳转登录页。
  - 登录后执行加入。
- `LedgerInviteOverview`
  - 分享页和加入页共用的账本邀请信息展示组件。

### 分享入口

文件：

- `lib/features/home/presentation/screens/home_page.dart`

职责：

- 账本列表的分享按钮调用 `InviteRepository.createInvite`。
- 创建成功后打开 `LedgerInviteSharePage`。

### 手动输入和粘贴入口

文件：

- `lib/features/auth/presentation/widgets/account_tab.dart`

职责：

- 在“我的”页面提供邀请码输入。
- 支持从剪贴板粘贴邀请文本。
- 解析成功后进入 `LedgerInviteJoinPage`。

### 后端接口封装

文件：

- `lib/core/repositories/invite_repository.dart`

接口：

```text
POST /api/ledgers/{ledgerUuid}/invites
GET  /api/invites/{code}
POST /api/invites/{code}/join
```

`POST /api/invites/{code}/join` 使用固定幂等键：

```text
join-invite-{code}
```

避免用户重复点击导致重复加入。

## 平台配置

### Android

文件：

- `android/app/src/main/AndroidManifest.xml`

已声明处理：

```text
https://ledger.simon996.com/invite/*
```

Android App Links 需要部署：

```text
https://ledger.simon996.com/.well-known/assetlinks.json
```

模板文件：

- `web/.well-known/assetlinks.json.example`

### iOS

文件：

- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`

已声明 Associated Domain：

```text
applinks:ledger.simon996.com
```

iOS Universal Links 需要部署：

```text
https://ledger.simon996.com/.well-known/apple-app-site-association
```

模板文件：

- `web/.well-known/apple-app-site-association.example`

### Web

文件：

- `lib/main.dart`
- `nginx.conf`

Web 端使用 path URL strategy。Nginx 需要把 `/invite/{code}` 回退到 `index.html`，由 Flutter 解析路由。

详细部署步骤见：

- `docs/invite-link-deployment.md`

## 剪贴板检测策略

App 只在 Android / iOS 启动或回到前台时读取剪贴板。

检测到邀请内容后，不会强制跳转，而是在顶部显示提示，用户点击“查看”后进入邀请页。

分享页自己复制出去的邀请码会写入 `InviteClipboardMemory`，避免用户刚复制完就被自己的剪贴板内容提示打扰。

当前可识别内容：

```text
ABCD1234
https://ledger.simon996.com/invite/ABCD1234
邀请码：ABCD1234
```

## 当前限制

- 只有已同步到云端、拥有远端 UUID 的账本才能生成邀请。
- 加入账本必须登录。
- 邀请链接的 App Links / Universal Links 需要部署 `.well-known` 验证文件后，系统级打开才会完全生效。
- iOS 剪贴板读取可能受到系统隐私策略影响，读取失败时会静默忽略。
- Web 深链依赖服务器正确配置 SPA 回退。

## 回归测试点

修改邀请功能后至少验证：

1. 复制单独邀请码成功。
2. 复制邀请链接成功。
3. 复制完整邀请文本成功。
4. 输入小写邀请码后能规范化为大写并打开邀请页。
5. 输入非 Simon Ledger 链接不会跳转。
6. 未登录用户进入邀请页时显示“登录后加入”。
7. 已登录用户点击“确认加入”后刷新账本列表。
8. 邀请过期或次数用尽时按钮不可用，并展示可理解提示。
9. Web 直接访问 `/invite/{code}` 不白屏。
10. Android / iOS 点击系统链接能进入邀请页。

已有测试文件：

- `test/invite_link_service_test.dart`
- `test/invite_repository_test.dart`
- `test/ledger_invite_widgets_test.dart`

## 推荐验证命令

```bash
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter build ios --no-codesign
```
