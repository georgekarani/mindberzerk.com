import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A handle to one subtree's [RenderBox], for converting pointer positions.
///
/// The usual tool is a `GlobalKey` and `currentContext.findRenderObject()`.
/// A GlobalKey must be unique in the whole tree, and a shell rebuilt while a
/// route or a distro switch is mid-transition can hold two copies of the same
/// state for a frame, which throws "Duplicate GlobalKeys". This needs no key:
/// [BoxProbe] writes its render object into the [BoxRef] it is given.
class BoxRef {
  RenderBox? _box;

  /// The probed box while it is attached and laid out, else null.
  RenderBox? get box {
    final b = _box;
    return b != null && b.attached && b.hasSize ? b : null;
  }
}

/// Publishes its child's render box to [handle]. Paints and lays out exactly
/// as its child does.
class BoxProbe extends SingleChildRenderObjectWidget {
  const BoxProbe({super.key, required this.handle, super.child});

  final BoxRef handle;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBoxProbe(handle);

  @override
  void updateRenderObject(BuildContext context, RenderBoxProbe renderObject) {
    renderObject.handle = handle;
  }
}

/// The render object behind [BoxProbe]; public only because
/// [BoxProbe.updateRenderObject] names it.
class RenderBoxProbe extends RenderProxyBox {
  RenderBoxProbe(this._handle);

  BoxRef _handle;

  set handle(BoxRef value) {
    if (identical(value, _handle)) return;
    if (identical(_handle._box, this)) _handle._box = null;
    _handle = value;
    if (attached) _handle._box = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _handle._box = this;
  }

  @override
  void detach() {
    // Only clear it if it is still ours: a second copy of the same state may
    // have attached in the meantime and must keep the handle.
    if (identical(_handle._box, this)) _handle._box = null;
    super.detach();
  }
}
