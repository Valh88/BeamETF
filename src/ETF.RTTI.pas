unit ETF.RTTI;

{
  RTTI-based mapper: TEtfTerm <-> TPersistent descendants.

  TEtfObjectMapper provides low-level mapping using TypInfo + Rtti units.
  TEtfMapper<T> is the generic facade.

  Mapping rules (Decode: TEtfMap → TObject):
    For each published property of the target class:
      1. Determine ETF key name: EtfFieldAttribute.FieldName or LowerCase(PropName)
      2. Skip if EtfIgnoreAttribute present
      3. Look up key in the ETF map (by atom name, then by binary/string value)
      4. If key missing:
           - raise EEtfMappingError if EtfRequiredAttribute present
           - leave default value otherwise
      5. Set property value based on Pascal type ↔ ETF term mapping:
           Integer/Int64/Word/... ← TEtfInteger
           Double/Single/Extended  ← TEtfFloat or TEtfInteger
           string                  ← TEtfBinary (UTF-8), TEtfString, TEtfAtom
           Boolean                 ← TEtfAtom (true/false)
           TObject descendant      ← TEtfMap (recursive)

  Mapping rules (Encode: TObject → TEtfMap):
    Symmetric: reads published properties → builds TEtfMap.
    For Elixir struct classes (EtfStructAttribute), adds __struct__ key.

  Usage:
    // Low-level (no generics):
    Obj := TEtfObjectMapper.MapFromTerm(TUser, MapTerm) as TUser;

    // Generic facade:
    User := TEtfMapper<TUser>.FromTerm(MapTerm);
    User := TEtfMapper<TUser>.Decode(EtfBytes);
    Term := TEtfMapper<TUser>.ToTerm(UserObj);
    Bytes := TEtfMapper<TUser>.Encode(UserObj);
}

{$mode objfpc}{$H+}
{$modeswitch prefixedattributes}

interface

uses
  Classes, SysUtils, TypInfo, Rtti,
  ETF.Types,
  ETF.Atom,
  ETF.Attributes,
  ETF.Struct,
  ETF.Decoder,
  ETF.Encoder;

type
  { Low-level object mapper (not generic, works with TClass) }
  TEtfObjectMapper = class
  private
    class procedure SetPropertyFromTerm(AObj: TObject; APropInfo: PPropInfo; ATerm: TEtfTerm);
    class function PropertyToTerm(AObj: TObject; APropInfo: PPropInfo): TEtfTerm;
    class function GetEtfKeyForProp(APropInfo: PPropInfo; AClass: TClass): string;
    class function FindTermInMap(AMap: TEtfMap; const AKey: string): TEtfTerm;
  public
    { Create and fill a new instance of AClass from an ETF map term.
      Caller owns the returned object. }
    class function MapFromTerm(AClass: TClass; ATerm: TEtfTerm): TObject;

    { Fill an existing object from an ETF map term }
    class procedure FillFromTerm(AObj: TObject; ATerm: TEtfTerm);

    { Build an ETF map term from a TObject's published properties.
      For classes with EtfStructAttribute, adds __struct__ key.
      Caller owns the returned term. }
    class function TermFromObject(AObj: TObject): TEtfMap;
  end;

  { Generic facade }
  generic TEtfMapper<T: TPersistent> = class
  public
    { Decode: bytes → T instance (caller owns result) }
    class function Decode(const ABytes: TBytes): T;

    { Decode from stream (caller owns result) }
    class function DecodeStream(AStream: TStream): T;

    { Map from already-decoded term (caller owns result) }
    class function FromTerm(ATerm: TEtfTerm): T;

    { Encode: T instance → bytes }
    class function Encode(AObj: T): TBytes;

    { Encode to stream }
    class procedure EncodeToStream(AObj: T; AStream: TStream);

    { Convert to term (caller owns result) }
    class function ToTerm(AObj: T): TEtfMap;
  end;

