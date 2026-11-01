// This is a generated file - do not edit.
//
// Generated from UserPost/UserPostResponse.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../Error.pb.dart' as $0;
import 'UserPostResponseData.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class UserPostResponse extends $pb.GeneratedMessage {
  factory UserPostResponse({
    $0.Error? error,
    $1.UserPostResponseData? data,
  }) {
    final result = UserPostResponse._();
    if (error != null) result.error = error;
    if (data != null) result.data = data;
    return result;
  }

  UserPostResponse._();

  factory UserPostResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserPostResponse()..mergeFromBuffer(data, registry);
  factory UserPostResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserPostResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserPostResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba.userPost'),
      createEmptyInstance: UserPostResponse.$_createMessage)
    ..aOM<$0.Error>(1, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..aOM<$1.UserPostResponseData>(2, _omitFieldNames ? '' : 'data',
        subBuilder: $1.UserPostResponseData.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserPostResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserPostResponse copyWith(void Function(UserPostResponse) updates) =>
      super.copyWith((message) => updates(message as UserPostResponse))
          as UserPostResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserPostResponse() / UserPostResponse.new instead')
  static UserPostResponse create() => UserPostResponse._();
  static $pb.GeneratedMessage $_createMessage() => UserPostResponse._();
  @$core.override
  UserPostResponse createEmptyInstance() => UserPostResponse._();
  @$core.pragma('dart2js:noInline')
  static UserPostResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserPostResponse>(
          UserPostResponse.$_createMessage);
  static UserPostResponse? _defaultInstance;

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
  $1.UserPostResponseData get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($1.UserPostResponseData value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.UserPostResponseData ensureData() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
