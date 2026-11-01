// This is a generated file - do not edit.
//
// Generated from Profile/FinanceTab.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'FinanceTabItems.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class FinanceTab extends $pb.GeneratedMessage {
  factory FinanceTab({
    $core.String? title,
    $core.String? generalTabText,
    $core.String? generalTabUrl,
    $core.Iterable<$0.FinanceTabItems>? tabs,
  }) {
    final result = FinanceTab._();
    if (title != null) result.title = title;
    if (generalTabText != null) result.generalTabText = generalTabText;
    if (generalTabUrl != null) result.generalTabUrl = generalTabUrl;
    if (tabs != null) result.tabs.addAll(tabs);
    return result;
  }

  FinanceTab._();

  factory FinanceTab.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinanceTab()..mergeFromBuffer(data, registry);
  factory FinanceTab.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinanceTab()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinanceTab',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tieba.profile'),
      createEmptyInstance: FinanceTab.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aOS(2, _omitFieldNames ? '' : 'generalTabText')
    ..aOS(3, _omitFieldNames ? '' : 'generalTabUrl')
    ..pPM<$0.FinanceTabItems>(4, _omitFieldNames ? '' : 'tabs',
        subBuilder: $0.FinanceTabItems.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinanceTab clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinanceTab copyWith(void Function(FinanceTab) updates) =>
      super.copyWith((message) => updates(message as FinanceTab)) as FinanceTab;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FinanceTab() / FinanceTab.new instead')
  static FinanceTab create() => FinanceTab._();
  static $pb.GeneratedMessage $_createMessage() => FinanceTab._();
  @$core.override
  FinanceTab createEmptyInstance() => FinanceTab._();
  @$core.pragma('dart2js:noInline')
  static FinanceTab getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinanceTab>(FinanceTab.$_createMessage);
  static FinanceTab? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generalTabText => $_getSZ(1);
  @$pb.TagNumber(2)
  set generalTabText($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneralTabText() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneralTabText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get generalTabUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set generalTabUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneralTabUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneralTabUrl() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$0.FinanceTabItems> get tabs => $_getList(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
