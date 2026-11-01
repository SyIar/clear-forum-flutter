// This is a generated file - do not edit.
//
// Generated from GetForumDetail/GetForumDetailRequest.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'GetForumDetailRequestData.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetForumDetailRequest extends $pb.GeneratedMessage {
  factory GetForumDetailRequest({
    $0.GetForumDetailRequestData? data,
  }) {
    final result = GetForumDetailRequest._();
    if (data != null) result.data = data;
    return result;
  }

  GetForumDetailRequest._();

  factory GetForumDetailRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetForumDetailRequest()..mergeFromBuffer(data, registry);
  factory GetForumDetailRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetForumDetailRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetForumDetailRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'tieba.getForumDetail'),
      createEmptyInstance: GetForumDetailRequest.$_createMessage)
    ..aOM<$0.GetForumDetailRequestData>(1, _omitFieldNames ? '' : 'data',
        subBuilder: $0.GetForumDetailRequestData.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetForumDetailRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetForumDetailRequest copyWith(
          void Function(GetForumDetailRequest) updates) =>
      super.copyWith((message) => updates(message as GetForumDetailRequest))
          as GetForumDetailRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetForumDetailRequest() / GetForumDetailRequest.new instead')
  static GetForumDetailRequest create() => GetForumDetailRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetForumDetailRequest._();
  @$core.override
  GetForumDetailRequest createEmptyInstance() => GetForumDetailRequest._();
  @$core.pragma('dart2js:noInline')
  static GetForumDetailRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetForumDetailRequest>(
          GetForumDetailRequest.$_createMessage);
  static GetForumDetailRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.GetForumDetailRequestData get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($0.GetForumDetailRequestData value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.GetForumDetailRequestData ensureData() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
