// This is a generated file - do not edit.
//
// Generated from HotTWThreadInfo.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'User.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class HotTWThreadInfo extends $pb.GeneratedMessage {
  factory HotTWThreadInfo({
    $core.Iterable<$0.User>? userList,
    $core.int? fansCount,
  }) {
    final result = HotTWThreadInfo._();
    if (userList != null) result.userList.addAll(userList);
    if (fansCount != null) result.fansCount = fansCount;
    return result;
  }

  HotTWThreadInfo._();

  factory HotTWThreadInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HotTWThreadInfo()..mergeFromBuffer(data, registry);
  factory HotTWThreadInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HotTWThreadInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HotTWThreadInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba'),
      createEmptyInstance: HotTWThreadInfo.$_createMessage)
    ..pPM<$0.User>(1, _omitFieldNames ? '' : 'userList',
        subBuilder: $0.User.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'fansCount', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HotTWThreadInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HotTWThreadInfo copyWith(void Function(HotTWThreadInfo) updates) =>
      super.copyWith((message) => updates(message as HotTWThreadInfo))
          as HotTWThreadInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HotTWThreadInfo() / HotTWThreadInfo.new instead')
  static HotTWThreadInfo create() => HotTWThreadInfo._();
  static $pb.GeneratedMessage $_createMessage() => HotTWThreadInfo._();
  @$core.override
  HotTWThreadInfo createEmptyInstance() => HotTWThreadInfo._();
  @$core.pragma('dart2js:noInline')
  static HotTWThreadInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HotTWThreadInfo>(
          HotTWThreadInfo.$_createMessage);
  static HotTWThreadInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$0.User> get userList => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get fansCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set fansCount($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFansCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearFansCount() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
