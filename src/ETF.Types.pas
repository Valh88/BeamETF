unit ETF.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections;

const
  ETF_VERSION = 131;

  { ETF tag constants (Erlang External Term Format) }
  TAG_ATOM_CACHE_REF        = 82;
  TAG_SMALL_INTEGER_EXT     = 97;
  TAG_INTEGER_EXT           = 98;
  TAG_FLOAT_EXT             = 99;   { old float, 31-byte string }
  TAG_ATOM_EXT              = 100;
  TAG_REFERENCE_EXT         = 101;
  TAG_PORT_EXT              = 102;
  TAG_PID_EXT               = 103;
  TAG_SMALL_TUPLE_EXT       = 104;
  TAG_LARGE_TUPLE_EXT       = 105;
  TAG_NIL_EXT               = 106;
  TAG_STRING_EXT            = 107;
  TAG_LIST_EXT              = 108;
  TAG_BINARY_EXT            = 109;
  TAG_SMALL_BIG_EXT         = 110;
  TAG_LARGE_BIG_EXT         = 111;
  TAG_NEW_FUN_EXT           = 112;
  TAG_EXPORT_EXT            = 113;
  TAG_NEW_REFERENCE_EXT     = 114;
  TAG_SMALL_ATOM_EXT        = 115;
  TAG_MAP_EXT               = 116;
  TAG_FUN_EXT               = 117;
  TAG_ATOM_UTF8_EXT         = 118;
  TAG_SMALL_ATOM_UTF8_EXT   = 119;
  TAG_V4_PORT_EXT           = 120;
  TAG_NEW_PID_EXT           = 88;   { 'X' }
  TAG_NEW_PORT_EXT          = 89;   { 'Y' }
  TAG_NEWER_REFERENCE_EXT   = 90;   { 'Z' }
  TAG_NEW_FLOAT_EXT         = 70;   { 'F' }
  TAG_BIT_BINARY_EXT        = 77;   { 'M' }
  TAG_LOCAL_EXT             = 121;

  { Well-known Elixir/Erlang atoms }
  ATOM_NIL        = 'nil';
  ATOM_TRUE       = 'true';
  ATOM_FALSE      = 'false';
  ATOM_UNDEFINED  = 'undefined';
  ATOM_STRUCT     = '__struct__';
  ATOM_OK         = 'ok';
  ATOM_ERROR      = 'error';

