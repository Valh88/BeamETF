unit ETF.Encoder;

{
  Erlang External Term Format — encoder.

  Converts TEtfTerm tree into binary ETF bytes.

  Encoding strategy:
    - Integers:    fit in 0..255  → SMALL_INTEGER_EXT
                   fit in Int32   → INTEGER_EXT
                   otherwise      → SMALL_BIG_EXT / LARGE_BIG_EXT
    - Floats:      NEW_FLOAT_EXT (IEEE 754 big-endian)
    - Atoms:       length ≤ 255  → SMALL_ATOM_UTF8_EXT
                   length > 255  → ATOM_UTF8_EXT
    - Binary:      BINARY_EXT or BIT_BINARY_EXT
    - String:      STRING_EXT
    - List:        NIL_EXT for empty, LIST_EXT otherwise
    - ImproperList:LIST_EXT with non-NIL tail
    - Tuple:       SMALL_TUPLE_EXT or LARGE_TUPLE_EXT
    - Map:         MAP_EXT
    - Pid:         NEW_PID_EXT
    - Port:        NEW_PORT_EXT
    - Reference:   NEWER_REFERENCE_EXT
    - Fun:         EXPORT_EXT for efkExport, NEW_FUN_EXT stub otherwise

  Usage:
    Bytes := TEtfEncoder.Encode(Term);           // returns TBytes with version byte
    TEtfEncoder.EncodeToStream(Term, Stream);    // writes to existing stream
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  ETF.Types;

type
  TEtfEncoder = class
  private
    FStream: TStream;
    { Write helpers }
    procedure WriteByte(B: Byte);
    procedure WriteBytes(const ABytes: TBytes);
    procedure WriteUInt16BE(V: UInt16);
    procedure WriteUInt32BE(V: UInt32);
    procedure WriteInt32BE(V: Int32);
    procedure WriteUInt64BE(V: UInt64);
    procedure WriteDouble(V: Double);
    procedure WriteAtomBytes(const S: string);
    { Type-specific encoders }
    procedure EncodeAtom(ATerm: TEtfAtom);
    procedure EncodeInteger(ATerm: TEtfInteger);
    procedure EncodeFloat(ATerm: TEtfFloat);
    procedure EncodeBinary(ATerm: TEtfBinary);
    procedure EncodeString(ATerm: TEtfString);
    procedure EncodeList(ATerm: TEtfList);
    procedure EncodeImproperList(ATerm: TEtfImproperList);
    procedure EncodeTuple(ATerm: TEtfTuple);
    procedure EncodeMap(ATerm: TEtfMap);
    procedure EncodePid(ATerm: TEtfPid);
    procedure EncodePort(ATerm: TEtfPort);
    procedure EncodeReference(ATerm: TEtfReference);
    procedure EncodeFun(ATerm: TEtfFun);
    { Dispatch }
    procedure EncodeTerm(ATerm: TEtfTerm);
    { Big-integer helpers }
    procedure EncodeSmallBig(const ABytes: TBytes; ASign: Byte);
    procedure EncodeLargeBig(const ABytes: TBytes; ASign: Byte);
  public
    constructor Create(AStream: TStream);
    procedure Encode(ATerm: TEtfTerm);
    class function EncodeToBytes(ATerm: TEtfTerm): TBytes;
    class procedure EncodeToStream(ATerm: TEtfTerm; AStream: TStream);
  end;

implementation

{ ------------------------------------------------------------------ }
{ Helper: Int64 → little-endian bytes                                 }
{ ------------------------------------------------------------------ }

function Int64ToLEBytes(V: Int64; out ASign: Byte): TBytes;
var
  U: UInt64;
  Len: Integer;
  I: Integer;
begin
  if V < 0 then
  begin
    ASign := 1;
    U := UInt64(-V);
  end
  else
  begin
    ASign := 0;
    U := UInt64(V);
  end;
  if U = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := 0;
    Exit;
  end;
  Len := 0;
  while (U shr (Len * 8)) <> 0 do Inc(Len);
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    Result[I] := Byte(U shr (I * 8));
end;

function HexToBigEndianBytes(const AHex: string; out ASign: Byte): TBytes;
var
  H: string;
  I, J: Integer;
  ByteCount: Integer;
begin
  H := AHex;
  if (Length(H) > 0) and (H[1] = '-') then
  begin
    ASign := 1;
    Delete(H, 1, 1);
  end
  else
    ASign := 0;
  ByteCount := (Length(H) + 1) div 2;
  SetLength(Result, ByteCount);
  { Big-endian hex → little-endian bytes }
  J := Length(H);
  for I := 0 to ByteCount - 1 do
  begin
    if J > 0 then
    begin
      Result[I] := StrToInt('$' + Copy(H, Max(1, J-1), Min(2, J)));
      Dec(J, 2);
    end
    else
      Result[I] := 0;
  end;
end;

{ ------------------------------------------------------------------ }
{ TEtfEncoder                                                         }
{ ------------------------------------------------------------------ }

constructor TEtfEncoder.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

procedure TEtfEncoder.WriteByte(B: Byte);
begin
  FStream.Write(B, 1);
end;

procedure TEtfEncoder.WriteBytes(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    FStream.Write(ABytes[0], Length(ABytes));
end;

procedure TEtfEncoder.WriteUInt16BE(V: UInt16);
var
  B: array[0..1] of Byte;
begin
  B[0] := (V shr 8) and $FF;
  B[1] := V and $FF;
  FStream.Write(B[0], 2);
end;

procedure TEtfEncoder.WriteUInt32BE(V: UInt32);
var
  B: array[0..3] of Byte;
begin
  B[0] := (V shr 24) and $FF;
  B[1] := (V shr 16) and $FF;
  B[2] := (V shr 8)  and $FF;
  B[3] :=  V         and $FF;
  FStream.Write(B[0], 4);
end;

procedure TEtfEncoder.WriteInt32BE(V: Int32);
begin
  WriteUInt32BE(UInt32(V));
end;

procedure TEtfEncoder.WriteUInt64BE(V: UInt64);
begin
  WriteUInt32BE(UInt32(V shr 32));
  WriteUInt32BE(UInt32(V and $FFFFFFFF));
end;

procedure TEtfEncoder.WriteDouble(V: Double);
var
  B: array[0..7] of Byte;
  Rev: array[0..7] of Byte;
  I: Integer;
begin
  Move(V, B[0], 8);
  {$IFDEF ENDIAN_LITTLE}
  for I := 0 to 7 do Rev[I] := B[7 - I];
  FStream.Write(Rev[0], 8);
  {$ELSE}
  FStream.Write(B[0], 8);
  {$ENDIF}
end;

procedure TEtfEncoder.WriteAtomBytes(const S: string);
var
  Bytes: TBytes;
  Len: Integer;
begin
  Len := Length(S);
  SetLength(Bytes, Len);
  if Len > 0 then
    Move(S[1], Bytes[0], Len);
  if Len <= 255 then
  begin
    WriteByte(TAG_SMALL_ATOM_UTF8_EXT);
    WriteByte(Len);
  end
  else
  begin
    WriteByte(TAG_ATOM_UTF8_EXT);
    WriteUInt16BE(Len);
  end;
  WriteBytes(Bytes);
end;

procedure TEtfEncoder.EncodeAtom(ATerm: TEtfAtom);
begin
  WriteAtomBytes(ATerm.Value);
end;

procedure TEtfEncoder.EncodeSmallBig(const ABytes: TBytes; ASign: Byte);
begin
  WriteByte(TAG_SMALL_BIG_EXT);
  WriteByte(Length(ABytes));
  WriteByte(ASign);
  WriteBytes(ABytes);
end;

procedure TEtfEncoder.EncodeLargeBig(const ABytes: TBytes; ASign: Byte);
begin
  WriteByte(TAG_LARGE_BIG_EXT);
  WriteUInt32BE(Length(ABytes));
  WriteByte(ASign);
  WriteBytes(ABytes);
end;

procedure TEtfEncoder.EncodeInteger(ATerm: TEtfInteger);
var
  V: Int64;
  Sign: Byte;
  Data: TBytes;
begin
  if ATerm.IsBig then
  begin
    Data := HexToBigEndianBytes(ATerm.BigNum, Sign);
    if Length(Data) <= 255 then
      EncodeSmallBig(Data, Sign)
    else
      EncodeLargeBig(Data, Sign);
    Exit;
  end;
  V := ATerm.Value;
  if (V >= 0) and (V <= 255) then
  begin
    WriteByte(TAG_SMALL_INTEGER_EXT);
    WriteByte(Byte(V));
  end
  else if (V >= Low(Int32)) and (V <= High(Int32)) then
  begin
    WriteByte(TAG_INTEGER_EXT);
    WriteInt32BE(Int32(V));
  end
  else
  begin
    { Int64 that doesn't fit Int32 — encode as SMALL_BIG_EXT }
    Data := Int64ToLEBytes(V, Sign);
    if Length(Data) <= 255 then
      EncodeSmallBig(Data, Sign)
    else
      EncodeLargeBig(Data, Sign);
  end;
end;

procedure TEtfEncoder.EncodeFloat(ATerm: TEtfFloat);
begin
  WriteByte(TAG_NEW_FLOAT_EXT);
  WriteDouble(ATerm.Value);
end;

procedure TEtfEncoder.EncodeBinary(ATerm: TEtfBinary);
begin
  if ATerm.IsBitBinary then
  begin
    WriteByte(TAG_BIT_BINARY_EXT);
    WriteUInt32BE(Length(ATerm.Data));
    WriteByte(ATerm.Bits);
  end
  else
  begin
    WriteByte(TAG_BINARY_EXT);
    WriteUInt32BE(Length(ATerm.Data));
  end;
  WriteBytes(ATerm.Data);
end;

procedure TEtfEncoder.EncodeString(ATerm: TEtfString);
var
  S: string;
  Len: Integer;
  Bytes: TBytes;
begin
  S := ATerm.Value;
  Len := Length(S);
  if Len > $FFFF then
    raise EEtfEncodeError.CreateFmt('String too long for STRING_EXT: %d chars', [Len]);
  WriteByte(TAG_STRING_EXT);
  WriteUInt16BE(Len);
  if Len > 0 then
  begin
    SetLength(Bytes, Len);
    Move(S[1], Bytes[0], Len);
    WriteBytes(Bytes);
  end;
end;

procedure TEtfEncoder.EncodeList(ATerm: TEtfList);
var
  I: Integer;
begin
  if ATerm.Count = 0 then
  begin
    WriteByte(TAG_NIL_EXT);
    Exit;
  end;
  WriteByte(TAG_LIST_EXT);
  WriteUInt32BE(ATerm.Count);
  for I := 0 to ATerm.Count - 1 do
    EncodeTerm(ATerm.Get(I));
  WriteByte(TAG_NIL_EXT);  { proper list tail }
end;

procedure TEtfEncoder.EncodeImproperList(ATerm: TEtfImproperList);
var
  I: Integer;
begin
  WriteByte(TAG_LIST_EXT);
  WriteUInt32BE(ATerm.Count);
  for I := 0 to ATerm.Count - 1 do
    EncodeTerm(ATerm.Get(I));
  if Assigned(ATerm.Tail) then
    EncodeTerm(ATerm.Tail)
  else
    WriteByte(TAG_NIL_EXT);
end;

procedure TEtfEncoder.EncodeTuple(ATerm: TEtfTuple);
var
  I: Integer;
begin
  if ATerm.Count <= 255 then
  begin
    WriteByte(TAG_SMALL_TUPLE_EXT);
    WriteByte(ATerm.Count);
  end
  else
  begin
    WriteByte(TAG_LARGE_TUPLE_EXT);
    WriteUInt32BE(ATerm.Count);
  end;
  for I := 0 to ATerm.Count - 1 do
    EncodeTerm(ATerm.Get(I));
end;

procedure TEtfEncoder.EncodeMap(ATerm: TEtfMap);
var
  I: Integer;
  Pair: TEtfMapPair;
begin
  WriteByte(TAG_MAP_EXT);
  WriteUInt32BE(ATerm.Count);
  for I := 0 to ATerm.Count - 1 do
  begin
    Pair := ATerm.PairAt(I);
    EncodeTerm(Pair.Key);
    EncodeTerm(Pair.Value);
  end;
end;

procedure TEtfEncoder.EncodePid(ATerm: TEtfPid);
begin
  WriteByte(TAG_NEW_PID_EXT);
  EncodeAtom(ATerm.Node);
  WriteUInt32BE(ATerm.Id);
  WriteUInt32BE(ATerm.Serial);
  WriteUInt32BE(ATerm.Creation);
end;

procedure TEtfEncoder.EncodePort(ATerm: TEtfPort);
begin
  WriteByte(TAG_NEW_PORT_EXT);
  EncodeAtom(ATerm.Node);
  WriteUInt64BE(ATerm.Id);
  WriteUInt32BE(ATerm.Creation);
end;

procedure TEtfEncoder.EncodeReference(ATerm: TEtfReference);
var
  I: Integer;
begin
  WriteByte(TAG_NEWER_REFERENCE_EXT);
  WriteUInt16BE(ATerm.IdCount);
  EncodeAtom(ATerm.Node);
  WriteUInt32BE(ATerm.Creation);
  for I := 0 to ATerm.IdCount - 1 do
    WriteUInt32BE(ATerm.IdAt(I));
end;

procedure TEtfEncoder.EncodeFun(ATerm: TEtfFun);
begin
  case ATerm.FunKind of
    efkExport:
    begin
      WriteByte(TAG_EXPORT_EXT);
      WriteAtomBytes(ATerm.Module);
      WriteAtomBytes(ATerm.&Function);
      WriteByte(TAG_SMALL_INTEGER_EXT);
      WriteByte(Byte(ATerm.Arity));
    end;
  else
    { For old/new fun we store raw data if available, otherwise raise }
    if Length(ATerm.RawData) > 0 then
      WriteBytes(ATerm.RawData)
    else
      raise EEtfEncodeError.Create(
        'Cannot encode non-export fun without raw data; use efkExport or provide RawData');
  end;
end;

procedure TEtfEncoder.EncodeTerm(ATerm: TEtfTerm);
begin
  if ATerm = nil then
    raise EEtfEncodeError.Create('Cannot encode nil TEtfTerm pointer');
  case ATerm.Kind of
    etkAtom:          EncodeAtom(TEtfAtom(ATerm));
    etkInteger:       EncodeInteger(TEtfInteger(ATerm));
    etkFloat:         EncodeFloat(TEtfFloat(ATerm));
    etkBinary:        EncodeBinary(TEtfBinary(ATerm));
    etkString:        EncodeString(TEtfString(ATerm));
    etkList:          EncodeList(TEtfList(ATerm));
    etkImproperList:  EncodeImproperList(TEtfImproperList(ATerm));
    etkTuple:         EncodeTuple(TEtfTuple(ATerm));
    etkMap,
    etkElixirStruct:  EncodeMap(TEtfMap(ATerm));
    etkPid:           EncodePid(TEtfPid(ATerm));
    etkPort:          EncodePort(TEtfPort(ATerm));
    etkReference:     EncodeReference(TEtfReference(ATerm));
    etkFun:           EncodeFun(TEtfFun(ATerm));
    etkNil:           WriteByte(TAG_NIL_EXT);
  else
    raise EEtfEncodeError.CreateFmt('Unknown term kind: %d', [Ord(ATerm.Kind)]);
  end;
end;

procedure TEtfEncoder.Encode(ATerm: TEtfTerm);
begin
  WriteByte(ETF_VERSION);
  EncodeTerm(ATerm);
end;

class function TEtfEncoder.EncodeToBytes(ATerm: TEtfTerm): TBytes;
var
  Stream: TBytesStream;
  Enc: TEtfEncoder;
begin
  Stream := TBytesStream.Create(nil);
  try
    Enc := TEtfEncoder.Create(Stream);
    try
      Enc.Encode(ATerm);
    finally
      Enc.Free;
    end;
    Result := Stream.Bytes;
    SetLength(Result, Stream.Size);
  finally
    Stream.Free;
  end;
end;

class procedure TEtfEncoder.EncodeToStream(ATerm: TEtfTerm; AStream: TStream);
var
  Enc: TEtfEncoder;
begin
  Enc := TEtfEncoder.Create(AStream);
  try
    Enc.Encode(ATerm);
  finally
    Enc.Free;
  end;
end;

end.