implementation

{ ------------------------------------------------------------------ }
{ Helpers                                                             }
{ ------------------------------------------------------------------ }

function EtfTermToString(ATerm: TEtfTerm): string;
begin
  if ATerm is TEtfBinary then
    Result := TEtfBinary(ATerm).AsUtf8String
  else if ATerm is TEtfString then
    Result := TEtfString(ATerm).Value
  else if ATerm is TEtfAtom then
    Result := TEtfAtom(ATerm).Value
  else
    Result := ATerm.AsString;
end;

{ ------------------------------------------------------------------ }
{ TEtfObjectMapper                                                    }
{ ------------------------------------------------------------------ }

class function TEtfObjectMapper.GetEtfKeyForProp(APropInfo: PPropInfo; AClass: TClass): string;
begin
  Result := TEtfAttributeHelper.GetFieldName(AClass, APropInfo);
end;

class function TEtfObjectMapper.FindTermInMap(AMap: TEtfMap; const AKey: string): TEtfTerm;
begin
  Result := AMap.GetByAtom(AKey);
  if Result = nil then
  begin
    { Try binary key with the same value }
    Result := AMap.GetByAtom(AKey);
  end;
end;

class procedure TEtfObjectMapper.SetPropertyFromTerm(
  AObj: TObject; APropInfo: PPropInfo; ATerm: TEtfTerm);
var
  PropKind: TTypeKind;
  StrVal: string;
  SubObj: TObject;
  SubMap: TEtfMap;
begin
  if ATerm = nil then Exit;
  PropKind := APropInfo^.PropType^.Kind;
  case PropKind of
    tkInteger, tkInt64:
    begin
      if ATerm is TEtfInteger then
        SetInt64Prop(AObj, APropInfo, TEtfInteger(ATerm).Value)
      else if ATerm is TEtfFloat then
        SetInt64Prop(AObj, APropInfo, Round(TEtfFloat(ATerm).Value));
    end;
    tkFloat:
    begin
      if ATerm is TEtfFloat then
        SetFloatProp(AObj, APropInfo, TEtfFloat(ATerm).Value)
      else if ATerm is TEtfInteger then
        SetFloatProp(AObj, APropInfo, TEtfInteger(ATerm).Value);
    end;
    tkBool:
    begin
      if (ATerm is TEtfAtom) then
      begin
        if TEtfAtom(ATerm).IsTrueAtom then
          SetOrdProp(AObj, APropInfo, 1)
        else if TEtfAtom(ATerm).IsFalseAtom then
          SetOrdProp(AObj, APropInfo, 0)
        else
          SetOrdProp(AObj, APropInfo, 0);
      end;
    end;
    tkSString, tkLString, tkAString, tkWString, tkUString:
    begin
      StrVal := EtfTermToString(ATerm);
      SetStrProp(AObj, APropInfo, StrVal);
    end;
    tkEnumeration:
    begin
      if APropInfo^.PropType = TypeInfo(Boolean) then
      begin
        if (ATerm is TEtfAtom) and TEtfAtom(ATerm).IsTrueAtom then
          SetOrdProp(AObj, APropInfo, 1)
        else
          SetOrdProp(AObj, APropInfo, 0);
      end
      else if ATerm is TEtfInteger then
        SetOrdProp(AObj, APropInfo, TEtfInteger(ATerm).Value)
      else if ATerm is TEtfAtom then
      begin
        { Try to map atom name to enum ordinal }
        SetOrdProp(AObj, APropInfo,
          GetEnumValue(APropInfo^.PropType, TEtfAtom(ATerm).Value));
      end;
    end;
    tkClass:
    begin
      { Nested object: must be a TEtfMap }
      if ATerm is TEtfMap then
      begin
        SubMap := TEtfMap(ATerm);
        SubObj := GetObjectProp(AObj, APropInfo);
        if SubObj = nil then
        begin
          SubObj := GetTypeData(APropInfo^.PropType)^.ClassType.Create;
          SetObjectProp(AObj, APropInfo, SubObj);
        end;
        FillFromTerm(SubObj, SubMap);
      end;
    end;
  end;
