import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class TimelineStep {
  const TimelineStep(this.title, this.detail, {this.done = true});

  final String title;
  final String detail;
  final bool done;
}

class ProgressTimeline extends StatelessWidget {
  const ProgressTimeline(this.steps, {super.key});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: steps[i].done
                              ? AppColors.primary
                              : AppColors.fieldBorder,
                        ),
                      ),
                      if (i < steps.length - 1)
                        const Expanded(
                          child: VerticalDivider(
                            color: AppColors.primaryBorder,
                            width: 1,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: steps[i].done
                                ? AppColors.ink
                                : AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          steps[i].detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
