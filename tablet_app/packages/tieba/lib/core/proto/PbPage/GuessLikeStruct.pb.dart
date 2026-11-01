// This is a generated file - do not edit.
//
// Generated from PbPage/GuessLikeStruct.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../GuessLikeThreadInfo.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GuessLikeStruct extends $pb.GeneratedMessage {
  factory GuessLikeStruct({
    $core.String? title,
    $core.Iterable<$0.GuessLikeThreadInfo>? threadList,
  }) {
    final result = GuessLikeStruct._();
    if (title != null) result.title = title;
    if (threadList != null) result.threadList.addAll(threadList);
    return result;
  }

  GuessLikeStruct._();

  factory GuessLikeStruct.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GuessLikeStruct()..mergeFromBuffer(data, registry);
  factory GuessLikeStruct.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GuessLikeStruct()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GuessLikeStruct',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba.pbPage'),
      createEmptyInstance: GuessLikeStruct.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..pPM<$0.GuessLikeThreadInfo>(2, _omitFieldNames ? '' : 'threadList',
        subBuilder: $0.GuessLikeThreadInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GuessLikeStruct clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GuessLikeStruct copyWith(void Function(GuessLikeStruct) updates) =>
      super.copyWith((message) => updates(message as GuessLikeStruct))
          as GuessLikeStruct;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GuessLikeStruct() / GuessLikeStruct.new instead')
  static GuessLikeStruct create() => GuessLikeStruct._();
  static $pb.GeneratedMessage $_createMessage() => GuessLikeStruct._();
  @$core.override
  GuessLikeStruct createEmptyInstance() => GuessLikeStruct._();
  @$core.pragma('dart2js:noInline')
  static GuessLikeStruct getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GuessLikeStruct>(
          GuessLikeStruct.$_createMessage);
  static GuessLikeStruct? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$0.GuessLikeThreadInfo> get threadList => $_getList(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