type
  TEtfTermKind = (
    etkInteger,
    etkFloat,
    etkAtom,
    etkBinary,
    etkString,
    etkList,
    etkImproperList,
    etkTuple,
    etkMap,
    etkElixirStruct,
    etkPid,
    etkPort,
    etkReference,
    etkFun,
    etkNil   { the [] empty list atom, not Elixir nil }
  );

  TEtfException = class(Exception);
  EEtfDecodeError = class(TEtfException);
  EEtfEncodeError = class(TEtfException);
  EEtfMappingError = class(TEtfException);

  { Forward declarations }
  TEtfTerm = class;
  TEtfAtom = class;
  TEtfInteger = class;
  TEtfFloat = class;
  TEtfBinary = class;
  TEtfString = class;
  TEtfList = class;
  TEtfImproperList = class;
  TEtfTuple = class;
  TEtfMap = class;
  TEtfElixirStruct = class;
  TEtfPid = class;
  TEtfPort = class;
  TEtfReference = class;
  TEtfFun = class;

  TEtfTermList  = specialize TObjectList<TEtfTerm>;
  TEtfTermArray = array of TEtfTerm;

  { Base class for all ETF terms. Owns its children by default. }
  TEtfTerm = class
  private
    FOwned: Boolean;  { if True, Free is safe to call }
  public
    constructor Create;
    destructor Destroy; override;
    function Kind: TEtfTermKind; virtual; abstract;
    function AsString: string; virtual; abstract;
    { Convenience casts — raise EEtfMappingError on wrong type }
    function AsAtom: TEtfAtom;
    function AsInteger: TEtfInteger;
    function AsFloat: TEtfFloat;
    function AsBinary: TEtfBinary;
    function AsEtfString: TEtfString;
    function AsList: TEtfList;
    function AsTuple: TEtfTuple;
    function AsMap: TEtfMap;
    function AsElixirStruct: TEtfElixirStruct;
    function AsPid: TEtfPid;
    function AsPort: TEtfPort;
    function AsReference: TEtfReference;
    function AsFun: TEtfFun;
    { True if this is the atom 'nil' }
    function IsNil: Boolean;
    { True if atom 'true' or 'false' }
    function IsBool: Boolean;
    function AsBool: Boolean;
    property Owned: Boolean read FOwned write FOwned;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfAtom                                                            }
  { ------------------------------------------------------------------ }
  TEtfAtom = class(TEtfTerm)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Value: string read FValue;
    function IsNilAtom: Boolean;
    function IsTrueAtom: Boolean;
    function IsFalseAtom: Boolean;
    function IsUndefined: Boolean;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfInteger — covers small/large integers, including bignum         }
  { ------------------------------------------------------------------ }
  TEtfInteger = class(TEtfTerm)
  private
    FValue: Int64;
    FBigNum: string;  { hex string for values exceeding Int64 }
    FIsBig: Boolean;
  public
    constructor Create(AValue: Int64);
    constructor CreateBig(const AHex: string; ASign: Byte);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Value: Int64 read FValue;
    property BigNum: string read FBigNum;
    property IsBig: Boolean read FIsBig;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfFloat                                                           }
  { ------------------------------------------------------------------ }
  TEtfFloat = class(TEtfTerm)
  private
    FValue: Double;
  public
    constructor Create(AValue: Double);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Value: Double read FValue write FValue;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfBinary — BINARY_EXT or BIT_BINARY_EXT                          }
  { ------------------------------------------------------------------ }
  TEtfBinary = class(TEtfTerm)
  private
    FData: TBytes;
    FBits: Byte;   { valid bits in last byte; 8 = full byte }
  public
    constructor Create(const AData: TBytes; ABits: Byte = 8);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    function AsUtf8String: string;
    property Data: TBytes read FData;
    property Bits: Byte read FBits;
    function IsBitBinary: Boolean;
    function Size: Integer;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfString — STRING_EXT (latin-1 char list as optimised form)       }
  { ------------------------------------------------------------------ }
  TEtfString = class(TEtfTerm)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Value: string read FValue;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfList — proper list (tail = [])                                  }
  { ------------------------------------------------------------------ }
  TEtfList = class(TEtfTerm)
  private
    FElements: TEtfTermList;
  public
    constructor Create;
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    procedure Add(AItem: TEtfTerm);
    function Count: Integer;
    function Get(AIndex: Integer): TEtfTerm;
    property Elements: TEtfTermList read FElements;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfImproperList — list with non-[] tail                            }
  { ------------------------------------------------------------------ }
  TEtfImproperList = class(TEtfTerm)
  private
    FElements: TEtfTermList;
    FTail: TEtfTerm;
  public
    constructor Create;
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    procedure Add(AItem: TEtfTerm);
    function Count: Integer;
    function Get(AIndex: Integer): TEtfTerm;
    property Elements: TEtfTermList read FElements;
    property Tail: TEtfTerm read FTail write FTail;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfTuple                                                           }
  { ------------------------------------------------------------------ }
  TEtfTuple = class(TEtfTerm)
  private
    FElements: TEtfTermList;
  public
    constructor Create;
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    procedure Add(AItem: TEtfTerm);
    function Count: Integer;
    function Get(AIndex: Integer): TEtfTerm;
    property Elements: TEtfTermList read FElements;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfMapPair — one key-value pair in a map                           }
  { ------------------------------------------------------------------ }
  TEtfMapPair = record
    Key: TEtfTerm;
    Value: TEtfTerm;
  end;
  TEtfMapPairArray = array of TEtfMapPair;

  { ------------------------------------------------------------------ }
  {  TEtfMap — MAP_EXT; insertion-ordered pairs                          }
  { ------------------------------------------------------------------ }
  TEtfMap = class(TEtfTerm)
  private
    FPairs: TEtfMapPairArray;
    FCount: Integer;
    procedure Grow;
  public
    constructor Create;
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    procedure Put(AKey, AValue: TEtfTerm);
    function Get(AKey: TEtfTerm): TEtfTerm;
    function GetByAtom(const AKey: string): TEtfTerm;
    function TryGetByAtom(const AKey: string; out AValue: TEtfTerm): Boolean;
    function Count: Integer;
    function PairAt(AIndex: Integer): TEtfMapPair;
    function HasStructKey: Boolean;
    function StructName: string;  { value of __struct__ atom, or '' }
  end;

  { ------------------------------------------------------------------ }
  {  TEtfElixirStruct — Map with __struct__ key                          }
  { ------------------------------------------------------------------ }
  TEtfElixirStruct = class(TEtfMap)
  private
    FStructName: string;
  public
    constructor Create(const AStructName: string);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property ElixirStructName: string read FStructName;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfPid                                                             }
  { ------------------------------------------------------------------ }
  TEtfPid = class(TEtfTerm)
  private
    FNode: TEtfAtom;
    FId: UInt32;
    FSerial: UInt32;
    FCreation: UInt32;
  public
    constructor Create(ANode: TEtfAtom; AId, ASerial, ACreation: UInt32);
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Node: TEtfAtom read FNode;
    property Id: UInt32 read FId;
    property Serial: UInt32 read FSerial;
    property Creation: UInt32 read FCreation;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfPort                                                            }
  { ------------------------------------------------------------------ }
  TEtfPort = class(TEtfTerm)
  private
    FNode: TEtfAtom;
    FId: UInt64;
    FCreation: UInt32;
  public
    constructor Create(ANode: TEtfAtom; AId: UInt64; ACreation: UInt32);
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Node: TEtfAtom read FNode;
    property Id: UInt64 read FId;
    property Creation: UInt32 read FCreation;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfReference                                                       }
  { ------------------------------------------------------------------ }
  TEtfReference = class(TEtfTerm)
  private
    FNode: TEtfAtom;
    FIds: array of UInt32;
    FCreation: UInt32;
  public
    constructor Create(ANode: TEtfAtom; const AIds: array of UInt32; ACreation: UInt32);
    destructor Destroy; override;
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property Node: TEtfAtom read FNode;
    function IdCount: Integer;
    function IdAt(AIndex: Integer): UInt32;
    property Creation: UInt32 read FCreation;
  end;

  { ------------------------------------------------------------------ }
  {  TEtfFun — FUN_EXT, NEW_FUN_EXT, EXPORT_EXT                         }
  { ------------------------------------------------------------------ }
  TEtfFunKind = (efkOldFun, efkNewFun, efkExport);

  TEtfFun = class(TEtfTerm)
  private
    FFunKind: TEtfFunKind;
    FModule: string;
    FFunction: string;
    FArity: Integer;
    { Raw bytes for opaque storage of fun internals }
    FRawData: TBytes;
  public
    constructor Create(AFunKind: TEtfFunKind; const AModule, AFunction: string; AArity: Integer);
    function Kind: TEtfTermKind; override;
    function AsString: string; override;
    property FunKind: TEtfFunKind read FFunKind;
    property Module: string read FModule;
    property &Function: string read FFunction;
    property Arity: Integer read FArity;
    property RawData: TBytes read FRawData write FRawData;
  end;

