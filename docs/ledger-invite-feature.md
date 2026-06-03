# 账本邀请功能说明

本文档说明 Simon Ledger 的账本邀请功能。它用于在失去上下文后快速理解当前功能边界、代码入口和后续维护注意事项。

## 功能目标

账本所有者可以查看当前可用的邀请码或邀请链接，必要时重新生成邀请码。其他用户先查看账本信息，再确认是否加入共享账本。

核心原则：

- 邀请不是直接加入，用户必须看到邀请页并主动确认。
- 分享使用轻量弹窗，只保留复制邀请所需的信息。
- 一个账本默认只维护一个“当前可用邀请码”。用户点击分享时优先复用当前邀请码，避免反复创建多个同时可用的邀请码。
- 只有用户明确点击“重新生成”，才禁用旧的当前邀请码并创建新邀请码。
- 邀请有效期和次数由用户在重新生成时选择，不再由前端静默固定成 7 天和 20 次。
- 加入也不再使用底部弹窗，而是完整页面，方便展示账本名称、编号、币种、成员、角色和有效期。
- 同一个邀请入口兼容 Android、iOS、Web 和手动粘贴。

## 用户流程

### 发起分享

1. 用户进入账本列表。
2. 对已同步到云端的账本点击分享。
3. App 查询该账本当前可用邀请码。
4. 如果存在当前可用邀请码，直接打开轻量分享弹窗。
5. 如果不存在当前可用邀请码，打开生成邀请配置态。
6. 用户可以复制：
   - 单独邀请码
   - 邀请链接
   - 完整邀请文本

邀请链接格式：

```text
https://ledger.simon996.com/invite/{code}
```

邀请码统一为 8 位大写字母或数字。

### 重新生成邀请

生成配置态只暴露用户真正需要理解的两个选项：

- 有效期：`1 / 3 / 5 / 7 天`
- 使用次数：默认 `5 次`

默认值：

```text
有效期：1 天
使用次数：5 次
角色：editor
```

角色暂时不暴露给用户，统一为可共同记账。

用户点击“重新生成”时：

1. 后端校验当前用户是否有管理账本权限。
2. 后端禁用该账本下已有的当前可用邀请码。
3. 后端创建新的邀请码。
4. 前端更新分享弹窗，展示新邀请码。

旧邀请码被禁用后，收到旧链接的人会在邀请确认页看到不可加入状态。

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

### 分享弹窗与加入页

文件：

- `lib/features/ledgers/presentation/widgets/ledger_invite_widgets.dart`

主要组件：

- `showLedgerInviteShareSheet`
  - 打开轻量分享弹窗。
- `LedgerInviteShareSheet`
  - 展示账本名和邀请码。
  - 复制邀请码、邀请链接、完整邀请文本。
  - 有可用邀请时显示“重新生成”入口。
  - 没有可用邀请或用户点击重新生成时，展示有效期和使用次数配置。
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

- 账本列表的分享按钮先调用 `InviteRepository.getCurrentInvite`。
- 有当前可用邀请码时打开分享弹窗。
- 没有当前可用邀请码时打开生成配置态。
- 创建成功后打开 `LedgerInviteShareSheet`。

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
GET  /api/ledgers/{ledgerUuid}/invites/current
POST /api/ledgers/{ledgerUuid}/invites/regenerate
GET  /api/invites/{code}
POST /api/invites/{code}/join
```

`POST /api/invites/{code}/join` 使用固定幂等键：

```text
join-invite-{code}
```

避免用户重复点击导致重复加入。

创建或重新生成邀请的请求体：

```text
role: editor
days: 1 | 3 | 5 | 7
maxUses: 5
```

后端负责把 `days` 转换为真实 `expiresAt` 并入库，避免客户端直接决定过期时间。后端在预览和加入时继续使用入库的 `expiresAt`、`maxUses`、`usedCount` 判断邀请码是否可用。

### 后端存储策略

邀请码存储在 MySQL 的 `ledger_invite` 表中，不使用 Redis 作为唯一存储。

保留数据库存储的原因：

- 邀请码需要记录有效期、使用次数、已使用次数和禁用状态。
- 加入时需要并发安全地递增 `used_count`。
- 需要保留审计和排查问题的依据。

目标状态规则：

- 同一个账本可以保留历史邀请码记录。
- 同一个账本同一时刻只应该有一个当前可用邀请码。
- 重新生成邀请码时，后端禁用旧的当前可用邀请码，再创建新邀请码。
- 当前可用邀请码定义为：未禁用、未过期、未超过使用次数。

后端并发要求：

- 重新生成邀请需要事务保护。
- 禁用旧码和创建新码必须在同一事务内完成。
- 加入时继续使用条件更新限制 `used_count < max_uses`，避免并发超用。

### 待实现接口细节

#### 查询当前可用邀请

```text
GET /api/ledgers/{ledgerUuid}/invites/current
```

行为：

- 需要登录。
- 需要是账本成员。
- 返回该账本最新的当前可用邀请码。
- 如果没有当前可用邀请码，返回 `data: null`。

#### 重新生成邀请

```text
POST /api/ledgers/{ledgerUuid}/invites/regenerate
```

请求：

```json
{
  "role": "editor",
  "days": 1,
  "maxUses": 5
}
```

行为：

- 需要登录。
- 需要有管理账本权限。
- `days` 只能是 `1 / 3 / 5 / 7`。
- `maxUses` 必须大于 0，默认前端传 `5`。
- 禁用旧的当前可用邀请码。
- 创建并返回新邀请码。

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
4. 账本已有可用邀请码时，点击分享不会创建新码，而是展示当前码。
5. 账本没有可用邀请码时，点击分享展示生成配置态。
6. 重新生成时可以选择 `1 / 3 / 5 / 7 天`，默认 `1 天`。
7. 重新生成时使用次数默认 `5`，且必须大于 0。
8. 重新生成后旧邀请码不可再加入，新邀请码可加入。
9. 输入小写邀请码后能规范化为大写并打开邀请页。
10. 输入非 Simon Ledger 链接不会跳转。
11. 未登录用户进入邀请页时显示“登录后加入”。
12. 已登录用户点击“确认加入”后刷新账本列表。
13. 邀请过期或次数用尽时按钮不可用，并展示可理解提示。
14. Web 直接访问 `/invite/{code}` 不白屏。
15. Android / iOS 点击系统链接能进入邀请页。

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
