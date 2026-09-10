import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';

// Moves float tensors between native memory and ORT without going through the
// plugin's list conversions, which both turned out to be the slow part of a
// frame on a SM-A137F:
//
//   input   OrtValueTensor.createTensorWithDataList flattens the Float32List it
//           is given into a growable List<double> -- boxing all 230k values --
//           then copies that element by element into a buffer it allocates,
//           then wraps the buffer. ~56 ms.
//   output  OrtValue.value copies the data one element at a time into a
//           growable List<num>, then reshapes it into nested lists, which the
//           caller has to walk to flatten again. ~46 ms.
//
// Both do real work only in their last step, and ORT's C API exposes that step
// directly -- so these call it directly.
//
// The plugin keeps tensor type and size private, so those are read from the C
// API too. Opaque ORT handles are typed as Pointer<Void>: the plugin's
// generated binding types live under its src/ and are not exported, and nothing
// here needs to know what is behind the pointers.

typedef _StatusFn2<T extends ffi.NativeType> = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<T>);
typedef _ReleaseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ReleaseDart = void Function(ffi.Pointer<ffi.Void>);
typedef _CreateTensorNative = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void> memoryInfo,
    ffi.Pointer<ffi.Void> data,
    ffi.Size dataBytes,
    ffi.Pointer<ffi.Int64> shape,
    ffi.Size shapeLength,
    ffi.Int32 elementType,
    ffi.Pointer<ffi.Pointer<ffi.Void>> out);
typedef _CreateTensorDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void> memoryInfo,
    ffi.Pointer<ffi.Void> data,
    int dataBytes,
    ffi.Pointer<ffi.Int64> shape,
    int shapeLength,
    int elementType,
    ffi.Pointer<ffi.Pointer<ffi.Void>> out);

final class _Api {
  _Api(OrtEnv env)
      : getShape = env.ortApiPtr.ref.GetTensorTypeAndShape
            .cast<ffi.NativeFunction<_StatusFn2<ffi.Pointer<ffi.Void>>>>()
            .asFunction(),
        getElementType = env.ortApiPtr.ref.GetTensorElementType
            .cast<ffi.NativeFunction<_StatusFn2<ffi.Int32>>>()
            .asFunction(),
        getElementCount = env.ortApiPtr.ref.GetTensorShapeElementCount
            .cast<ffi.NativeFunction<_StatusFn2<ffi.Size>>>()
            .asFunction(),
        releaseShape = env.ortApiPtr.ref.ReleaseTensorTypeAndShapeInfo
            .cast<ffi.NativeFunction<_ReleaseNative>>()
            .asFunction<_ReleaseDart>(),
        getData = env.ortApiPtr.ref.GetTensorMutableData
            .cast<ffi.NativeFunction<_StatusFn2<ffi.Pointer<ffi.Void>>>>()
            .asFunction(),
        allocatorGetInfo = env.ortApiPtr.ref.AllocatorGetInfo
            .cast<ffi.NativeFunction<_StatusFn2<ffi.Pointer<ffi.Void>>>>()
            .asFunction(),
        createTensorWithData = env.ortApiPtr.ref.CreateTensorWithDataAsOrtValue
            .cast<ffi.NativeFunction<_CreateTensorNative>>()
            .asFunction<_CreateTensorDart>();

  final _StatusFn2<ffi.Pointer<ffi.Void>> getShape;
  final _StatusFn2<ffi.Int32> getElementType;
  final _StatusFn2<ffi.Size> getElementCount;
  final _ReleaseDart releaseShape;
  final _StatusFn2<ffi.Pointer<ffi.Void>> getData;
  final _StatusFn2<ffi.Pointer<ffi.Void>> allocatorGetInfo;
  final _CreateTensorDart createTensorWithData;
}

// Resolved on first use, which is always after OrtEnv.init() -- nothing can
// create or read a tensor before a session exists.
final _api = _Api(OrtEnv.instance);

/// A non-null status is an error; hand it to the plugin, which throws with
/// ORT's message and frees the status.
void _check(ffi.Pointer<ffi.Void> status) {
  if (status != ffi.nullptr) OrtStatus.checkOrtStatus(status.cast());
}

/// Wraps [data] as an ORT float32 tensor of [shape], without copying it.
///
/// [data] stays owned by the caller, and ORT reads it for as long as the tensor
/// is in use -- so it must stay allocated and unmodified until inference on
/// this tensor has finished, which with runAsync means after the await returns.
/// Releasing the returned tensor frees only ORT's wrapper, never [data]: it is
/// deliberately constructed without the plugin's data pointer, since the plugin
/// would otherwise calloc.free memory it never allocated.
OrtValueTensor wrapFloat32Tensor(ffi.Pointer<ffi.Float> data, List<int> shape) {
  return using((arena) {
    final count = shape.fold<int>(1, (a, b) => a * b);
    // ORT copies the shape into the tensor, so this can be freed on return.
    final shapeOut = arena<ffi.Int64>(shape.length);
    shapeOut.asTypedList(shape.length).setAll(0, shape);

    // The same memory info the plugin uses for its own tensors: that of ORT's
    // default CPU allocator, which owns it, so it is not released here.
    final infoOut = arena<ffi.Pointer<ffi.Void>>();
    _check(_api.allocatorGetInfo(OrtAllocator.instance.ptr.cast(), infoOut));

    final valueOut = arena<ffi.Pointer<ffi.Void>>();
    _check(_api.createTensorWithData(
      infoOut.value,
      data.cast(),
      count * ffi.sizeOf<ffi.Float>(),
      shapeOut,
      shape.length,
      ONNXTensorElementDataType.float.value,
      valueOut,
    ));
    return OrtValueTensor(valueOut.value.cast());
  });
}

/// Copies float tensor [value] into a new Float32List of [expectedCount].
///
/// Throws instead of reading if the tensor is not float32 or holds a different
/// number of elements. That check is the whole reason to query ORT first rather
/// than just trusting [expectedCount]: the buffer is raw native memory, so a
/// model re-exported at another size would otherwise be read past its end --
/// in release builds too, where an assert would have been compiled out.
///
/// Returns a copy, not a view. The native buffer is freed when [value] is
/// released, and a view kept past that point would read freed memory: garbage
/// or a crash rather than an error. The copy is a single ~300 KB memmove.
Float32List readFloat32Output(OrtValue value, int expectedCount) {
  return using((arena) {
    final handle = value.ptr.cast<ffi.Void>();

    final shapeOut = arena<ffi.Pointer<ffi.Void>>();
    _check(_api.getShape(handle, shapeOut));
    final shape = shapeOut.value;
    try {
      final typeOut = arena<ffi.Int32>();
      _check(_api.getElementType(shape, typeOut));
      if (typeOut.value != ONNXTensorElementDataType.float.value) {
        throw StateError(
          'expected a float32 output tensor, got '
          '${ONNXTensorElementDataType.valueOf(typeOut.value)}',
        );
      }
      final countOut = arena<ffi.Size>();
      _check(_api.getElementCount(shape, countOut));
      if (countOut.value != expectedCount) {
        throw StateError(
          'output tensor holds ${countOut.value} values, expected '
          '$expectedCount -- the model and kModelInputHeight/Width disagree',
        );
      }
    } finally {
      _api.releaseShape(shape);
    }

    final dataOut = arena<ffi.Pointer<ffi.Void>>();
    _check(_api.getData(handle, dataOut));
    final view = dataOut.value.cast<ffi.Float>().asTypedList(expectedCount);
    return Float32List(expectedCount)..setRange(0, expectedCount, view);
  });
}