implementation

{ TEtfTerm }

constructor TEtfTerm.Create;
begin
  inherited Create;
  FOwned := True;
end;

destructor TEtfTerm.Destroy;
begin
  inherited Destroy;
end;

function TEtfTerm.AsAtom: TEtfAtom;
begin
  if not (Self is TEtfAtom) then
    raise EEtfMappingError.CreateFmt('Expected atom, got %s', [ClassName]);
  Result := TEtfAtom(Self);
end;

function TEtfTerm.AsInteger: TEtfInteger;
begin
  if not (Self is TEtfInteger) then
    raise EEtfMappingError.CreateFmt('Expected integer, got %s', [ClassName]);
  Result := TEtfInteger(Self);
end;

function TEtfTerm.AsFloat: TEtfFloat;
begin
  if not (Self is TEtfFloat) then
    raise EEtfMappingError.CreateFmt('Expected float, got %s', [ClassName]);
  Result := TEtfFloat(Self);
end;

function TEtfTerm.AsBinary: TEtfBinary;
begin
  if not (Self is TEtfBinary) then
    raise EEtfMappingError.CreateFmt('Expected binary, got %s', [ClassName]);
  Result := TEtfBinary(Self);
end;

function TEtfTerm.AsEtfString: TEtfString;
begin
  if not (Self is TEtfString) then
    raise EEtfMappingError.CreateFmt('Expected string, got %s', [ClassName]);
  Result := TEtfString(Self);
