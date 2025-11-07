// class EditorController {
//   String Function()? _getValue;

//   // Called by the Editor widget when it becomes ready
//   void bind({required String Function() getValue}) {
//     _getValue = getValue;
//   }

//   // Called by the parent (Dashboard) when Run is pressed
//   Future<String> getCode() async {
//     final getter = _getValue;
//     if (getter == null) {
//       throw StateError('Editor is not ready yet');
//     }
//     return getter();
//   }
// }
