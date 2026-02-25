unit ETF.Attributes;

{
  Custom RTTI attributes for ETF mapping.

  These attributes annotate published properties of TPersistent descendants
  to control how they map to/from ETF terms.

  FPC 3.2+ supports custom attributes via TCustomAttribute.  The Rtti unit
  provides TRttiContext which can enumerate class attributes and property
  attributes.

  IMPORTANT: property attributes in FPC RTTI are fetched via
    TRttiInstanceType.GetProperty(name).GetAttributes
  NOT via the property's PropType (that is the type of the value, not the
  attribute container).

  Usage example:

    type
      [EtfStruct('Elixir.MyApp.User')]
      TUser = class(TPersistent)
      private
        FId: Integer;
        FName: string;
        FEmail: string;
        FInternal: string;
      published
        [EtfField('id')]
        [EtfRequired]
        property Id: Integer read FId write FId;

        [EtfField('name')]
        property Name: string read FName write FName;

        [EtfIgnore]
        property Internal: string read FInternal write FInternal;
      end;

  Helper usage:
    TEtfAttributeHelper.GetFieldName(AClass, PropInfo)  → 'id'
    TEtfAttributeHelper.IsIgnored(AClass, PropInfo)     → True/False
    TEtfAttributeHelper.IsRequired(AClass, PropInfo)    → True/False
    TEtfAttributeHelper.GetStructName(AClass)           → 'Elixir.MyApp.User'
}

{$mode objfpc}{$H+}
{$modeswitch prefixedattributes}

interface

uses
  Classes, SysUtils, TypInfo, Rtti;

type
  { Maps a published property to a specific ETF map key (atom name).
    If absent, LowerCase(property name) is used as the default. }
  EtfFieldAttribute = class(TCustomAttribute)
  private
    FFieldName: string;
  public
    constructor Create(const AFieldName: string);
    property FieldName: string read FFieldName;
  end;

  { Exclude this property from ETF encoding/decoding entirely. }
  EtfIgnoreAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  { Raise EEtfMappingError during decoding if this key is absent in the map. }
  EtfRequiredAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  { Marks a TPersistent subclass or a record type as the Pascal representation
    of a named Elixir struct.  The name is the fully-qualified Elixir module,
    e.g. 'Elixir.MyApp.User'.  On classes, TEtfStructRegistry.Register reads it.
    On records, TEtfRecordMapper uses it when encoding (adds __struct__ key). }
  EtfStructAttribute = class(TCustomAttribute)
  private
    FStructName: string;
  public
    constructor Create(const AStructName: string);
    property StructName: string read FStructName;
  end;

  { Hint: encode/decode this property as BINARY_EXT even when it is a string. }
  EtfAsBinaryAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  { Hint: this string property should be encoded as an atom (SMALL_ATOM_UTF8_EXT). }
  EtfAsAtomAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  { ------------------------------------------------------------------ }
  { Runtime helper — inspects RTTI attributes via TRttiContext           }
  { NOTE: all helpers require the *owning class* (AClass) because        }
  { property attributes are stored on the class type, not the value type.}
  { ------------------------------------------------------------------ }
  TEtfAttributeHelper = class
  private
    class function FindRttiProperty(AClass: TClass; const APropName: string): TRttiProperty;
  public
    { ETF field name for the property:
        1. EtfFieldAttribute.FieldName if present
        2. LowerCase(PropInfo^.Name) otherwise }
    class function GetFieldName(AClass: TClass; APropInfo: PPropInfo): string;

    { True if EtfIgnoreAttribute is on the property }
    class function IsIgnored(AClass: TClass; APropInfo: PPropInfo): Boolean;

    { True if EtfRequiredAttribute is on the property }
    class function IsRequired(AClass: TClass; APropInfo: PPropInfo): Boolean;

    { True if EtfAsBinaryAttribute is on the property }
    class function IsAsBinary(AClass: TClass; APropInfo: PPropInfo): Boolean;

    { True if EtfAsAtomAttribute is on the property }
    class function IsAsAtom(AClass: TClass; APropInfo: PPropInfo): Boolean;

    { EtfStruct name for AClass, or '' if not annotated }
    class function GetStructName(AClass: TClass): string;

    { EtfStruct name for a type (e.g. record), or '' if not annotated.
      Use for record types: [EtfStruct('Elixir.Address')] on the record. }
    class function GetStructNameForType(ATypeInfo: PTypeInfo): string;

    { True if the class has an EtfStructAttribute }
    class function HasStructAttribute(AClass: TClass): Boolean;
  end;

