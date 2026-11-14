// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'context_menu_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ContextMenuItemOverride {

 ContextMenuVisibility get visibility; ContextMenuPin get pin;/// 仅在 [pin] 为 [ContextMenuPin.top] 时有意义：顶部那一排只画图标。
/// 其余档位解析器会忽略它，切走 pin 时也由编辑函数清掉。
 bool get iconOnly;
/// Create a copy of ContextMenuItemOverride
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextMenuItemOverrideCopyWith<ContextMenuItemOverride> get copyWith => _$ContextMenuItemOverrideCopyWithImpl<ContextMenuItemOverride>(this as ContextMenuItemOverride, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContextMenuItemOverride;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextMenuItemOverride&&(identical(other.visibility, _this.visibility) || other.visibility == _this.visibility)&&(identical(other.pin, _this.pin) || other.pin == _this.pin)&&(identical(other.iconOnly, _this.iconOnly) || other.iconOnly == _this.iconOnly));
}


@override
int get hashCode {
  final _this = this as ContextMenuItemOverride;
  return Object.hash(runtimeType,_this.visibility,_this.pin,_this.iconOnly);
}

@override
String toString() {
  final _this = this as ContextMenuItemOverride;
  return 'ContextMenuItemOverride(visibility: ${_this.visibility}, pin: ${_this.pin}, iconOnly: ${_this.iconOnly})';
}


}

/// @nodoc
abstract mixin class $ContextMenuItemOverrideCopyWith<$Res>  {
  factory $ContextMenuItemOverrideCopyWith(ContextMenuItemOverride value, $Res Function(ContextMenuItemOverride) _then) = _$ContextMenuItemOverrideCopyWithImpl;
@useResult
$Res call({
 ContextMenuVisibility visibility, ContextMenuPin pin, bool iconOnly
});




}
/// @nodoc
class _$ContextMenuItemOverrideCopyWithImpl<$Res>
    implements $ContextMenuItemOverrideCopyWith<$Res> {
  _$ContextMenuItemOverrideCopyWithImpl(this._self, this._then);

  final ContextMenuItemOverride _self;
  final $Res Function(ContextMenuItemOverride) _then;

/// Create a copy of ContextMenuItemOverride
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? visibility = null,Object? pin = null,Object? iconOnly = null,}) {
  return _then(ContextMenuItemOverride(
visibility: null == visibility ? _self.visibility : visibility // ignore: cast_nullable_to_non_nullable
as ContextMenuVisibility,pin: null == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as ContextMenuPin,iconOnly: null == iconOnly ? _self.iconOnly : iconOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ContextMenuItemOverride].
extension ContextMenuItemOverridePatterns on ContextMenuItemOverride {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextMenuItemOverride value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextMenuItemOverride() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextMenuItemOverride value)  $default,){
final _that = this;
switch (_that) {
case _ContextMenuItemOverride():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextMenuItemOverride value)?  $default,){
final _that = this;
switch (_that) {
case _ContextMenuItemOverride() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ContextMenuVisibility visibility,  ContextMenuPin pin,  bool iconOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextMenuItemOverride() when $default != null:
return $default(_that.visibility,_that.pin,_that.iconOnly);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ContextMenuVisibility visibility,  ContextMenuPin pin,  bool iconOnly)  $default,) {final _that = this;
switch (_that) {
case _ContextMenuItemOverride():
return $default(_that.visibility,_that.pin,_that.iconOnly);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ContextMenuVisibility visibility,  ContextMenuPin pin,  bool iconOnly)?  $default,) {final _that = this;
switch (_that) {
case _ContextMenuItemOverride() when $default != null:
return $default(_that.visibility,_that.pin,_that.iconOnly);case _:
  return null;

}
}

}

/// @nodoc


class _ContextMenuItemOverride extends ContextMenuItemOverride {
  const _ContextMenuItemOverride({this.visibility = ContextMenuVisibility.normal, this.pin = ContextMenuPin.none, this.iconOnly = false}): super._();
  

@override@JsonKey() final  ContextMenuVisibility visibility;
@override@JsonKey() final  ContextMenuPin pin;
/// 仅在 [pin] 为 [ContextMenuPin.top] 时有意义：顶部那一排只画图标。
/// 其余档位解析器会忽略它，切走 pin 时也由编辑函数清掉。
@override@JsonKey() final  bool iconOnly;

/// Create a copy of ContextMenuItemOverride
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextMenuItemOverrideCopyWith<_ContextMenuItemOverride> get copyWith => __$ContextMenuItemOverrideCopyWithImpl<_ContextMenuItemOverride>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextMenuItemOverride&&(identical(other.visibility, visibility) || other.visibility == visibility)&&(identical(other.pin, pin) || other.pin == pin)&&(identical(other.iconOnly, iconOnly) || other.iconOnly == iconOnly));
}


