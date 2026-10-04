> 模板版本: v0.0.1

<p align="center">
  <h1 align="center"> <code>audioplayers</code> </h1>
</p>

本项目基于 [audioplayers](https://pub.dev/packages/audioplayers) 开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml

dependencies:
  audioplayers:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_audioplayers.git
      path: packages/audioplayers
      ref: TAG #通过下面的框架版本选择TAG
      #ref: 6.5.1-ohos-1.0.0
```

### TAG 版本对应表

| Flutter 框架版本 | TAG                    |  分支    |
|--------------|------------------------|--------|
| 3.22         | 4.1.0-ohos-1.0.0-beta.1 | master |
| 3.22         | 6.1.0-ohos-1.0.0-beta.1 | br_audioplayers-v6.1.0_ohos |
| 3.27         |6.5.1-ohos-1.0.0 | br_v6.5.1_ohos |
| 3.35         |6.5.1-ohos-1.0.0 | br_v6.5.1_ohos |


执行命令

```bash
flutter pub get
```

<!-- tabs:end -->

### 1.2 使用案例

使用案例详见 [ohos/example](./packages/audioplayers/example/lib/main.dart)

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

Flutter: 3.27.5-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 5.1.0.130 SP8;
Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;
### 2.2 权限要求

#### 2.2.1 在 entry 目录下的 module.json5 中添加权限

打开 `entry/src/main/module.json5`，添加：

```diff
...
"abilities": [
    {
+     "backgroundModes": [
+        "audioPlayback",
+     ],
    }
],
...
"requestPermissions": [
+  {
+    "name": "ohos.permission.KEEP_BACKGROUND_RUNNING",
+    "reason": "$string:background_running_reason",
+    "usedScene": {
+      "abilities": [
+        "EntryAbility"
+      ],
+      "when":"inuse"
+    }
+  }
]
```

#### 2.2.2 在 entry 目录下的 string.json 添加申请以上权限的原因

打开 `entry/src/main/resources/base/element/string.json`，添加：

```diff
...
{
  "string": [
+    {
+      "name": "background_running_reason",
+      "value": "后台运行"
+    }
  ]
}
```

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name               | Description      | Type      | Input                               | Output            | ohos Support |
| ------------------ | ---------------- | --------- | ----------------------------------- | ----------------- | ------------ |
| setSourceUrl       | 设置 url 播放源  | string    | String url, {String? mimeType}      | Future<void>      | yes          |
| setSourceBytes     | 设置字节流播放源 | uint8List | Uint8List bytes, {String? mimeType} | Future<void>      | yes          |
| resume             | 恢复暂停的播放   | function  | /                                   | Future<void>      | yes          |
| pause              | 暂停播放         | function  | /                                   | Future<void>      | yes          |
| stop               | 停止播放         | function  | /                                   | Future<void>      | yes          |
| seek               | 跳转到指定位置   | function  | Duration position                   | Future<void>      | yes          |
| setVolume          | 设置音量         | function  | double volume                       | Future<void>      | yes          |
| setBalance         | 设置左右声道平衡 | function  | double balance                      | Future<void>      | yes          |
| setPlaybackRate    | 设置播放速率     | function  | double playbackRate                 | Future<void>      | yes          |
| release            | 释放播放器资源   | function  | /                                   | Future<void>      | yes          |
| dispose            | 销毁播放器实例   | function  | /                                   | Future<void>      | yes          |
| getDuration        | 获取总时长       | function  | /                                   | Future<Duration?> | yes          |
| getCurrentPosition | 获取当前播放位置 | function  | /                                   | Future<Duration?> | yes          |
| setPlayerMode      | 设置播放模式     | function  | PlayerMode mode                     | Future<void>      | yes          |
| setAudioContext    | 设置播放参数     | function  | AudioContext ctx                    | Future<void>      | yes          |

## 4. 属性

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

### setAudioContext Parameters

| Name          | Description                        | Type    | Input | Output | ohos Support |
| ------------- | ---------------------------------- | ------- | ----- | ------ | ------------ |
| rendererFlags | 设置播放参数                       | number  | /     | /      | yes          |
| usageType     | 定义音频用途类型                   | number  | /     | /      | yes          |
| stayAwake     | 控制是否在播放期间保持设备唤醒状态 | boolean | /     | /      | yes          |

## 5. 遗留问题

## 6. 其他

## 7. 开源协议

本项目基于 [The MIT License (MIT)](./LICENSE) ，请自由地享受和参与开源。