implementation

{ EtfFieldAttribute }

constructor EtfFieldAttribute.Create(const AFieldName: string);
begin
  inherited Create;
  FFieldName := AFieldName;
end;

{ EtfIgnoreAttribute }

constructor EtfIgnoreAttribute.Create;
begin
  inherited Create;
end;

{ EtfRequiredAttribute }

constructor EtfRequiredAttribute.Create;
begin
  inherited Create;
end;

{ EtfStructAttribute }

constructor EtfStructAttribute.Create(const AStructName: string);
begin
  inherited Create;
  FStructName := AStructName;
end;

{ EtfAsBinaryAttribute }

constructor EtfAsBinaryAttribute.Create;
begin
  inherited Create;
end;

{ EtfAsAtomAttribute }

constructor EtfAsAtomAttribute.Create;
begin
  inherited Create;
end;

{ TEtfAttributeHelper }

class function TEtfAttributeHelper.FindRttiProperty(
  AClass: TClass; const APropName: string): TRttiProperty;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  LowName: string;
begin
  Result := nil;
  LowName := LowerCase(APropName);
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        Result := Prop;
        Exit;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.GetFieldName(
  AClass: TClass; APropInfo: PPropInfo): string;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  LowName: string;
begin
  Result := LowerCase(string(APropInfo^.Name));
  LowName := Result;
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        for Attr in Prop.GetAttributes do
          if Attr is EtfFieldAttribute then
          begin
            Result := EtfFieldAttribute(Attr).FieldName;
            Exit;
          end;
        Break;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.IsIgnored(
  AClass: TClass; APropInfo: PPropInfo): Boolean;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  LowName: string;
begin
  Result := False;
  LowName := LowerCase(string(APropInfo^.Name));
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        for Attr in Prop.GetAttributes do
          if Attr is EtfIgnoreAttribute then Exit(True);
        Break;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.IsRequired(
  AClass: TClass; APropInfo: PPropInfo): Boolean;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  LowName: string;
begin
  Result := False;
  LowName := LowerCase(string(APropInfo^.Name));
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        for Attr in Prop.GetAttributes do
          if Attr is EtfRequiredAttribute then Exit(True);
        Break;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.IsAsBinary(
  AClass: TClass; APropInfo: PPropInfo): Boolean;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  LowName: string;
begin
  Result := False;
  LowName := LowerCase(string(APropInfo^.Name));
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        for Attr in Prop.GetAttributes do
          if Attr is EtfAsBinaryAttribute then Exit(True);
        Break;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.IsAsAtom(
  AClass: TClass; APropInfo: PPropInfo): Boolean;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  LowName: string;
begin
  Result := False;
  LowName := LowerCase(string(APropInfo^.Name));
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Prop in RttiType.GetProperties do
      if LowerCase(Prop.Name) = LowName then
      begin
        for Attr in Prop.GetAttributes do
          if Attr is EtfAsAtomAttribute then Exit(True);
        Break;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.GetStructName(AClass: TClass): string;
var
  Ctx: TRttiContext;
  RttiType: TRttiInstanceType;
  Attr: TCustomAttribute;
begin
  Result := '';
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(AClass) as TRttiInstanceType;
    if RttiType = nil then Exit;
    for Attr in RttiType.GetAttributes do
      if Attr is EtfStructAttribute then
      begin
        Result := EtfStructAttribute(Attr).StructName;
        Exit;
      end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfAttributeHelper.HasStructAttribute(AClass: TClass): Boolean;
begin
  Result := GetStructName(AClass) <> '';
end;

class function TEtfAttributeHelper.GetStructNameForType(ATypeInfo: PTypeInfo): string;
var
  Ctx: TRttiContext;
  RttiType: TRttiType;
  Attr: TCustomAttribute;
begin
  Result := '';
  if ATypeInfo = nil then Exit;
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(ATypeInfo);
    if RttiType = nil then Exit;
    for Attr in RttiType.GetAttributes do
      if Attr is EtfStructAttribute then
      begin
        Result := EtfStructAttribute(Attr).StructName;
        Exit;
      end;
  finally
    Ctx.Free;
  end;
end;

end.