end;

class function TEtfObjectMapper.PropertyToTerm(
  AObj: TObject; APropInfo: PPropInfo): TEtfTerm;
var
  PropKind: TTypeKind;
  SubObj: TObject;
  IsAtomProp: Boolean;
  StrVal: string;
  StrBytes: TBytes;
begin
  Result := nil;
  IsAtomProp := TEtfAttributeHelper.IsAsAtom(AObj.ClassType, APropInfo);

  PropKind := APropInfo^.PropType^.Kind;
  case PropKind of
    tkInteger, tkInt64:
      Result := TEtfInteger.Create(GetInt64Prop(AObj, APropInfo));
    tkFloat:
      Result := TEtfFloat.Create(GetFloatProp(AObj, APropInfo));
    tkBool:
    begin
      if GetOrdProp(AObj, APropInfo) <> 0 then
        Result := TEtfAtom.Create(ATOM_TRUE)
      else
        Result := TEtfAtom.Create(ATOM_FALSE);
    end;
    tkEnumeration:
    begin
      if APropInfo^.PropType = TypeInfo(Boolean) then
      begin
        if GetOrdProp(AObj, APropInfo) <> 0 then
          Result := TEtfAtom.Create(ATOM_TRUE)
        else
          Result := TEtfAtom.Create(ATOM_FALSE);
      end
      else
      begin
        { Encode enum as atom by name }
        Result := TEtfAtom.Create(
          GetEnumName(APropInfo^.PropType, GetOrdProp(AObj, APropInfo)));
      end;
    end;
    tkSString, tkLString, tkAString, tkWString, tkUString:
    begin
      if IsAtomProp then
        Result := TEtfAtom.Create(GetStrProp(AObj, APropInfo))
      else
      begin
        { Default: encode string as binary (UTF-8), matching Elixir convention }
        StrVal := GetStrProp(AObj, APropInfo);
        SetLength(StrBytes, Length(StrVal));
        if Length(StrVal) > 0 then
          Move(StrVal[1], StrBytes[0], Length(StrVal));
        Result := TEtfBinary.Create(StrBytes);
      end;
    end;
    tkClass:
    begin
      SubObj := GetObjectProp(AObj, APropInfo);
      if SubObj <> nil then
        Result := TermFromObject(SubObj)
      else
        Result := TEtfAtom.Create(ATOM_NIL);
    end;
  end;
end;

class function TEtfObjectMapper.MapFromTerm(AClass: TClass; ATerm: TEtfTerm): TObject;
begin
  Result := AClass.Create;
  try
    FillFromTerm(Result, ATerm);
  except
    Result.Free;
    raise;
  end;
end;

class procedure TEtfObjectMapper.FillFromTerm(AObj: TObject; ATerm: TEtfTerm);
var
  Map: TEtfMap;
  PropList: PPropList;
  PropCount: Integer;
  I: Integer;
  PropInfo: PPropInfo;
  Key: string;
  Val: TEtfTerm;
begin
  if not (ATerm is TEtfMap) then
    raise EEtfMappingError.CreateFmt(
      'Cannot fill %s from a non-map ETF term (%s)',
      [AObj.ClassName, ATerm.ClassName]);

  Map := TEtfMap(ATerm);
  PropCount := GetPropList(AObj.ClassInfo, tkAny, nil);
  if PropCount <= 0 then Exit;

  GetMem(PropList, PropCount * SizeOf(Pointer));
  try
    GetPropList(AObj.ClassInfo, tkAny, PropList);
    for I := 0 to PropCount - 1 do
    begin
      PropInfo := PropList^[I];
      if PropInfo^.PropType^.Kind = tkMethod then Continue;

      if TEtfAttributeHelper.IsIgnored(AObj.ClassType, PropInfo) then Continue;

      Key := GetEtfKeyForProp(PropInfo, AObj.ClassType);
      Val := FindTermInMap(Map, Key);

      if Val = nil then
      begin
        if TEtfAttributeHelper.IsRequired(AObj.ClassType, PropInfo) then
          raise EEtfMappingError.CreateFmt(
            'Required ETF key "%s" missing when filling %s.%s',
            [Key, AObj.ClassName, string(PropInfo^.Name)]);
        Continue;
      end;

      SetPropertyFromTerm(AObj, PropInfo, Val);
    end;
  finally
    FreeMem(PropList);
  end;
