// This is a generated file - do not edit.
//
// Generated from FrsPage/Group.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Group extends $pb.GeneratedMessage {
  factory Group({
    $core.int? hideRecommendGroup,
    $core.int? groupCount,
  }) {
    final result = Group._();
    if (hideRecommendGroup != null)
      result.hideRecommendGroup = hideRecommendGroup;
    if (groupCount != null) result.groupCount = groupCount;
    return result;
  }

  Group._();

  factory Group.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Group()..mergeFromBuffer(data, registry);
  factory Group.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Group()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Group',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba.frsPage'),
      createEmptyInstance: Group.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'hideRecommendGroup')
    ..aI(2, _omitFieldNames ? '' : 'groupCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Group clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Group copyWith(void Function(Group) updates) =>
      super.copyWith((message) => updates(message as Group)) as Group;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Group() / Group.new instead')
  static Group create() => Group._();
  static $pb.GeneratedMessage $_createMessage() => Group._();
  @$core.override
  Group createEmptyInstance() => Group._();
  @$core.pragma('dart2js:noInline')
  static Group getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Group>(Group.$_createMessage);
  static Group? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get hideRecommendGroup => $_getIZ(0);
  @$pb.TagNumber(1)
  set hideRecommendGroup($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHideRecommendGroup() => $_has(0);
  @$pb.TagNumber(1)
  void clearHideRecommendGroup() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get groupCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set groupCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroupCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupCount() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