@override
int get hashCode {
    return Object.hash(runtimeType,visibility,pin,iconOnly);
}

@override
String toString() {
    return 'ContextMenuItemOverride(visibility: $visibility, pin: $pin, iconOnly: $iconOnly)';
}


}

/// @nodoc
abstract mixin class _$ContextMenuItemOverrideCopyWith<$Res> implements $ContextMenuItemOverrideCopyWith<$Res> {
  factory _$ContextMenuItemOverrideCopyWith(_ContextMenuItemOverride value, $Res Function(_ContextMenuItemOverride) _then) = __$ContextMenuItemOverrideCopyWithImpl;
@override @useResult
$Res call({
 ContextMenuVisibility visibility, ContextMenuPin pin, bool iconOnly
});




}
/// @nodoc
class __$ContextMenuItemOverrideCopyWithImpl<$Res>
    implements _$ContextMenuItemOverrideCopyWith<$Res> {
  __$ContextMenuItemOverrideCopyWithImpl(this._self, this._then);

  final _ContextMenuItemOverride _self;
  final $Res Function(_ContextMenuItemOverride) _then;

/// Create a copy of ContextMenuItemOverride
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? visibility = null,Object? pin = null,Object? iconOnly = null,}) {
  return _then(_ContextMenuItemOverride(
visibility: null == visibility ? _self.visibility : visibility // ignore: cast_nullable_to_non_nullable
as ContextMenuVisibility,pin: null == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as ContextMenuPin,iconOnly: null == iconOnly ? _self.iconOnly : iconOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ContextMenuScopeLayout {

/// 用户排过的完整次序；空 = 没排过 ⇒ 用 definition 的出厂次序。
/// 只装 `persistent == true` 的项；动态生成项（如「恢复隐藏卡 X」）不进这里。
 List<String> get order;/// 稀疏：只存被改过的项，未出现的项 = 全默认。
 Map<String, ContextMenuItemOverride> get overrides;
/// Create a copy of ContextMenuScopeLayout
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextMenuScopeLayoutCopyWith<ContextMenuScopeLayout> get copyWith => _$ContextMenuScopeLayoutCopyWithImpl<ContextMenuScopeLayout>(this as ContextMenuScopeLayout, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContextMenuScopeLayout;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextMenuScopeLayout&&const DeepCollectionEquality().equals(other.order, _this.order)&&const DeepCollectionEquality().equals(other.overrides, _this.overrides));
}


@override
int get hashCode {
  final _this = this as ContextMenuScopeLayout;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.order),const DeepCollectionEquality().hash(_this.overrides));
}

@override
String toString() {
  final _this = this as ContextMenuScopeLayout;
  return 'ContextMenuScopeLayout(order: ${_this.order}, overrides: ${_this.overrides})';
}


}

/// @nodoc
abstract mixin class $ContextMenuScopeLayoutCopyWith<$Res>  {
  factory $ContextMenuScopeLayoutCopyWith(ContextMenuScopeLayout value, $Res Function(ContextMenuScopeLayout) _then) = _$ContextMenuScopeLayoutCopyWithImpl;
@useResult
$Res call({
 List<String> order, Map<String, ContextMenuItemOverride> overrides
});




}
/// @nodoc
class _$ContextMenuScopeLayoutCopyWithImpl<$Res>
    implements $ContextMenuScopeLayoutCopyWith<$Res> {
  _$ContextMenuScopeLayoutCopyWithImpl(this._self, this._then);

  final ContextMenuScopeLayout _self;
  final $Res Function(ContextMenuScopeLayout) _then;

/// Create a copy of ContextMenuScopeLayout
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? order = null,Object? overrides = null,}) {
  return _then(ContextMenuScopeLayout(
order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as List<String>,overrides: null == overrides ? _self.overrides : overrides // ignore: cast_nullable_to_non_nullable
as Map<String, ContextMenuItemOverride>,
  ));
}

}


