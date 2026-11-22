import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';

class CustomListTile extends StatelessWidget {
  final Widget? icon;
  final Widget title;
  final Widget subTitle;
  final Widget? trailing;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  const CustomListTile({
    this.icon,
    required this.title,
    required this.subTitle,
    this.trailing,
    this.padding = const EdgeInsets.all(15),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      // Follow the global flat-card radius so every card matches.
      color: Theme.of(context).colorScheme.secondaryContainerIfDark,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 15),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final content = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: title,
                        ),
                        const SizedBox(height: 5),
                        subTitle,
                      ],
                    );
                    if (!constraints.hasBoundedHeight) {
                      return content;
                    }
                    // Hero 飞行会把子项约束到插值后的尺寸，可能比自然高度略小。
                    // 此时缩小内容而不是溢出。
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: content,
                      ),
                    );
                  },
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
