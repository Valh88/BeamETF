unit ETF.RecordMap;

{
  Stack-friendly ETF mapper for Pascal record types.

  TEtfRecordMapper<T> maps an ETF map term directly into a Pascal record
  (value type) without any heap allocation for the target value.
  The record lives wherever the caller puts it: on the stack, inside
  another record, in a static array, etc.

  REQUIREMENTS for the record type T:
    1. Expose RTTI fields via the directive placed *before* the record:
         {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
       or use {$mode delphi} which enables it by default.
    2. Use EtfField / EtfIgnore / EtfRequired attributes on fields
       (same attributes as for TEtfMapper<TClass>).

  Example:

    type
      {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
      TUserRecord = record
        [EtfField('id')]    [EtfRequired]
        Id: Integer;
        [EtfField('name')]
        Name: string;
        [EtfField('active')]
        Active: Boolean;
        [EtfField('score')]
        Score: Double;
      end;

    var
      U: TUserRecord;
    begin
      // Decode directly into a stack variable — zero heap allocation:
      TEtfRecordMapper<TUserRecord>.FillFromTerm(U, MapTerm);
      // or in one shot:
      U := TEtfRecordMapper<TUserRecord>.FromTerm(MapTerm);
      U := TEtfRecordMapper<TUserRecord>.Decode(EtfBytes);

      // Encode back:
      Bytes := TEtfRecordMapper<TUserRecord>.Encode(U);
      Term  := TEtfRecordMapper<TUserRecord>.ToTerm(U);   // caller owns term
    end;

  Field-type mapping (decode):
    Integer/Int64/Word/Byte/...  ← TEtfInteger
    Double/Single/Extended       ← TEtfFloat  (or TEtfInteger)
    Boolean                      ← TEtfAtom  (true / false)
    string                       ← TEtfBinary (UTF-8), TEtfString, TEtfAtom
    enum                         ← TEtfAtom  (enum name) or TEtfInteger

  Field-type mapping (encode):
    Integer/Int64                → SMALL_INTEGER_EXT / INTEGER_EXT / SMALL_BIG_EXT
    Double/Single/Extended       → NEW_FLOAT_EXT
    Boolean                      → SMALL_ATOM_UTF8_EXT  ('true' / 'false')
    string  (default)            → BINARY_EXT  (UTF-8)
    string  + [EtfAsAtom]        → SMALL_ATOM_UTF8_EXT
    enum                         → SMALL_ATOM_UTF8_EXT  (enum name)
}

{$mode delphi}

interface

uses
  Classes, SysUtils, TypInfo, Rtti,
  ETF.Types,
  ETF.Atom,
  ETF.Attributes,
  ETF.Decoder,
  ETF.Encoder;

type
  { Low-level mapper: works with a raw pointer to the record + TypeInfo }
  TEtfRawRecordMapper = class
  private
    class function EtfFieldName(AField: TRttiField): string;
    class function IsIgnored(AField: TRttiField): Boolean;
    class function IsRequired(AField: TRttiField): Boolean;
    class function IsAsAtom(AField: TRttiField): Boolean;
    class function TermToTValue(ATerm: TEtfTerm; AKind: TTypeKind;
      ATypeInfo: PTypeInfo): TValue;
    class function TValueToTerm(const AVal: TValue; AField: TRttiField): TEtfTerm;
  public
    { Fill record at AData from an ETF map term.
      ATypeInfo must be TypeInfo(TYourRecord). }
    class procedure FillFromTerm(AData: Pointer; ATypeInfo: PTypeInfo;
      ATerm: TEtfTerm);

    { Build an ETF map from a record.
      AStructName: if non-empty, adds __struct__ key (Elixir struct). }
    class function TermFromRecord(AData: Pointer; ATypeInfo: PTypeInfo;
      const AStructName: string = ''): TEtfMap;
  end;

  { Generic facade — T must be a record type }
  TEtfRecordMapper<T> = class
  public
    { Fill an existing record variable from an ETF map term (no allocation) }
    class procedure FillFromTerm(var ARec: T; ATerm: TEtfTerm);

    { Create a new record value from an ETF map term }
    class function FromTerm(ATerm: TEtfTerm): T;

    { Decode ETF bytes → record value }
    class function Decode(const ABytes: TBytes): T;

    { Decode from stream → record value }
    class function DecodeStream(AStream: TStream): T;

    { Encode record → ETF bytes }
    class function Encode(const ARec: T): TBytes;

    { Encode record → stream }
    class procedure EncodeToStream(const ARec: T; AStream: TStream);

    { Build an ETF map term from a record.
      Pass AStructName to produce an Elixir struct map with __struct__ key. }
    class function ToTerm(const ARec: T;
      const AStructName: string = ''): TEtfMap;
  end;

implementation

{ ------------------------------------------------------------------ }
{ Helpers                                                             }
{ ------------------------------------------------------------------ }

function TermToUtf8String(ATerm: TEtfTerm): string;
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
{ TEtfRawRecordMapper                                                 }
{ ------------------------------------------------------------------ }

class function TEtfRawRecordMapper.EtfFieldName(AField: TRttiField): string;
var
  Attr: TCustomAttribute;
begin
  Result := LowerCase(AField.Name);
  for Attr in AField.GetAttributes do
    if Attr is EtfFieldAttribute then
    begin
      Result := EtfFieldAttribute(Attr).FieldName;
      Exit;
    end;
end;

class function TEtfRawRecordMapper.IsIgnored(AField: TRttiField): Boolean;
var
  Attr: TCustomAttribute;
begin
  for Attr in AField.GetAttributes do
    if Attr is EtfIgnoreAttribute then Exit(True);
  Result := False;
end;

class function TEtfRawRecordMapper.IsRequired(AField: TRttiField): Boolean;
var
  Attr: TCustomAttribute;
begin
  for Attr in AField.GetAttributes do
    if Attr is EtfRequiredAttribute then Exit(True);
  Result := False;
end;

class function TEtfRawRecordMapper.IsAsAtom(AField: TRttiField): Boolean;
var
  Attr: TCustomAttribute;
begin
  for Attr in AField.GetAttributes do
    if Attr is EtfAsAtomAttribute then Exit(True);
  Result := False;
end;

class function TEtfRawRecordMapper.TermToTValue(ATerm: TEtfTerm;
  AKind: TTypeKind; ATypeInfo: PTypeInfo): TValue;
var
  IVal: Int64;
  FVal: Double;
  SVal: string;
  BVal: Boolean;
  EOrd: Integer;
begin
  case AKind of
    tkInteger, tkInt64:
    begin
      if ATerm is TEtfInteger then
        IVal := TEtfInteger(ATerm).Value
      else if ATerm is TEtfFloat then
        IVal := Round(TEtfFloat(ATerm).Value)
      else
        IVal := 0;
      case GetTypeData(ATypeInfo)^.OrdType of
        otSByte:  Result := TValue.From<ShortInt>(IVal);
        otUByte:  Result := TValue.From<Byte>(IVal);
        otSWord:  Result := TValue.From<SmallInt>(IVal);
        otUWord:  Result := TValue.From<Word>(IVal);
        otSLong:  Result := TValue.From<Integer>(IVal);
        otULong:  Result := TValue.From<Cardinal>(IVal);
      else
        Result := TValue.From<Int64>(IVal);
      end;
      if AKind = tkInt64 then
        Result := TValue.From<Int64>(IVal);
    end;
    tkFloat:
    begin
      if ATerm is TEtfFloat then
        FVal := TEtfFloat(ATerm).Value
      else if ATerm is TEtfInteger then
        FVal := TEtfInteger(ATerm).Value
      else
        FVal := 0;
      case GetTypeData(ATypeInfo)^.FloatType of
        ftSingle:   Result := TValue.From<Single>(FVal);
        ftExtended: Result := TValue.From<Extended>(FVal);
      else
        Result := TValue.From<Double>(FVal);
      end;
    end;
    tkBool:
    begin
      if ATerm is TEtfAtom then
        BVal := TEtfAtom(ATerm).IsTrueAtom
      else
        BVal := False;
      Result := TValue.From<Boolean>(BVal);
    end;
    tkEnumeration:
    begin
      if ATypeInfo = TypeInfo(Boolean) then
      begin
        BVal := (ATerm is TEtfAtom) and TEtfAtom(ATerm).IsTrueAtom;
        Result := TValue.From<Boolean>(BVal);
      end
      else
      begin
        if ATerm is TEtfAtom then
          EOrd := GetEnumValue(ATypeInfo, TEtfAtom(ATerm).Value)
        else if ATerm is TEtfInteger then
          EOrd := TEtfInteger(ATerm).Value
        else
          EOrd := 0;
        TValue.Make(@EOrd, ATypeInfo, Result);
      end;
    end;
    tkSString, tkLString, tkAString, tkWString, tkUString:
    begin
      SVal := TermToUtf8String(ATerm);
      Result := TValue.From<string>(SVal);
    end;
  else
    { Unknown kind — leave zero/empty }
    TValue.Make(nil, ATypeInfo, Result);
  end;
end;

class function TEtfRawRecordMapper.TValueToTerm(const AVal: TValue;
  AField: TRttiField): TEtfTerm;
var
  SVal: string;
  SBytes: TBytes;
begin
  Result := nil;
  case AVal.Kind of
    tkInteger, tkInt64:
      Result := TEtfInteger.Create(AVal.AsInt64);
    tkFloat:
      Result := TEtfFloat.Create(AVal.AsExtended);
    tkBool:
    begin
      if AVal.AsBoolean then
        Result := TEtfAtom.Create(ATOM_TRUE)
      else
        Result := TEtfAtom.Create(ATOM_FALSE);
    end;
    tkEnumeration:
    begin
      if AVal.TypeInfo = TypeInfo(Boolean) then
      begin
        if AVal.AsBoolean then
          Result := TEtfAtom.Create(ATOM_TRUE)
        else
          Result := TEtfAtom.Create(ATOM_FALSE);
      end
      else
        { Encode enum as atom (name) }
        Result := TEtfAtom.Create(
          GetEnumName(AVal.TypeInfo, AVal.AsOrdinal));
    end;
    tkSString, tkLString, tkAString, tkWString, tkUString:
    begin
      SVal := AVal.AsString;
      if IsAsAtom(AField) then
        Result := TEtfAtom.Create(SVal)
      else
      begin
        SetLength(SBytes, Length(SVal));
        if Length(SVal) > 0 then
          Move(SVal[1], SBytes[0], Length(SVal));
        Result := TEtfBinary.Create(SBytes);
      end;
    end;
  end;
end;

class procedure TEtfRawRecordMapper.FillFromTerm(AData: Pointer;
  ATypeInfo: PTypeInfo; ATerm: TEtfTerm);
var
  Ctx: TRttiContext;
  RT: TRttiRecordType;
  RF: TRttiField;
  Map: TEtfMap;
  Key: string;
  ValTerm: TEtfTerm;
  TVal: TValue;
begin
  if not (ATerm is TEtfMap) then
    raise EEtfMappingError.CreateFmt(
      'Cannot fill record from non-map ETF term (%s)', [ATerm.ClassName]);

  Map := TEtfMap(ATerm);
  Ctx := TRttiContext.Create;
  try
    RT := Ctx.GetType(ATypeInfo).AsRecord;
    if RT = nil then
      raise EEtfMappingError.CreateFmt(
        'Type "%s" is not a record or has no RTTI. Add ' +
        '{$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])} before the record declaration.',
        [string(ATypeInfo^.Name)]);

    for RF in RT.GetFields do
    begin
      if IsIgnored(RF) then Continue;

      Key := EtfFieldName(RF);
      ValTerm := Map.GetByAtom(Key);

      if ValTerm = nil then
      begin
        if IsRequired(RF) then
          raise EEtfMappingError.CreateFmt(
            'Required ETF key "%s" missing for record field %s.%s',
            [Key, string(ATypeInfo^.Name), RF.Name]);
        Continue;
      end;

      TVal := TermToTValue(ValTerm, RF.FieldType.TypeKind, RF.FieldType.Handle);
      RF.SetValue(AData, TVal);
    end;
  finally
    Ctx.Free;
  end;
end;

class function TEtfRawRecordMapper.TermFromRecord(AData: Pointer;
  ATypeInfo: PTypeInfo; const AStructName: string): TEtfMap;
var
  Ctx: TRttiContext;
  RT: TRttiRecordType;
  RF: TRttiField;
  Map: TEtfMap;
  Key: string;
  TVal: TValue;
  ETerm: TEtfTerm;
begin
  if AStructName <> '' then
    Map := TEtfElixirStruct.Create(AStructName)
  else
    Map := TEtfMap.Create;

  try
    if AStructName <> '' then
      Map.Put(TEtfAtom.Create(ATOM_STRUCT), TEtfAtom.Create(AStructName));

    Ctx := TRttiContext.Create;
    try
      RT := Ctx.GetType(ATypeInfo).AsRecord;
      if RT = nil then
        raise EEtfMappingError.CreateFmt(
          'Type "%s" is not a record or has no RTTI.',
          [string(ATypeInfo^.Name)]);

      for RF in RT.GetFields do
      begin
        if IsIgnored(RF) then Continue;
        Key := EtfFieldName(RF);
        TVal := RF.GetValue(AData);
        ETerm := TValueToTerm(TVal, RF);
        if ETerm <> nil then
          Map.Put(TEtfAtom.Create(Key), ETerm);
      end;
    finally
      Ctx.Free;
    end;
  except
    Map.Free;
    raise;
  end;
  Result := Map;
end;

{ ------------------------------------------------------------------ }
{ TEtfRecordMapper<T>                                                 }
{ ------------------------------------------------------------------ }

class procedure TEtfRecordMapper<T>.FillFromTerm(var ARec: T; ATerm: TEtfTerm);
begin
  TEtfRawRecordMapper.FillFromTerm(@ARec, TypeInfo(T), ATerm);
end;

class function TEtfRecordMapper<T>.FromTerm(ATerm: TEtfTerm): T;
begin
  FillChar(Result, SizeOf(T), 0);
  FillFromTerm(Result, ATerm);
end;

class function TEtfRecordMapper<T>.Decode(const ABytes: TBytes): T;
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

class function TEtfRecordMapper<T>.DecodeStream(AStream: TStream): T;
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

class function TEtfRecordMapper<T>.Encode(const ARec: T): TBytes;
var
  Term: TEtfMap;
begin
  Term := ToTerm(ARec);
  try
    Result := TEtfEncoder.EncodeToBytes(Term);
  finally
    Term.Free;
  end;
end;

class procedure TEtfRecordMapper<T>.EncodeToStream(const ARec: T; AStream: TStream);
var
  Term: TEtfMap;
begin
  Term := ToTerm(ARec);
  try
    TEtfEncoder.EncodeToStream(Term, AStream);
  finally
    Term.Free;
  end;
end;

class function TEtfRecordMapper<T>.ToTerm(const ARec: T;
  const AStructName: string): TEtfMap;
begin
  Result := TEtfRawRecordMapper.TermFromRecord(@ARec, TypeInfo(T), AStructName);
end;

end.