end;

class function TEtfObjectMapper.TermFromObject(AObj: TObject): TEtfMap;
var
  Map: TEtfMap;
  PropList: PPropList;
  PropCount: Integer;
  I: Integer;
  PropInfo: PPropInfo;
  Key: string;
  Val: TEtfTerm;
  StructName: string;
begin
  StructName := TEtfAttributeHelper.GetStructName(AObj.ClassType);

  if StructName <> '' then
    Map := TEtfElixirStruct.Create(StructName)
  else
    Map := TEtfMap.Create;

  try
    { For Elixir structs, add __struct__ key first }
    if StructName <> '' then
      Map.Put(TEtfAtom.Create(ATOM_STRUCT), TEtfAtom.Create(StructName));

    PropCount := GetPropList(AObj.ClassInfo, tkAny, nil);
    if PropCount > 0 then
    begin
      GetMem(PropList, PropCount * SizeOf(Pointer));
      try
        GetPropList(AObj.ClassInfo, tkAny, PropList);
        for I := 0 to PropCount - 1 do
        begin
          PropInfo := PropList^[I];
          if PropInfo^.PropType^.Kind = tkMethod then Continue;

          if TEtfAttributeHelper.IsIgnored(AObj.ClassType, PropInfo) then Continue;

          Key := GetEtfKeyForProp(PropInfo, AObj.ClassType);
          Val := PropertyToTerm(AObj, PropInfo);
          if Val <> nil then
            Map.Put(TEtfAtom.Create(Key), Val);
        end;
      finally
        FreeMem(PropList);
      end;
    end;
  except
    Map.Free;
    raise;
  end;
  Result := Map;
end;

{ ------------------------------------------------------------------ }
{ TEtfMapper<T>                                                       }
{ ------------------------------------------------------------------ }

class function TEtfMapper.Decode(const ABytes: TBytes): T;
var
  Term: TEtfTerm;
begin
  Term := TEtfDecoder.Decode(ABytes);
  try
    Result := FromTerm(Term);
  finally
    Term.Free;
  end;
end;

class function TEtfMapper.DecodeStream(AStream: TStream): T;
var
  Term: TEtfTerm;
begin
  Term := TEtfDecoder.DecodeStream(AStream);
  try
    Result := FromTerm(Term);
  finally
    Term.Free;
  end;
end;

class function TEtfMapper.FromTerm(ATerm: TEtfTerm): T;
begin
  Result := T(TEtfObjectMapper.MapFromTerm(T, ATerm));
end;

class function TEtfMapper.Encode(AObj: T): TBytes;
var
  Term: TEtfMap;
begin
  Term := ToTerm(AObj);
  try
    Result := TEtfEncoder.EncodeToBytes(Term);
  finally
    Term.Free;
  end;
end;

class procedure TEtfMapper.EncodeToStream(AObj: T; AStream: TStream);
var
  Term: TEtfMap;
begin
  Term := ToTerm(AObj);
  try
    TEtfEncoder.EncodeToStream(Term, AStream);
  finally
    Term.Free;
  end;
end;

class function TEtfMapper.ToTerm(AObj: T): TEtfMap;
begin
  Result := TEtfObjectMapper.TermFromObject(AObj);
end;

end.
