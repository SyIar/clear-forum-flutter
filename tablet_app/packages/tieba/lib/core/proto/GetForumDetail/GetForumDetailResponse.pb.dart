// This is a generated file - do not edit.
//
// Generated from GetForumDetail/GetForumDetailResponse.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../Error.pb.dart' as $0;
import 'GetForumDetailResponseData.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetForumDetailResponse extends $pb.GeneratedMessage {
  factory GetForumDetailResponse({
    $0.Error? error,
    $1.GetForumDetailResponseData? data,
  }) {
    final result = GetForumDetailResponse._();
    if (error != null) result.error = error;
    if (data != null) result.data = data;
    return result;
  }

  GetForumDetailResponse._();

  factory GetForumDetailResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetForumDetailResponse()..mergeFromBuffer(data, registry);
  factory GetForumDetailResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetForumDetailResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetForumDetailResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'tieba.getForumDetail'),
      createEmptyInstance: GetForumDetailResponse.$_createMessage)
    ..aOM<$0.Error>(1, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..aOM<$1.GetForumDetailResponseData>(2, _omitFieldNames ? '' : 'data',
        subBuilder: $1.GetForumDetailResponseData.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetForumDetailResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetForumDetailResponse copyWith(
          void Function(GetForumDetailResponse) updates) =>
      super.copyWith((message) => updates(message as GetForumDetailResponse))
          as GetForumDetailResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetForumDetailResponse() / GetForumDetailResponse.new instead')
  static GetForumDetailResponse create() => GetForumDetailResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetForumDetailResponse._();
  @$core.override
  GetForumDetailResponse createEmptyInstance() => GetForumDetailResponse._();
  @$core.pragma('dart2js:noInline')
  static GetForumDetailResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetForumDetailResponse>(
          GetForumDetailResponse.$_createMessage);
  static GetForumDetailResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Error get error => $_getN(0);
  @$pb.TagNumber(1)
  set error($0.Error value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasError() => $_has(0);
  @$pb.TagNumber(1)
  void clearError() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Error ensureError() => $_ensure(0);

  @$pb.TagNumber(2)
  $1.GetForumDetailResponseData get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($1.GetForumDetailResponseData value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.GetForumDetailResponseData ensureData() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
