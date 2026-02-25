unit testbeam;

{
  FPCUnit test suite for the BeamETF library.

  Groups:
    TTestEtfPrimitives   — integer, float, atom, binary, string roundtrip
    TTestEtfCollections  — list, tuple, map, improper list
    TTestEtfElixir       — atoms nil/true/false, Elixir struct decode
    TTestEtfRTTI         — TEtfMapper<T> encode/decode via RTTI + attributes
    TTestEtfRegistry     — TEtfStructRegistry register/lookup
    TTestEtfAtomCache    — atom interning and ref-table
    TTestEtfRecord       — TEtfRecordMapper<T> stack-friendly record mapping
}

{$mode objfpc}{$H+}
{$modeswitch prefixedattributes}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  ETF.Types,
  ETF.Atom,
  ETF.Decoder,
  ETF.Encoder,
  ETF.Attributes,
  ETF.Struct,
  ETF.RTTI,
  ETF.RecordMap,
  testrecords;

{ ------------------------------------------------------------------ }
{ Helper: encode a term and decode it back                            }
{ ------------------------------------------------------------------ }
function RoundTrip(ATerm: TEtfTerm): TEtfTerm;

type

  { ------------------------------------------------------------------ }
  {  Primitive types                                                     }
  { ------------------------------------------------------------------ }
  TTestEtfPrimitives = class(TTestCase)
  published
    procedure TestSmallInteger;
    procedure TestNegativeInteger;
    procedure TestInt32;
    procedure TestLargeInt64;
    procedure TestFloat;
    procedure TestAtom;
    procedure TestAtomNilTrueFalse;
    procedure TestBinary;
    procedure TestBitBinary;
    procedure TestStringExt;
  end;

  { ------------------------------------------------------------------ }
  {  Collections                                                         }
  { ------------------------------------------------------------------ }
  TTestEtfCollections = class(TTestCase)
  published
    procedure TestEmptyList;
    procedure TestProperList;
    procedure TestImproperList;
    procedure TestSmallTuple;
    procedure TestNestedTuple;
    procedure TestMap;
    procedure TestNestedMap;
  end;

  { ------------------------------------------------------------------ }
  {  Elixir-specific                                                     }
  { ------------------------------------------------------------------ }
  TTestEtfElixir = class(TTestCase)
  published
    procedure TestAtomNil;
    procedure TestAtomTrue;
    procedure TestAtomFalse;
    procedure TestElixirStructDecode;
    procedure TestElixirStructEncode;
    procedure TestBinaryAsUtf8;
  end;

  { ------------------------------------------------------------------ }
  {  RTTI mapper                                                         }
  { ------------------------------------------------------------------ }

  { Sample Pascal class representing Elixir's %User{} struct }
  [EtfStruct('Elixir.TestUser')]
  TTestUser = class(TPersistent)
  private
    FId: Integer;
    FName: string;
    FActive: Boolean;
    FScore: Double;
    FTag: string;
  published
    [EtfField('id')]
    [EtfRequired]
    property Id: Integer read FId write FId;

    [EtfField('name')]
    property Name: string read FName write FName;

    [EtfField('active')]
    property Active: Boolean read FActive write FActive;

    [EtfField('score')]
    property Score: Double read FScore write FScore;

    [EtfIgnore]
    property Tag: string read FTag write FTag;
  end;

  TTestEtfRTTI = class(TTestCase)
  published
    procedure TestDecodeMapToObject;
    procedure TestEncodeObjectToMap;
    procedure TestRoundTripObject;
    procedure TestIgnoreAttribute;
    procedure TestRequiredAttributeMissing;
    procedure TestBooleanMapping;
    procedure TestFloatMapping;
  end;

  { ------------------------------------------------------------------ }
  {  Struct registry                                                     }
  { ------------------------------------------------------------------ }
  TTestEtfRegistry = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRegisterAndFind;
    procedure TestRegisterWithAttribute;
    procedure TestFindUnregistered;
    procedure TestIsRegistered;
    procedure TestClear;
    procedure TestDecodeRegisteredStruct;
  end;

  { ------------------------------------------------------------------ }
  {  Atom cache                                                          }
  { ------------------------------------------------------------------ }
  TTestEtfAtomCache = class(TTestCase)
  published
    procedure TestInternSameReference;
    procedure TestWellKnownAtoms;
    procedure TestAtomRefTable;
    procedure TestClearAndReintern;
  end;

  { ------------------------------------------------------------------ }
  {  Record mapper                                                       }
  { ------------------------------------------------------------------ }
  TTestEtfRecord = class(TTestCase)
  published
    { Decode an ETF map term into a stack-allocated TUserRecord }
    procedure TestFillFromTerm;
    { Roundtrip: record → ETF bytes → record }
    procedure TestRoundTrip;
    { EtfIgnore attribute skips the field during encode }
    procedure TestIgnoreField;
    { EtfRequired raises EEtfMappingError when key is absent }
    procedure TestRequiredFieldMissing;
    { Boolean fields map to/from true/false atoms }
    procedure TestBoolField;
    { [EtfAsAtom] encodes string as atom }
    procedure TestAsAtomField;
    { enum fields encode as atom name }
    procedure TestEnumField;
    { Decode using TEtfRecordMapper<T>.Decode(bytes) shortcut }
    procedure TestDecodeBytes;
    { Nested record: decode map with nested map into record with record field }
    procedure TestNestedRecord;
    { [EtfStruct] on records: ToTerm adds __struct__ from type attribute }
    procedure TestNestedRecordStructName;
  end;

implementation

{ ------------------------------------------------------------------ }
{ RoundTrip helper                                                     }
{ ------------------------------------------------------------------ }
function RoundTrip(ATerm: TEtfTerm): TEtfTerm;
var
  Bytes: TBytes;
begin
  Bytes := TEtfEncoder.EncodeToBytes(ATerm);
  Result := TEtfDecoder.Decode(Bytes);
end;

{ ================================================================== }
{  TTestEtfPrimitives                                                  }
{ ================================================================== }

procedure TTestEtfPrimitives.TestSmallInteger;
var
  T, R: TEtfTerm;
begin
  T := TEtfInteger.Create(42);
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is integer', R.Kind = etkInteger);
      AssertEquals('Value', 42, R.AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestNegativeInteger;
var
  T, R: TEtfTerm;
begin
  T := TEtfInteger.Create(-12345);
  try
    R := RoundTrip(T);
    try
      AssertEquals('Negative value', -12345, R.AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestInt32;
var
  T, R: TEtfTerm;
begin
  T := TEtfInteger.Create(1000000);
  try
    R := RoundTrip(T);
    try
      AssertEquals('Int32 value', 1000000, R.AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestLargeInt64;
var
  T, R: TEtfTerm;
  V: Int64;
begin
  V := Int64(9999999999);
  T := TEtfInteger.Create(V);
  try
    R := RoundTrip(T);
    try
      AssertEquals('Int64 value', V, R.AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestFloat;
var
  T, R: TEtfTerm;
begin
  T := TEtfFloat.Create(3.14159265);
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is float', R.Kind = etkFloat);
      AssertTrue('Float value approx', Abs(R.AsFloat.Value - 3.14159265) < 1e-9);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestAtom;
var
  T, R: TEtfTerm;
begin
  T := TEtfAtom.Create('hello_world');
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is atom', R.Kind = etkAtom);
      AssertEquals('Atom value', 'hello_world', R.AsAtom.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestAtomNilTrueFalse;
var
  T, R: TEtfTerm;
begin
  T := TEtfAtom.Create('nil');
  try
    R := RoundTrip(T);
    try
      AssertTrue('nil atom IsNil', R.IsNil);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;

  T := TEtfAtom.Create('true');
  try
    R := RoundTrip(T);
    try
      AssertTrue('true atom IsBool', R.IsBool);
      AssertTrue('true atom AsBool', R.AsBool);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;

  T := TEtfAtom.Create('false');
  try
    R := RoundTrip(T);
    try
      AssertFalse('false atom AsBool', R.AsBool);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestBinary;
var
  Data: TBytes;
  T, R: TEtfTerm;
begin
  SetLength(Data, 4);
  Data[0] := $DE; Data[1] := $AD; Data[2] := $BE; Data[3] := $EF;
  T := TEtfBinary.Create(Data);
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is binary', R.Kind = etkBinary);
      AssertEquals('Binary size', 4, R.AsBinary.Size);
      AssertEquals('Byte 0', $DE, R.AsBinary.Data[0]);
      AssertEquals('Byte 3', $EF, R.AsBinary.Data[3]);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestBitBinary;
var
  Data: TBytes;
  T, R: TEtfTerm;
begin
  SetLength(Data, 2);
  Data[0] := $FF; Data[1] := $F0;
  T := TEtfBinary.Create(Data, 4);  { 4 valid bits in last byte }
  try
    R := RoundTrip(T);
    try
      AssertTrue('IsBitBinary', R.AsBinary.IsBitBinary);
      AssertEquals('Bits', 4, R.AsBinary.Bits);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfPrimitives.TestStringExt;
var
  T, R: TEtfTerm;
begin
  T := TEtfString.Create('Hello, Erlang!');
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is string', R.Kind = etkString);
      AssertEquals('String value', 'Hello, Erlang!', R.AsEtfString.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

{ ================================================================== }
{  TTestEtfCollections                                                 }
{ ================================================================== }

procedure TTestEtfCollections.TestEmptyList;
var
  T, R: TEtfTerm;
begin
  T := TEtfList.Create;
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is list', R.Kind = etkList);
      AssertEquals('Count', 0, R.AsList.Count);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfCollections.TestProperList;
var
  T, R: TEtfTerm;
  L: TEtfList;
begin
  L := TEtfList.Create;
  L.Add(TEtfInteger.Create(1));
  L.Add(TEtfInteger.Create(2));
  L.Add(TEtfInteger.Create(3));
  T := L;
  try
    R := RoundTrip(T);
    try
      AssertEquals('Count', 3, R.AsList.Count);
      AssertEquals('Item 0', 1, R.AsList.Get(0).AsInteger.Value);
      AssertEquals('Item 2', 3, R.AsList.Get(2).AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfCollections.TestImproperList;
var
  IL: TEtfImproperList;
  Bytes: TBytes;
  R: TEtfTerm;
begin
  IL := TEtfImproperList.Create;
  IL.Add(TEtfInteger.Create(1));
  IL.Add(TEtfInteger.Create(2));
  IL.Tail := TEtfAtom.Create('rest');
  try
    Bytes := TEtfEncoder.EncodeToBytes(IL);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertTrue('Kind is improper list', R.Kind = etkImproperList);
      AssertEquals('Count', 2, TEtfImproperList(R).Count);
      AssertEquals('Tail atom', 'rest', TEtfImproperList(R).Tail.AsAtom.Value);
    finally
      R.Free;
    end;
  finally
    IL.Free;
  end;
end;

procedure TTestEtfCollections.TestSmallTuple;
var
  T, R: TEtfTerm;
  Tup: TEtfTuple;
begin
  Tup := TEtfTuple.Create;
  Tup.Add(TEtfAtom.Create('ok'));
  Tup.Add(TEtfInteger.Create(200));
  T := Tup;
  try
    R := RoundTrip(T);
    try
      AssertTrue('Kind is tuple', R.Kind = etkTuple);
      AssertEquals('Count', 2, R.AsTuple.Count);
      AssertEquals('Atom', 'ok', R.AsTuple.Get(0).AsAtom.Value);
      AssertEquals('Int', 200, R.AsTuple.Get(1).AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestEtfCollections.TestNestedTuple;
var
  Inner, Outer: TEtfTuple;
  R: TEtfTerm;
  Bytes: TBytes;
begin
  Inner := TEtfTuple.Create;
  Inner.Add(TEtfInteger.Create(1));
  Inner.Add(TEtfInteger.Create(2));
  Outer := TEtfTuple.Create;
  Outer.Add(TEtfAtom.Create('nested'));
  Outer.Add(Inner);
  try
    Bytes := TEtfEncoder.EncodeToBytes(Outer);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertEquals('Outer count', 2, R.AsTuple.Count);
      AssertTrue('Inner is tuple', R.AsTuple.Get(1).Kind = etkTuple);
      AssertEquals('Inner[0]', 1, R.AsTuple.Get(1).AsTuple.Get(0).AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    Outer.Free;
  end;
end;

procedure TTestEtfCollections.TestMap;
var
  M: TEtfMap;
  R: TEtfTerm;
  Bytes: TBytes;
  Val: TEtfTerm;
begin
  M := TEtfMap.Create;
  M.Put(TEtfAtom.Create('key1'), TEtfInteger.Create(42));
  M.Put(TEtfAtom.Create('key2'), TEtfAtom.Create('hello'));
  try
    Bytes := TEtfEncoder.EncodeToBytes(M);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertTrue('Kind is map', R.Kind = etkMap);
      AssertEquals('Map count', 2, R.AsMap.Count);
      Val := R.AsMap.GetByAtom('key1');
      AssertTrue('key1 not nil', Val <> nil);
      AssertEquals('key1 value', 42, Val.AsInteger.Value);
      Val := R.AsMap.GetByAtom('key2');
      AssertEquals('key2 atom', 'hello', Val.AsAtom.Value);
    finally
      R.Free;
    end;
  finally
    M.Free;
  end;
end;

procedure TTestEtfCollections.TestNestedMap;
var
  Inner, Outer: TEtfMap;
  R: TEtfTerm;
  Bytes: TBytes;
begin
  Inner := TEtfMap.Create;
  Inner.Put(TEtfAtom.Create('x'), TEtfInteger.Create(10));
  Outer := TEtfMap.Create;
  Outer.Put(TEtfAtom.Create('inner'), Inner);
  Outer.Put(TEtfAtom.Create('flag'), TEtfAtom.Create('true'));
  try
    Bytes := TEtfEncoder.EncodeToBytes(Outer);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertEquals('Outer count', 2, R.AsMap.Count);
      AssertTrue('inner is map', R.AsMap.GetByAtom('inner').Kind = etkMap);
    finally
      R.Free;
    end;
  finally
    Outer.Free;
  end;
end;

{ ================================================================== }
{  TTestEtfElixir                                                      }
{ ================================================================== }

procedure TTestEtfElixir.TestAtomNil;
var
  T: TEtfAtom;
begin
  T := TEtfAtom.Create('nil');
  try
    AssertTrue('IsNilAtom', T.IsNilAtom);
    AssertTrue('IsNil via base', TEtfTerm(T).IsNil);
  finally
    T.Free;
  end;
end;

procedure TTestEtfElixir.TestAtomTrue;
var
  T: TEtfAtom;
begin
  T := TEtfAtom.Create('true');
  try
    AssertTrue('IsTrueAtom', T.IsTrueAtom);
    AssertTrue('IsBool', TEtfTerm(T).IsBool);
    AssertTrue('AsBool', TEtfTerm(T).AsBool);
  finally
    T.Free;
  end;
end;

procedure TTestEtfElixir.TestAtomFalse;
var
  T: TEtfAtom;
begin
  T := TEtfAtom.Create('false');
  try
    AssertTrue('IsFalseAtom', T.IsFalseAtom);
    AssertFalse('AsBool', TEtfTerm(T).AsBool);
  finally
    T.Free;
  end;
end;

procedure TTestEtfElixir.TestElixirStructDecode;
var
  M: TEtfElixirStruct;
  Bytes: TBytes;
  R: TEtfTerm;
begin
  M := TEtfElixirStruct.Create('Elixir.MyModule.Struct');
  M.Put(TEtfAtom.Create(ATOM_STRUCT), TEtfAtom.Create('Elixir.MyModule.Struct'));
  M.Put(TEtfAtom.Create('field_a'), TEtfInteger.Create(99));
  try
    Bytes := TEtfEncoder.EncodeToBytes(M);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertTrue('Decoded as ElixirStruct', R.Kind = etkElixirStruct);
      AssertEquals('StructName', 'Elixir.MyModule.Struct',
        R.AsElixirStruct.ElixirStructName);
      AssertEquals('field_a', 99,
        R.AsElixirStruct.GetByAtom('field_a').AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    M.Free;
  end;
end;

procedure TTestEtfElixir.TestElixirStructEncode;
var
  M: TEtfElixirStruct;
  Bytes: TBytes;
  R: TEtfTerm;
  V: TEtfTerm;
begin
  M := TEtfElixirStruct.Create('Elixir.Counter');
  M.Put(TEtfAtom.Create(ATOM_STRUCT), TEtfAtom.Create('Elixir.Counter'));
  M.Put(TEtfAtom.Create('count'), TEtfInteger.Create(0));
  try
    Bytes := TEtfEncoder.EncodeToBytes(M);
    AssertTrue('Bytes not empty', Length(Bytes) > 0);
    AssertEquals('First byte is version', ETF_VERSION, Bytes[0]);
    R := TEtfDecoder.Decode(Bytes);
    try
      V := R.AsElixirStruct.GetByAtom('count');
      AssertEquals('count=0', 0, V.AsInteger.Value);
    finally
      R.Free;
    end;
  finally
    M.Free;
  end;
end;

procedure TTestEtfElixir.TestBinaryAsUtf8;
var
  S: string;
  Data: TBytes;
  Bin: TEtfBinary;
begin
  S := 'привет';  { UTF-8 }
  SetLength(Data, Length(S));
  Move(S[1], Data[0], Length(S));
  Bin := TEtfBinary.Create(Data);
  try
    AssertEquals('AsUtf8String', S, Bin.AsUtf8String);
  finally
    Bin.Free;
  end;
end;

{ ================================================================== }
{  TTestEtfRTTI                                                        }
{ ================================================================== }

procedure TTestEtfRTTI.TestDecodeMapToObject;
var
  Map: TEtfMap;
  User: TTestUser;
begin
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('id'), TEtfInteger.Create(7));
  Map.Put(TEtfAtom.Create('name'), TEtfBinary.Create(BytesOf('Alice')));
  Map.Put(TEtfAtom.Create('active'), TEtfAtom.Create('true'));
  Map.Put(TEtfAtom.Create('score'), TEtfFloat.Create(9.5));
  try
    User := specialize TEtfMapper<TTestUser>.FromTerm(Map);
    try
      AssertEquals('Id', 7, User.Id);
      AssertEquals('Name', 'Alice', User.Name);
      AssertTrue('Active', User.Active);
      AssertTrue('Score', Abs(User.Score - 9.5) < 1e-10);
    finally
      User.Free;
    end;
  finally
    Map.Free;
  end;
end;

procedure TTestEtfRTTI.TestEncodeObjectToMap;
var
  User: TTestUser;
  Term: TEtfMap;
  Val: TEtfTerm;
begin
  User := TTestUser.Create;
  try
    User.Id := 42;
    User.Name := 'Bob';
    User.Active := False;
    User.Score := 1.0;
    User.Tag := 'ignored';
    Term := specialize TEtfMapper<TTestUser>.ToTerm(User);
    try
      Val := Term.GetByAtom('id');
      AssertTrue('id present', Val <> nil);
      AssertEquals('id=42', 42, Val.AsInteger.Value);
      Val := Term.GetByAtom('tag');
      AssertTrue('tag absent (ignored)', Val = nil);
    finally
      Term.Free;
    end;
  finally
    User.Free;
  end;
end;

procedure TTestEtfRTTI.TestRoundTripObject;
var
  User, User2: TTestUser;
  Bytes: TBytes;
begin
  User := TTestUser.Create;
  try
    User.Id := 100;
    User.Name := 'Charlie';
    User.Active := True;
    User.Score := 7.77;
    Bytes := specialize TEtfMapper<TTestUser>.Encode(User);
  finally
    User.Free;
  end;

  User2 := specialize TEtfMapper<TTestUser>.Decode(Bytes);
  try
    AssertEquals('RoundTrip Id', 100, User2.Id);
    AssertEquals('RoundTrip Name', 'Charlie', User2.Name);
    AssertTrue('RoundTrip Active', User2.Active);
    AssertTrue('RoundTrip Score', Abs(User2.Score - 7.77) < 1e-10);
  finally
    User2.Free;
  end;
end;

procedure TTestEtfRTTI.TestIgnoreAttribute;
var
  User: TTestUser;
  Term: TEtfMap;
begin
  User := TTestUser.Create;
  try
    User.Id := 1;
    User.Tag := 'should-be-ignored';
    Term := specialize TEtfMapper<TTestUser>.ToTerm(User);
    try
      AssertTrue('tag key absent', Term.GetByAtom('tag') = nil);
    finally
      Term.Free;
    end;
  finally
    User.Free;
  end;
end;

procedure TTestEtfRTTI.TestRequiredAttributeMissing;
var
  Map: TEtfMap;
  Caught: Boolean;
begin
  { Map without 'id' key — Id has EtfRequired }
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('name'), TEtfBinary.Create(BytesOf('NoId')));
  try
    Caught := False;
    try
      specialize TEtfMapper<TTestUser>.FromTerm(Map).Free;
    except
      on E: EEtfMappingError do
        Caught := True;
    end;
    AssertTrue('EEtfMappingError raised for missing required field', Caught);
  finally
    Map.Free;
  end;
end;

procedure TTestEtfRTTI.TestBooleanMapping;
var
  User: TTestUser;
  Term: TEtfMap;
  Val: TEtfTerm;
begin
  User := TTestUser.Create;
  try
    User.Id := 1;
    User.Active := True;
    Term := specialize TEtfMapper<TTestUser>.ToTerm(User);
    try
      Val := Term.GetByAtom('active');
      AssertTrue('active is atom', Val.Kind = etkAtom);
      AssertEquals('active=true', 'true', Val.AsAtom.Value);
    finally
      Term.Free;
    end;
  finally
    User.Free;
  end;
end;

procedure TTestEtfRTTI.TestFloatMapping;
var
  Map: TEtfMap;
  User: TTestUser;
begin
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('id'), TEtfInteger.Create(1));
  Map.Put(TEtfAtom.Create('score'), TEtfFloat.Create(3.14));
  try
    User := specialize TEtfMapper<TTestUser>.FromTerm(Map);
    try
      AssertTrue('Score approx pi', Abs(User.Score - 3.14) < 1e-10);
    finally
      User.Free;
    end;
  finally
    Map.Free;
  end;
end;

{ ================================================================== }
{  TTestEtfRegistry                                                    }
{ ================================================================== }

procedure TTestEtfRegistry.SetUp;
begin
  TEtfStructRegistry.Clear;
end;

procedure TTestEtfRegistry.TearDown;
begin
  TEtfStructRegistry.Clear;
end;

procedure TTestEtfRegistry.TestRegisterAndFind;
begin
  TEtfStructRegistry.RegisterClass('Elixir.Foo', TTestUser);
  AssertTrue('Found class', TEtfStructRegistry.FindClass('Elixir.Foo') = TTestUser);
end;

procedure TTestEtfRegistry.TestRegisterWithAttribute;
begin
  TEtfStructRegistry.Register(TTestUser);
  AssertTrue('Found via attribute',
    TEtfStructRegistry.FindClass('Elixir.TestUser') = TTestUser);
end;

procedure TTestEtfRegistry.TestFindUnregistered;
begin
  AssertTrue('Not registered → nil',
    TEtfStructRegistry.FindClass('Elixir.NoSuchStruct') = nil);
end;

procedure TTestEtfRegistry.TestIsRegistered;
begin
  TEtfStructRegistry.RegisterClass('Elixir.Bar', TTestUser);
  AssertTrue('IsRegistered true', TEtfStructRegistry.IsRegistered('Elixir.Bar'));
  AssertFalse('IsRegistered false', TEtfStructRegistry.IsRegistered('Elixir.Missing'));
end;

procedure TTestEtfRegistry.TestClear;
begin
  TEtfStructRegistry.RegisterClass('Elixir.Temp', TTestUser);
  TEtfStructRegistry.Clear;
  AssertTrue('After clear → nil', TEtfStructRegistry.FindClass('Elixir.Temp') = nil);
end;

procedure TTestEtfRegistry.TestDecodeRegisteredStruct;
var
  M: TEtfElixirStruct;
  Bytes: TBytes;
  R: TEtfTerm;
begin
  { Even without RTTI mapping, decoding should produce TEtfElixirStruct }
  M := TEtfElixirStruct.Create('Elixir.TestUser');
  M.Put(TEtfAtom.Create(ATOM_STRUCT), TEtfAtom.Create('Elixir.TestUser'));
  M.Put(TEtfAtom.Create('id'), TEtfInteger.Create(55));
  try
    Bytes := TEtfEncoder.EncodeToBytes(M);
    R := TEtfDecoder.Decode(Bytes);
    try
      AssertTrue('Decoded as ElixirStruct', R.Kind = etkElixirStruct);
      AssertEquals('StructName', 'Elixir.TestUser', R.AsElixirStruct.ElixirStructName);
    finally
      R.Free;
    end;
  finally
    M.Free;
  end;
end;

{ ================================================================== }
{  TTestEtfAtomCache                                                   }
{ ================================================================== }

procedure TTestEtfAtomCache.TestInternSameReference;
var
  S1, S2: string;
begin
  S1 := TEtfAtomCache.Instance.Intern('my_atom');
  S2 := TEtfAtomCache.Instance.Intern('my_atom');
  AssertEquals('Same value', S1, S2);
end;

procedure TTestEtfAtomCache.TestWellKnownAtoms;
begin
  AssertEquals('nil', CACHED_NIL, EtfInternAtom('nil'));
  AssertEquals('true', CACHED_TRUE, EtfInternAtom('true'));
  AssertEquals('false', CACHED_FALSE, EtfInternAtom('false'));
  AssertEquals('ok', CACHED_OK, EtfInternAtom('ok'));
  AssertEquals('error', CACHED_ERROR, EtfInternAtom('error'));
  AssertEquals('__struct__', CACHED_STRUCT, EtfInternAtom('__struct__'));
end;

procedure TTestEtfAtomCache.TestAtomRefTable;
var
  Tbl: TEtfAtomRefTable;
begin
  Tbl := TEtfAtomRefTable.Create;
  try
    AssertFalse('Slot 0 unused', Tbl.IsUsed(0));
    Tbl.Store(0, 'some_atom');
    AssertTrue('Slot 0 used', Tbl.IsUsed(0));
    AssertEquals('Retrieve slot 0', 'some_atom', Tbl.Retrieve(0));
    Tbl.Clear;
    AssertFalse('Slot 0 cleared', Tbl.IsUsed(0));
  finally
    Tbl.Free;
  end;
end;

procedure TTestEtfAtomCache.TestClearAndReintern;
var
  Before, After: Integer;
begin
  Before := TEtfAtomCache.Instance.Count;
  TEtfAtomCache.Instance.Intern('unique_test_atom_xyz_123');
  AssertTrue('Count increased', TEtfAtomCache.Instance.Count > Before);
  TEtfAtomCache.Instance.Clear;
  { After clear, well-known atoms are back }
  AssertEquals('nil still there after clear', 'nil', EtfInternAtom('nil'));
end;

{ ================================================================== }
{  TTestEtfRecord                                                      }
{ ================================================================== }

procedure TTestEtfRecord.TestFillFromTerm;
var
  Map: TEtfMap;
  U: TUserRecord;
begin
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('id'),     TEtfInteger.Create(7));
  Map.Put(TEtfAtom.Create('name'),   TEtfBinary.Create(BytesOf('Alice')));
  Map.Put(TEtfAtom.Create('active'), TEtfAtom.Create('true'));
  Map.Put(TEtfAtom.Create('score'),  TEtfFloat.Create(9.5));
  try
    FillChar(U, SizeOf(U), 0);
    specialize TEtfRecordMapper<TUserRecord>.FillFromTerm(U, Map);
    AssertEquals('Id', 7, U.Id);
    AssertEquals('Name', 'Alice', U.Name);
    AssertTrue('Active', U.Active);
    AssertTrue('Score', Abs(U.Score - 9.5) < 1e-10);
  finally
    Map.Free;
  end;
end;

procedure TTestEtfRecord.TestRoundTrip;
var
  U1, U2: TUserRecord;
  Bytes: TBytes;
begin
  FillChar(U1, SizeOf(U1), 0);
  U1.Id := 42;
  U1.Name := 'Bob';
  U1.Active := True;
  U1.Score := 3.14;
  U1.InternalTag := 'should-be-ignored';

  Bytes := specialize TEtfRecordMapper<TUserRecord>.Encode(U1);
  FillChar(U2, SizeOf(U2), 0);
  U2 := specialize TEtfRecordMapper<TUserRecord>.Decode(Bytes);

  AssertEquals('RT Id', 42, U2.Id);
  AssertEquals('RT Name', 'Bob', U2.Name);
  AssertTrue('RT Active', U2.Active);
  AssertTrue('RT Score', Abs(U2.Score - 3.14) < 1e-10);
  AssertEquals('RT InternalTag absent', '', U2.InternalTag);
end;

procedure TTestEtfRecord.TestIgnoreField;
var
  U: TUserRecord;
  Term: TEtfMap;
begin
  FillChar(U, SizeOf(U), 0);
  U.Id := 1;
  U.InternalTag := 'secret';
  Term := specialize TEtfRecordMapper<TUserRecord>.ToTerm(U);
  try
    AssertTrue('internaltag absent in map',
      Term.GetByAtom('internaltag') = nil);
  finally
    Term.Free;
  end;
end;

procedure TTestEtfRecord.TestRequiredFieldMissing;
var
  Map: TEtfMap;
  U: TUserRecord;
  Caught: Boolean;
begin
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('name'), TEtfBinary.Create(BytesOf('NoId')));
  try
    Caught := False;
    try
      FillChar(U, SizeOf(U), 0);
      specialize TEtfRecordMapper<TUserRecord>.FillFromTerm(U, Map);
    except
      on E: EEtfMappingError do
        Caught := True;
    end;
    AssertTrue('EEtfMappingError raised', Caught);
  finally
    Map.Free;
  end;
end;

procedure TTestEtfRecord.TestBoolField;
var
  Map: TEtfMap;
  U: TUserRecord;
  Term: TEtfMap;
  Val: TEtfTerm;
begin
  { decode false }
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('id'),     TEtfInteger.Create(1));
  Map.Put(TEtfAtom.Create('active'), TEtfAtom.Create('false'));
  try
    FillChar(U, SizeOf(U), 0);
    specialize TEtfRecordMapper<TUserRecord>.FillFromTerm(U, Map);
    AssertFalse('Active is false', U.Active);
  finally
    Map.Free;
  end;

  { encode true }
  FillChar(U, SizeOf(U), 0);
  U.Id := 2;
  U.Active := True;
  Term := specialize TEtfRecordMapper<TUserRecord>.ToTerm(U);
  try
    Val := Term.GetByAtom('active');
    AssertTrue('active present', Val <> nil);
    AssertEquals('active=true atom', 'true', Val.AsAtom.Value);
  finally
    Term.Free;
  end;
end;

procedure TTestEtfRecord.TestAsAtomField;
var
  R: TRoleRecord;
  Term: TEtfMap;
  Val: TEtfTerm;
begin
  FillChar(R, SizeOf(R), 0);
  R.Id := 10;
  R.Role := 'admin';
  Term := specialize TEtfRecordMapper<TRoleRecord>.ToTerm(R);
  try
    Val := Term.GetByAtom('role');
    AssertTrue('role present', Val <> nil);
    AssertTrue('role is atom (not binary)', Val.Kind = etkAtom);
    AssertEquals('role value', 'admin', Val.AsAtom.Value);
  finally
    Term.Free;
  end;
end;

procedure TTestEtfRecord.TestEnumField;
var
  S: TStatusRecord;
  Term: TEtfMap;
  Val: TEtfTerm;
  Bytes: TBytes;
  S2: TStatusRecord;
begin
  FillChar(S, SizeOf(S), 0);
  S.Id := 5;
  S.Status := seBanned;

  Term := specialize TEtfRecordMapper<TStatusRecord>.ToTerm(S);
  try
    Val := Term.GetByAtom('status');
    AssertTrue('status present', Val <> nil);
    AssertTrue('status is atom', Val.Kind = etkAtom);
    AssertEquals('status=seBanned', 'seBanned', Val.AsAtom.Value);
  finally
    Term.Free;
  end;

  { roundtrip }
  Bytes := specialize TEtfRecordMapper<TStatusRecord>.Encode(S);
  FillChar(S2, SizeOf(S2), 0);
  S2 := specialize TEtfRecordMapper<TStatusRecord>.Decode(Bytes);
  AssertEquals('RT Status', Ord(seBanned), Ord(S2.Status));
end;

procedure TTestEtfRecord.TestDecodeBytes;
var
  Map: TEtfMap;
  Bytes: TBytes;
  U: TUserRecord;
begin
  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('id'),    TEtfInteger.Create(99));
  Map.Put(TEtfAtom.Create('name'),  TEtfBinary.Create(BytesOf('Eve')));
  Map.Put(TEtfAtom.Create('score'), TEtfFloat.Create(100.0));
  try
    Bytes := TEtfEncoder.EncodeToBytes(Map);
  finally
    Map.Free;
  end;

  FillChar(U, SizeOf(U), 0);
  U := specialize TEtfRecordMapper<TUserRecord>.Decode(Bytes);
  AssertEquals('Decode id', 99, U.Id);
  AssertEquals('Decode name', 'Eve', U.Name);
  AssertTrue('Decode score', Abs(U.Score - 100.0) < 1e-10);
end;

procedure TTestEtfRecord.TestNestedRecord;
var
  Map, AddrMap: TEtfMap;
  P: TProfileRecord;
  Bytes: TBytes;
  P2: TProfileRecord;
begin
  AddrMap := TEtfMap.Create;
  AddrMap.Put(TEtfAtom.Create('street'),  TEtfBinary.Create(BytesOf('Main St')));
  AddrMap.Put(TEtfAtom.Create('city'),    TEtfBinary.Create(BytesOf('Boston')));
  AddrMap.Put(TEtfAtom.Create('country'), TEtfBinary.Create(BytesOf('US')));

  Map := TEtfMap.Create;
  Map.Put(TEtfAtom.Create('name'), TEtfBinary.Create(BytesOf('John')));
  Map.Put(TEtfAtom.Create('address'), AddrMap);
  try
    FillChar(P, SizeOf(P), 0);
    specialize TEtfRecordMapper<TProfileRecord>.FillFromTerm(P, Map);
    AssertEquals('Profile.Name', 'John', P.Name);
    AssertEquals('Profile.Address.Street', 'Main St', P.Address.Street);
    AssertEquals('Profile.Address.City', 'Boston', P.Address.City);
    AssertEquals('Profile.Address.Country', 'US', P.Address.Country);

    Bytes := specialize TEtfRecordMapper<TProfileRecord>.Encode(P);
    FillChar(P2, SizeOf(P2), 0);
    P2 := specialize TEtfRecordMapper<TProfileRecord>.Decode(Bytes);
    AssertEquals('Roundtrip Name', 'John', P2.Name);
    AssertEquals('Roundtrip Address.Street', 'Main St', P2.Address.Street);
    AssertEquals('Roundtrip Address.City', 'Boston', P2.Address.City);
    AssertEquals('Roundtrip Address.Country', 'US', P2.Address.Country);
  finally
    Map.Free;
  end;
end;

procedure TTestEtfRecord.TestNestedRecordStructName;
var
  P: TProfileRecord;
  Term: TEtfMap;
  AddrTerm: TEtfTerm;
begin
  FillChar(P, SizeOf(P), 0);
  P.Name := 'Jane';
  P.Address.Street := 'Elm St';
  P.Address.City := 'NYC';
  P.Address.Country := 'US';
  Term := specialize TEtfRecordMapper<TProfileRecord>.ToTerm(P);
  try
    AssertTrue('Root is Elixir struct', Term is TEtfElixirStruct);
    AssertEquals('Root struct name', 'Elixir.Profile',
      TEtfElixirStruct(Term).ElixirStructName);
    AddrTerm := Term.GetByAtom('address');
    AssertTrue('Address is Elixir struct', AddrTerm is TEtfElixirStruct);
    AssertEquals('Address struct name', 'Elixir.Address',
      TEtfElixirStruct(AddrTerm).ElixirStructName);
  finally
    Term.Free;
  end;
end;

initialization
  RegisterTest(TTestEtfPrimitives);
  RegisterTest(TTestEtfCollections);
  RegisterTest(TTestEtfElixir);
  RegisterTest(TTestEtfRTTI);
  RegisterTest(TTestEtfRegistry);
  RegisterTest(TTestEtfAtomCache);
  RegisterTest(TTestEtfRecord);
end.
