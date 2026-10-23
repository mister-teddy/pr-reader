import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver list whose item extents are known up front as prefix sums.
///
/// Flutter's `itemExtentBuilder` lists walk every preceding item to place a
/// child, which is O(n) per child and unusable at 100k+ rows. Here placing a
/// child is an array read and finding the first visible one is a binary
/// search, so scrolling (or dragging the scrollbar) anywhere in a giant diff
/// costs the same as at the top.
class SliverPrefixExtentList extends SliverMultiBoxAdaptorWidget {
  const SliverPrefixExtentList({super.key, required super.delegate, required this.offsets});

  /// `offsets[i]` is the leading edge of item i; `offsets.last` is the total.
  final Float64List offsets;

  @override
  RenderSliverPrefixExtentList createRenderObject(BuildContext context) {
    return RenderSliverPrefixExtentList(
      childManager: context as SliverMultiBoxAdaptorElement,
      offsets: offsets,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSliverPrefixExtentList renderObject) {
    renderObject.offsets = offsets;
  }

  @override
  double estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => offsets.last;
}

class RenderSliverPrefixExtentList extends RenderSliverFixedExtentBoxAdaptor {
  RenderSliverPrefixExtentList({required super.childManager, required this._offsets});

  Float64List _offsets;
  set offsets(Float64List value) {
    if (identical(value, _offsets)) return;
    _offsets = value;
    markNeedsLayout();
  }

  int get _count => _offsets.length - 1;

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder? get itemExtentBuilder => _extent;

  double? _extent(int index, SliverLayoutDimensions _) {
    if (index < 0 || index >= _count) return null;
    return _offsets[index + 1] - _offsets[index];
  }

  @override
  double indexToLayoutOffset(double itemExtent, int index) {
    if (index <= 0) return 0;
    return _offsets[index > _count ? _count : index];
  }

  /// Largest index whose leading edge is at or before [scrollOffset].
  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    if (_count <= 0) return 0;
    final target = scrollOffset + precisionErrorTolerance;
    var lo = 0, hi = _count - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_offsets[mid] <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Index of the item containing the point just before [scrollOffset].
  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    if (_count <= 0) return 0;
    final target = scrollOffset - precisionErrorTolerance;
    var lo = 0, hi = _count - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_offsets[mid + 1] >= target) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  @override
  double computeMaxScrollOffset(SliverConstraints constraints, double itemExtent) => _offsets[_count];

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _offsets[_count];
}