end;

function TEtfTerm.AsList: TEtfList;
begin
  if not (Self is TEtfList) then
    raise EEtfMappingError.CreateFmt('Expected list, got %s', [ClassName]);
  Result := TEtfList(Self);
end;

function TEtfTerm.AsTuple: TEtfTuple;
begin
  if not (Self is TEtfTuple) then
    raise EEtfMappingError.CreateFmt('Expected tuple, got %s', [ClassName]);
  Result := TEtfTuple(Self);
end;

function TEtfTerm.AsMap: TEtfMap;
begin
  if not (Self is TEtfMap) then
    raise EEtfMappingError.CreateFmt('Expected map, got %s', [ClassName]);
  Result := TEtfMap(Self);
end;

function TEtfTerm.AsElixirStruct: TEtfElixirStruct;
begin
  if not (Self is TEtfElixirStruct) then
    raise EEtfMappingError.CreateFmt('Expected Elixir struct, got %s', [ClassName]);
  Result := TEtfElixirStruct(Self);
end;

function TEtfTerm.AsPid: TEtfPid;
begin
  if not (Self is TEtfPid) then
    raise EEtfMappingError.CreateFmt('Expected PID, got %s', [ClassName]);
  Result := TEtfPid(Self);
end;

function TEtfTerm.AsPort: TEtfPort;
begin
  if not (Self is TEtfPort) then
    raise EEtfMappingError.CreateFmt('Expected port, got %s', [ClassName]);
  Result := TEtfPort(Self);
end;

function TEtfTerm.AsReference: TEtfReference;
begin
  if not (Self is TEtfReference) then
    raise EEtfMappingError.CreateFmt('Expected reference, got %s', [ClassName]);
  Result := TEtfReference(Self);
end;

function TEtfTerm.AsFun: TEtfFun;
begin
  if not (Self is TEtfFun) then
    raise EEtfMappingError.CreateFmt('Expected fun, got %s', [ClassName]);
  Result := TEtfFun(Self);
end;

function TEtfTerm.IsNil: Boolean;
begin
  Result := (Self is TEtfAtom) and (TEtfAtom(Self).Value = ATOM_NIL);
end;

function TEtfTerm.IsBool: Boolean;
begin
  Result := (Self is TEtfAtom) and
    ((TEtfAtom(Self).Value = ATOM_TRUE) or (TEtfAtom(Self).Value = ATOM_FALSE));
end;

