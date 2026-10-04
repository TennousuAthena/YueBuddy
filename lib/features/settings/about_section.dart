import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/platform/harmony.dart';
import '../../theme/app_theme.dart';

const kYueBuddyRepositoryUrl = 'https://github.com/TennousuAthena/YueBuddy';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final frame = AppFrame(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          );
          final horizontal = frame.pagePadding;
          final maxWidth = frame.settingsMaxWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
                children: const [_AboutCard(child: AboutSection())],
              ),
            ),
          );
        },
      ),
    );
  }
}

class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '关于',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '粤语伴 YueBuddy 0.1.0 · 开源与版权',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '粤语伴 YueBuddy 0.1.0',
          style: TextStyle(fontWeight: FontWeight.w800, height: 1.45),
        ),
        SizedBox(height: 4),
        _Body('普通话到粤语的口袋练习册。前三课已开放。'),
        SizedBox(height: 16),
        _Heading('开源'),
        _Body('应用源代码公开在 GitHub，界面、练习逻辑、课文数据和语音后端都以这个仓库为准。'),
        SizedBox(height: 8),
        _LinkLine(label: '开源地址', url: kYueBuddyRepositoryUrl),
        SizedBox(height: 16),
        _Heading('课文与录音'),
        _Body(
          '课文、词表和老师原音来自广东话兴趣班讲义与课堂录音。这些材料的著作权属于讲义和录音的权利人。本应用在练习册里展示文字并播放原音。',
        ),
        SizedBox(height: 16),
        _Heading('插画'),
        _Body('名词卡和模块入口的插画来自 いらすとや，作者是 みふねたかし。画面上标有「插画：いらすとや」。'),
        SizedBox(height: 8),
        _LinkLine(label: 'いらすとや', url: 'https://www.irasutoya.com/'),
        SizedBox(height: 6),
        _LinkLine(label: '使用条款', url: 'https://www.irasutoya.com/p/terms.html'),
        SizedBox(height: 8),
        _Body(
          '按该站条款，个人用途以及符合条款的商业设计可以使用这些插画。插画素材本身不得当作商品再分发或销售，也不得用于违反公序良俗的内容。商业设计用到 21 张以上时，需要联系作者另行取得许可。本练习册已经超过 21 张；若用于商业发行，须先取得 みふねたかし 的许可。',
        ),
        SizedBox(height: 16),
        _Heading('开源组件'),
        _Body('本应用基于下列开源软件，版本以 pubspec.lock 为准。'),
        SizedBox(height: 8),
        _ComponentLine(
          name: 'Flutter SDK',
          license: 'BSD 3-Clause License',
          url: 'https://github.com/flutter/flutter',
        ),
        _ComponentLine(
          name: 'flutter_tts 4.2.5',
          license: 'MIT License，Copyright (c) 2018 Daniel Lutton',
          url: 'https://github.com/dlutton/flutter_tts',
        ),
        _ComponentLine(
          name: 'audioplayers 6.8.1',
          license: 'MIT License，Copyright (c) 2017 Blue Fire',
          url: 'https://github.com/bluefireteam/audioplayers',
        ),
        _ComponentLine(
          name: 'shared_preferences 2.5.5',
          license: 'BSD 3-Clause License，Copyright 2013 The Flutter Authors',
          url:
              'https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences',
        ),
        _ComponentLine(
          name: 'http 1.6.0',
          license:
              'BSD 3-Clause License，Copyright 2014, the Dart project authors',
          url: 'https://github.com/dart-lang/http',
        ),
        _ComponentLine(
          name: 'crypto 3.0.7',
          license:
              'BSD 3-Clause License，Copyright 2015, the Dart project authors',
          url: 'https://github.com/dart-lang/core/tree/main/pkgs/crypto',
        ),
        _ComponentLine(
          name: 'cupertino_icons 1.0.9',
          license: 'MIT License，Copyright (c) 2016 Vladimir Kharlampidi',
          url:
              'https://github.com/flutter/packages/tree/main/third_party/packages/cupertino_icons',
        ),
        _ComponentLine(
          name: 'url_launcher 6.3.3',
          license: 'BSD 3-Clause License，Copyright 2013 The Flutter Authors',
          url:
              'https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher',
        ),
        SizedBox(height: 16),
        _Heading('语音'),
        _Body(
          isHarmonyOs
              ? '在线朗读经过本项目的语音后端，由 MiniMax 合成。合成结果适用 MiniMax 的服务条款。'
              : '在线朗读经过本项目的语音后端，由 MiniMax 合成。合成结果适用 MiniMax 的服务条款。系统离线朗读使用设备里的「中文（香港）」语音。',
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w800));
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              SelectableText(
                url,
                style: const TextStyle(
                  color: AppColors.greenDark,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '在浏览器中打开',
          onPressed: () => openAboutLink(context, url),
          icon: const Icon(
            Icons.open_in_new_rounded,
            color: AppColors.greenDark,
          ),
        ),
      ],
    );
  }
}

class _ComponentLine extends StatelessWidget {
  const _ComponentLine({
    required this.name,
    required this.license,
    required this.url,
  });

  final String name;
  final String license;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            license,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              IconButton(
                tooltip: '在浏览器中打开',
                visualDensity: VisualDensity.compact,
                onPressed: () => openAboutLink(context, url),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: AppColors.greenDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: child,
    );
  }
}

Future<void> openAboutLink(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('无法打开链接，地址已复制')));
}
