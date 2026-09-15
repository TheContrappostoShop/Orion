/*
* Orion - Selection Screens
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter/material.dart';
import 'package:orion/backend_service/providers/resins_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/widgets/orion_app_bar.dart';

class DetailedSelectionScreen extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final List<Widget>? actions;

  const DetailedSelectionScreen({
    super.key,
    required this.title,
    required this.child,
    this.padding = OrionSpacing.screenPadding,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return GlassApp(
      child: Scaffold(
        appBar: OrionAppBar(
          title: Text(title),
          actions: actions ?? const [SystemStatusWidget()],
          toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
        ),
        body: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class ListSelectionScreen<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final Widget? header;
  final EdgeInsetsGeometry padding;
  final List<Widget>? actions;

  const ListSelectionScreen({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.separatorBuilder,
    this.header,
    this.padding = OrionSpacing.screenPadding,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return DetailedSelectionScreen(
      title: title,
      padding: padding,
      actions: actions,
      child: header == null
          ? ListView.separated(
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  itemBuilder(context, items[index]),
              separatorBuilder: separatorBuilder ??
                  (context, index) {
                    return const SizedBox(height: OrionSpacing.listGap);
                  },
            )
          : Column(
              children: [
                header!,
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        itemBuilder(context, items[index]),
                    separatorBuilder: separatorBuilder ??
                        (context, index) {
                          return const SizedBox(height: OrionSpacing.listGap);
                        },
                  ),
                ),
              ],
            ),
    );
  }
}

class ResinProfileSelectionScreen extends StatelessWidget {
  final String title;
  final List<ResinProfile> resins;
  final String? selectedResinKey;
  final ValueChanged<ResinProfile> onSelected;

  const ResinProfileSelectionScreen({
    super.key,
    required this.title,
    required this.resins,
    required this.selectedResinKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListSelectionScreen<ResinProfile>(
      title: title,
      items: resins,
      separatorBuilder: (ctx, i) => const SizedBox(height: 10),
      itemBuilder: (context, resin) {
        final resinKey = resin.path ?? resin.name;
        final isSelected = selectedResinKey == resinKey;
        final meta = resin.meta;
        final parts = <String>[];
        if (meta['viscosity'] != null) {
          parts.add('Viscosity: ${meta['viscosity']}');
        }
        if (meta['exposure'] != null) {
          parts.add('Exposure: ${meta['exposure']}');
        }
        final accent = Theme.of(context).colorScheme.primary;

        return GlassCard(
          elevation: isSelected ? 2.0 : 1.0,
          outlined: true,
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
          child: InkWell(
            onTap: () => onSelected(resin),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (isSelected ? accent : Colors.blueGrey)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.science,
                      color: isSelected ? accent : Colors.blueGrey.shade300,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resin.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (parts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              parts.join(' • '),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      border: isSelected
                          ? null
                          : Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 2,
                            ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

