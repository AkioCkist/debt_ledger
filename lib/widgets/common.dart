import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vòng tròn chữ cái đầu. Màu chọn theo [seed] (thường là id người dùng) để
/// mỗi người giữ một màu cố định, dễ nhận ra trong danh bạ.
class InitialAvatar extends StatelessWidget {
  final String initial;
  final String seed;
  final double size;

  const InitialAvatar({
    super.key,
    required this.initial,
    required this.seed,
    this.size = 40,
  });

  static const _palette = [
    (bg: Color(0xFFE3ECE8), fg: Color(0xFF2B5D4F)),
    (bg: Color(0xFFF3E5E0), fg: Color(0xFF8E3A26)),
    (bg: Color(0xFFE3E9F2), fg: Color(0xFF33507A)),
    (bg: Color(0xFFE6E4F2), fg: Color(0xFF4A4380)),
    (bg: Color(0xFFF3ECDA), fg: Color(0xFF6E5214)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palette[seed.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          color: colors.fg,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Nhãn nhóm nhỏ, viết hoa, đặt trên mỗi khối nội dung.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Một khối nền trắng chứa nhiều dòng, ngăn nhau bằng đường kẻ mảnh.
class GroupedCard extends StatelessWidget {
  final List<Widget> children;

  const GroupedCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 66),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Thanh nút cố định ở đáy màn hình, nền mờ dần lên trên để không cắt
/// ngang nội dung đang cuộn.
class BottomActionBar extends StatelessWidget {
  final Widget child;

  const BottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F6F5F1), AppColors.background],
          stops: [0, 0.35],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: child,
      ),
    );
  }
}