function TEtfTerm.AsBool: Boolean;
begin
  if not (Self is TEtfAtom) then
    raise EEtfMappingError.CreateFmt('Expected bool atom, got %s', [ClassName]);
  if TEtfAtom(Self).Value = ATOM_TRUE then
    Result := True
  else if TEtfAtom(Self).Value = ATOM_FALSE then
    Result := False
  else
    raise EEtfMappingError.CreateFmt('Atom "%s" is not a boolean', [TEtfAtom(Self).Value]);
end;

{ TEtfAtom }

constructor TEtfAtom.Create(const AValue: string);
begin
  inherited Create;
  FValue := AValue;
end;

function TEtfAtom.Kind: TEtfTermKind;
begin
  Result := etkAtom;
end;

function TEtfAtom.AsString: string;
begin
  Result := ':' + FValue;
end;

function TEtfAtom.IsNilAtom: Boolean;
begin
  Result := FValue = ATOM_NIL;
end;

function TEtfAtom.IsTrueAtom: Boolean;
begin
  Result := FValue = ATOM_TRUE;
end;

function TEtfAtom.IsFalseAtom: Boolean;
begin
  Result := FValue = ATOM_FALSE;
end;

function TEtfAtom.IsUndefined: Boolean;
begin
  Result := FValue = ATOM_UNDEFINED;
end;

{ TEtfInteger }