/// Adds pattern-matching-related methods to [ContextMenuScopeLayout].
extension ContextMenuScopeLayoutPatterns on ContextMenuScopeLayout {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextMenuScopeLayout value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextMenuScopeLayout() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextMenuScopeLayout value)  $default,){
final _that = this;
switch (_that) {
case _ContextMenuScopeLayout():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextMenuScopeLayout value)?  $default,){
final _that = this;
switch (_that) {
case _ContextMenuScopeLayout() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> order,  Map<String, ContextMenuItemOverride> overrides)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextMenuScopeLayout() when $default != null:
return $default(_that.order,_that.overrides);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> order,  Map<String, ContextMenuItemOverride> overrides)  $default,) {final _that = this;
switch (_that) {
case _ContextMenuScopeLayout():
return $default(_that.order,_that.overrides);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> order,  Map<String, ContextMenuItemOverride> overrides)?  $default,) {final _that = this;
switch (_that) {
case _ContextMenuScopeLayout() when $default != null:
return $default(_that.order,_that.overrides);case _:
  return null;

}
}

}

/// @nodoc


class _ContextMenuScopeLayout extends ContextMenuScopeLayout {
  const _ContextMenuScopeLayout({ List<String> order = const <String>[],  Map<String, ContextMenuItemOverride> overrides = const <String, ContextMenuItemOverride>{}}): _order = order,_overrides = overrides,super._();
  

/// 用户排过的完整次序；空 = 没排过 ⇒ 用 definition 的出厂次序。
/// 只装 `persistent == true` 的项；动态生成项（如「恢复隐藏卡 X」）不进这里。
 final  List<String> _order;
/// 用户排过的完整次序；空 = 没排过 ⇒ 用 definition 的出厂次序。
/// 只装 `persistent == true` 的项；动态生成项（如「恢复隐藏卡 X」）不进这里。
@override@JsonKey() List<String> get order {
  if (_order is EqualUnmodifiableListView) return _order;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_order);
}

/// 稀疏：只存被改过的项，未出现的项 = 全默认。
 final  Map<String, ContextMenuItemOverride> _overrides;
/// 稀疏：只存被改过的项，未出现的项 = 全默认。
@override@JsonKey() Map<String, ContextMenuItemOverride> get overrides {
  if (_overrides is EqualUnmodifiableMapView) return _overrides;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_overrides);
}


/// Create a copy of ContextMenuScopeLayout
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextMenuScopeLayoutCopyWith<_ContextMenuScopeLayout> get copyWith => __$ContextMenuScopeLayoutCopyWithImpl<_ContextMenuScopeLayout>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextMenuScopeLayout&&const DeepCollectionEquality().equals(other.order, _order)&&const DeepCollectionEquality().equals(other.overrides, _overrides));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_order),const DeepCollectionEquality().hash(_overrides));
}

@override
String toString() {
    return 'ContextMenuScopeLayout(order: $order, overrides: $overrides)';
}


}

/// @nodoc
abstract mixin class _$ContextMenuScopeLayoutCopyWith<$Res> implements $ContextMenuScopeLayoutCopyWith<$Res> {
  factory _$ContextMenuScopeLayoutCopyWith(_ContextMenuScopeLayout value, $Res Function(_ContextMenuScopeLayout) _then) = __$ContextMenuScopeLayoutCopyWithImpl;
@override @useResult
$Res call({
 List<String> order, Map<String, ContextMenuItemOverride> overrides
});




}
/// @nodoc
class __$ContextMenuScopeLayoutCopyWithImpl<$Res>
    implements _$ContextMenuScopeLayoutCopyWith<$Res> {
  __$ContextMenuScopeLayoutCopyWithImpl(this._self, this._then);

  final _ContextMenuScopeLayout _self;
  final $Res Function(_ContextMenuScopeLayout) _then;

/// Create a copy of ContextMenuScopeLayout
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? order = null,Object? overrides = null,}) {
  return _then(_ContextMenuScopeLayout(
order: null == order ? _self._order : order // ignore: cast_nullable_to_non_nullable
as List<String>,overrides: null == overrides ? _self._overrides : overrides // ignore: cast_nullable_to_non_nullable
as Map<String, ContextMenuItemOverride>,
  ));
}


}

// dart format on
