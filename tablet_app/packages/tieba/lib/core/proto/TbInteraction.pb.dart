// This is a generated file - do not edit.
//
// Generated from TbInteraction.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class TbInteraction extends $pb.GeneratedMessage {
  factory TbInteraction({
    $core.String? content,
  }) {
    final result = TbInteraction._();
    if (content != null) result.content = content;
    return result;
  }

  TbInteraction._();

  factory TbInteraction.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TbInteraction()..mergeFromBuffer(data, registry);
  factory TbInteraction.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TbInteraction()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TbInteraction',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba'),
      createEmptyInstance: TbInteraction.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'content')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TbInteraction clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TbInteraction copyWith(void Function(TbInteraction) updates) =>
      super.copyWith((message) => updates(message as TbInteraction))
          as TbInteraction;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TbInteraction() / TbInteraction.new instead')
  static TbInteraction create() => TbInteraction._();
  static $pb.GeneratedMessage $_createMessage() => TbInteraction._();
  @$core.override
  TbInteraction createEmptyInstance() => TbInteraction._();
  @$core.pragma('dart2js:noInline')
  static TbInteraction getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TbInteraction>(
          TbInteraction.$_createMessage);
  static TbInteraction? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get content => $_getSZ(0);
  @$pb.TagNumber(1)
  set content($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