constructor TEtfInteger.Create(AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
  FIsBig := False;
end;

constructor TEtfInteger.CreateBig(const AHex: string; ASign: Byte);
begin
  inherited Create;
  FBigNum := AHex;
  FIsBig := True;
  FValue := 0;
  if ASign = 0 then
    FValue := StrToInt64Def('$' + Copy(AHex, 1, 16), 0)
  else
    FValue := -StrToInt64Def('$' + Copy(AHex, 1, 16), 0);
end;

function TEtfInteger.Kind: TEtfTermKind;
begin
  Result := etkInteger;
end;

function TEtfInteger.AsString: string;
begin
  if FIsBig then
    Result := FBigNum
  else
    Result := IntToStr(FValue);
end;

{ TEtfFloat }

constructor TEtfFloat.Create(AValue: Double);
begin
  inherited Create;
  FValue := AValue;
end;

function TEtfFloat.Kind: TEtfTermKind;
begin
  Result := etkFloat;
end;

function TEtfFloat.AsString: string;
begin
  Result := FloatToStr(FValue);
end;

{ TEtfBinary }

constructor TEtfBinary.Create(const AData: TBytes; ABits: Byte);
begin
  inherited Create;
  FData := AData;
  FBits := ABits;
end;

function TEtfBinary.Kind: TEtfTermKind;
begin
  Result := etkBinary;
end;

function TEtfBinary.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<<');
    for I := 0 to High(FData) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(IntToStr(FData[I]));
    end;
    SB.Append('>>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TEtfBinary.AsUtf8String: string;
begin
  if Length(FData) = 0 then
    Exit('');
  SetLength(Result, Length(FData));
  Move(FData[0], Result[1], Length(FData));
end;

function TEtfBinary.IsBitBinary: Boolean;
begin
  Result := FBits <> 8;
end;

function TEtfBinary.Size: Integer;
begin
  Result := Length(FData);
end;

{ TEtfString }

constructor TEtfString.Create(const AValue: string);
begin
  inherited Create;
  FValue := AValue;
end;

function TEtfString.Kind: TEtfTermKind;
begin
  Result := etkString;
end;

function TEtfString.AsString: string;
begin
  Result := '"' + FValue + '"';
end;

{ TEtfList }

constructor TEtfList.Create;
begin
  inherited Create;
  FElements := TEtfTermList.Create(True);
end;

destructor TEtfList.Destroy;
begin
  FElements.Free;
  inherited Destroy;
end;

function TEtfList.Kind: TEtfTermKind;
begin
  Result := etkList;
end;

function TEtfList.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to FElements.Count - 1 do
    begin
      if I > 0 then SB.Append(', ');
      SB.Append(FElements[I].AsString);
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TEtfList.Add(AItem: TEtfTerm);
begin
  FElements.Add(AItem);
end;

function TEtfList.Count: Integer;
begin
  Result := FElements.Count;
end;

function TEtfList.Get(AIndex: Integer): TEtfTerm;
begin
  Result := FElements[AIndex];
end;

{ TEtfImproperList }

constructor TEtfImproperList.Create;
begin
  inherited Create;
  FElements := TEtfTermList.Create(True);
  FTail := nil;
end;

destructor TEtfImproperList.Destroy;
begin
  FTail.Free;
  FElements.Free;
  inherited Destroy;
end;

function TEtfImproperList.Kind: TEtfTermKind;
begin
  Result := etkImproperList;
end;

function TEtfImproperList.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to FElements.Count - 1 do
    begin
      if I > 0 then SB.Append(', ');
      SB.Append(FElements[I].AsString);
    end;
    if Assigned(FTail) then
    begin
      SB.Append(' | ');
      SB.Append(FTail.AsString);
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TEtfImproperList.Add(AItem: TEtfTerm);
begin
  FElements.Add(AItem);
end;

function TEtfImproperList.Count: Integer;
begin
  Result := FElements.Count;
end;

function TEtfImproperList.Get(AIndex: Integer): TEtfTerm;
begin
  Result := FElements[AIndex];
end;

{ TEtfTuple }

constructor TEtfTuple.Create;
begin
  inherited Create;
  FElements := TEtfTermList.Create(True);
end;

destructor TEtfTuple.Destroy;
begin
  FElements.Free;
  inherited Destroy;
end;

function TEtfTuple.Kind: TEtfTermKind;
begin
  Result := etkTuple;
end;

function TEtfTuple.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    for I := 0 to FElements.Count - 1 do
    begin
      if I > 0 then SB.Append(', ');
      SB.Append(FElements[I].AsString);
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TEtfTuple.Add(AItem: TEtfTerm);
begin
  FElements.Add(AItem);
end;

function TEtfTuple.Count: Integer;
begin
  Result := FElements.Count;
end;

function TEtfTuple.Get(AIndex: Integer): TEtfTerm;
begin
  Result := FElements[AIndex];
end;

{ TEtfMap }

constructor TEtfMap.Create;
begin
  inherited Create;
  FCount := 0;
  SetLength(FPairs, 8);
end;

destructor TEtfMap.Destroy;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
  begin
    FPairs[I].Key.Free;
    FPairs[I].Value.Free;
  end;
  inherited Destroy;
end;

procedure TEtfMap.Grow;
begin
  SetLength(FPairs, Length(FPairs) * 2);
end;

function TEtfMap.Kind: TEtfTermKind;
begin
  Result := etkMap;
end;

function TEtfMap.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('%{');
    for I := 0 to FCount - 1 do
    begin
      if I > 0 then SB.Append(', ');
      SB.Append(FPairs[I].Key.AsString);
      SB.Append(' => ');
      SB.Append(FPairs[I].Value.AsString);
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TEtfMap.Put(AKey, AValue: TEtfTerm);
begin
  if FCount >= Length(FPairs) then Grow;
  FPairs[FCount].Key := AKey;
  FPairs[FCount].Value := AValue;
  Inc(FCount);
end;

function TEtfMap.Get(AKey: TEtfTerm): TEtfTerm;
var
  I: Integer;
  KeyStr: string;
begin
  KeyStr := AKey.AsString;
  for I := 0 to FCount - 1 do
    if FPairs[I].Key.AsString = KeyStr then
      Exit(FPairs[I].Value);
  Result := nil;
end;

function TEtfMap.GetByAtom(const AKey: string): TEtfTerm;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
    if (FPairs[I].Key is TEtfAtom) and (TEtfAtom(FPairs[I].Key).Value = AKey) then
      Exit(FPairs[I].Value);
  Result := nil;
end;

function TEtfMap.TryGetByAtom(const AKey: string; out AValue: TEtfTerm): Boolean;
begin
  AValue := GetByAtom(AKey);
  Result := AValue <> nil;
end;

function TEtfMap.Count: Integer;
begin
  Result := FCount;
end;

function TEtfMap.PairAt(AIndex: Integer): TEtfMapPair;
begin
  Result := FPairs[AIndex];
end;

function TEtfMap.HasStructKey: Boolean;
begin
  Result := GetByAtom(ATOM_STRUCT) <> nil;
end;

function TEtfMap.StructName: string;
var
  V: TEtfTerm;
begin
  V := GetByAtom(ATOM_STRUCT);
  if (V <> nil) and (V is TEtfAtom) then
    Result := TEtfAtom(V).Value
  else
    Result := '';
end;

{ TEtfElixirStruct }

constructor TEtfElixirStruct.Create(const AStructName: string);
begin
  inherited Create;
  FStructName := AStructName;
end;

function TEtfElixirStruct.Kind: TEtfTermKind;
begin
  Result := etkElixirStruct;
end;

function TEtfElixirStruct.AsString: string;
begin
  Result := '%' + FStructName + '{' + inherited AsString + '}';
end;

{ TEtfPid }

constructor TEtfPid.Create(ANode: TEtfAtom; AId, ASerial, ACreation: UInt32);
begin
  inherited Create;
  FNode := ANode;
  FId := AId;
  FSerial := ASerial;
  FCreation := ACreation;
end;

destructor TEtfPid.Destroy;
begin
  FNode.Free;
  inherited Destroy;
end;

function TEtfPid.Kind: TEtfTermKind;
begin
  Result := etkPid;
end;

function TEtfPid.AsString: string;
begin
  Result := Format('#PID<%s.%d.%d>', [FNode.Value, FId, FSerial]);
end;

{ TEtfPort }

constructor TEtfPort.Create(ANode: TEtfAtom; AId: UInt64; ACreation: UInt32);
begin
  inherited Create;
  FNode := ANode;
  FId := AId;
  FCreation := ACreation;
end;

destructor TEtfPort.Destroy;
begin
  FNode.Free;
  inherited Destroy;
end;

function TEtfPort.Kind: TEtfTermKind;
begin
  Result := etkPort;
end;

function TEtfPort.AsString: string;
begin
  Result := Format('#Port<%s.%d>', [FNode.Value, FId]);
end;

{ TEtfReference }

constructor TEtfReference.Create(ANode: TEtfAtom; const AIds: array of UInt32; ACreation: UInt32);
var
  I: Integer;
begin
  inherited Create;
  FNode := ANode;
  FCreation := ACreation;
  SetLength(FIds, Length(AIds));
  for I := 0 to High(AIds) do
    FIds[I] := AIds[I];
end;

destructor TEtfReference.Destroy;
begin
  FNode.Free;
  inherited Destroy;
end;

function TEtfReference.Kind: TEtfTermKind;
begin
  Result := etkReference;
end;

function TEtfReference.AsString: string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('#Reference<');
    SB.Append(FNode.Value);
    for I := 0 to High(FIds) do
    begin
      SB.Append('.');
      SB.Append(IntToStr(FIds[I]));
    end;
    SB.Append('>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TEtfReference.IdCount: Integer;
begin
  Result := Length(FIds);
end;

function TEtfReference.IdAt(AIndex: Integer): UInt32;
begin
  Result := FIds[AIndex];
end;

{ TEtfFun }

constructor TEtfFun.Create(AFunKind: TEtfFunKind; const AModule, AFunction: string; AArity: Integer);
begin
  inherited Create;
  FFunKind := AFunKind;
  FModule := AModule;
  FFunction := AFunction;
  FArity := AArity;
end;

function TEtfFun.Kind: TEtfTermKind;
begin
  Result := etkFun;
end;

function TEtfFun.AsString: string;
begin
  Result := Format('&%s.%s/%d', [FModule, FFunction, FArity]);
end;

end.
