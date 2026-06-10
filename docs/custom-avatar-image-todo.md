# 图片头像选项待做项

## 背景

当前资料头像使用 `AvatarConfig` 中维护的 emoji/key 方案，用户资料和同步接口保存的是头像 key，界面再根据 key 渲染对应 emoji。后续希望支持把 PNG/JPG 图片加入头像候选，让用户可以从内置图片头像中选择。

## 目标

- 支持把项目内置 PNG/JPG 图片作为头像选项。
- 保留现有 emoji 头像，不破坏已保存用户资料。
- 用户保存资料时仍存储稳定 key，不直接存储图片二进制。
- 图片头像在“我的”资料卡、编辑资料弹窗、账本成员、参与人和流水相关展示中渲染一致。

## 建议资源规范

- 文件格式：优先 PNG，也支持 JPG。
- 尺寸：建议 `256x256` 或 `512x512`。
- 形状：建议正方形。
- 背景：PNG 透明背景最佳。
- 路径建议：

```text
assets/avatars/
  avatar_custom_01.png
  avatar_custom_02.jpg
```

## 实现清单

1. 新增头像资源目录。

```text
assets/avatars/
```

2. 在 `pubspec.yaml` 声明资源。

```yaml
flutter:
  assets:
    - assets/avatars/
```

3. 扩展 `AvatarOption` 数据结构。

当前：

```dart
class AvatarOption {
  const AvatarOption({required this.key, required this.avatar});

  final String key;
  final String avatar;
}
```

建议支持两类头像：

```dart
enum AvatarOptionType { emoji, asset }

class AvatarOption {
  const AvatarOption.emoji({required this.key, required this.value})
      : type = AvatarOptionType.emoji;

  const AvatarOption.asset({required this.key, required this.value})
      : type = AvatarOptionType.asset;

  final String key;
  final String value;
  final AvatarOptionType type;
}
```

4. 在 `AvatarConfig.options` 中加入图片头像。

```dart
AvatarOption.asset(
  key: 'custom_avatar_01',
  value: 'assets/avatars/avatar_custom_01.png',
),
```

5. 新增统一头像渲染组件。

建议新增类似 `AppAvatarView` 的组件，集中处理：

- emoji 头像：渲染 `Text`
- asset 图片头像：渲染 `Image.asset`
- 未知 key：回退默认头像
- 圆形裁剪、背景色、尺寸、语义标签

6. 替换现有头像展示点。

重点检查：

- `lib/features/auth/presentation/widgets/account_tab.dart`
- `lib/features/people_pool/presentation/widgets/person_edit_dialog.dart`
- `lib/core/widgets/app_components.dart`
- 流水详情、记账成功提示、成员列表等使用 `avatar` 的组件

7. 兼容资料同步。

后端 `user_account.avatar` 当前允许保存字符串。图片头像也保存 key，例如：

```text
custom_avatar_01
```

不要上传图片本身，也不要把 asset 路径直接作为用户资料值长期依赖。这样后续可以替换资源路径而不迁移用户数据。

8. 补充测试。

建议新增或调整 Widget Test：

- 编辑资料弹窗能显示图片头像选项。
- 点击图片头像后，顶部预览切换为图片。
- 保存后 `LocalProfile.avatarIcon` 保存图片头像 key。
- 旧 emoji key 仍能正常显示。
- 未知 key 回退默认头像。

## 验收标准

- `flutter analyze` 通过。
- 相关 Widget Test 通过。
- 用户可以在编辑资料中选择 PNG/JPG 图片头像。
- 保存后重新进入应用，图片头像仍正确显示。
- 已有 emoji 头像用户不受影响。

## 注意事项

- 图片资源需要控制体积，避免显著增加 Web 首屏加载大小。
- 图片头像 key 一旦发布，不建议随意改名。
- 如果以后支持用户上传头像，需要另做上传、裁剪、压缩、存储、鉴权和 CDN 方案；本待做项仅覆盖“内置图片头像选项”。
