import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Skeleton loader for better loading states
class SkeletonLoader extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    Key? key,
    this.width,
    this.height = 16,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Shimmer.fromColors(
      baseColor: theme.primaryBackground,
      highlightColor: theme.secondaryBackground,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: borderRadius ?? BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Skeleton for list items
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(
            width: 48,
            height: 48,
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 16,
                ),
                const SizedBox(height: 8),
                SkeletonLoader(
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for conversation items
class ConversationItemSkeleton extends StatelessWidget {
  const ConversationItemSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonLoader(
                      width: MediaQuery.of(context).size.width * 0.3,
                      height: 16,
                    ),
                    const SkeletonLoader(
                      width: 40,
                      height: 12,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SkeletonLoader(
                  width: MediaQuery.of(context).size.width * 0.5,
                  height: 14,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for pulse cards in grid
class PulseCardSkeleton extends StatelessWidget {
  const PulseCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonLoader(
          width: double.infinity,
          height: 200,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        const SizedBox(height: 8),
        SkeletonLoader(
          width: MediaQuery.of(context).size.width * 0.4,
          height: 16,
        ),
        const SizedBox(height: 6),
        SkeletonLoader(
          width: MediaQuery.of(context).size.width * 0.3,
          height: 12,
        ),
      ],
    );
  }
}

/// Loading list view with skeletons
class SkeletonListView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const SkeletonListView({
    Key? key,
    this.itemCount = 8,
    required this.itemBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
