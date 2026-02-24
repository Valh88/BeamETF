unit ETF.Decoder;

{
  Erlang External Term Format — binary decoder.

  Supported tags (per OTP documentation):
    SMALL_INTEGER_EXT   (97)
    INTEGER_EXT         (98)
    FLOAT_EXT           (99)   — legacy 31-byte text float
    ATOM_EXT            (100)
    REFERENCE_EXT       (101)
    PORT_EXT            (102)
    PID_EXT             (103)
    SMALL_TUPLE_EXT     (104)
    LARGE_TUPLE_EXT     (105)
    NIL_EXT             (106)
    STRING_EXT          (107)
    LIST_EXT            (108)
    BINARY_EXT          (109)
    SMALL_BIG_EXT       (110)
    LARGE_BIG_EXT       (111)
    NEW_FUN_EXT         (112)
    EXPORT_EXT          (113)
    NEW_REFERENCE_EXT   (114)
    SMALL_ATOM_EXT      (115)
    MAP_EXT             (116)
    FUN_EXT             (117)
    ATOM_UTF8_EXT       (118)
    SMALL_ATOM_UTF8_EXT (119)
    NEW_FLOAT_EXT       (70/'F')
    BIT_BINARY_EXT      (77/'M')
    NEW_PID_EXT         (88/'X')
    NEW_PORT_EXT        (89/'Y')
    NEWER_REFERENCE_EXT (90/'Z')
    ATOM_CACHE_REF      (82)

  Usage:
    Term := TEtfDecoder.Decode(Bytes);            // full ETF blob (with version byte)
    Term := TEtfDecoder.DecodeTerm(Stream);       // single term from stream (no version)
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  ETF.Types,
  ETF.Atom;

type
  TEtfDecoder = class
  private
    FStream: TStream;
    FAtomRefTable: TEtfAtomRefTable;
    FOwnStream: Boolean;
    { Low-level read helpers }
    function ReadByte: Byte;
    function ReadBytes(ACount: Integer): TBytes;
    function ReadUInt16BE: UInt16;
    function ReadUInt32BE: UInt32;
    function ReadInt32BE: Int32;
    function ReadUInt64BE: UInt64;
    function ReadDouble: Double;
    function ReadAtomStr(ALen: Integer): string;
    { Tag-specific decoders }
    function DecodeAtomCacheRef: TEtfAtom;
    function DecodeSmallInteger: TEtfInteger;
    function DecodeInteger: TEtfInteger;
    function DecodeFloat: TEtfFloat;
    function DecodeNewFloat: TEtfFloat;
    function DecodeAtomExt(AUtf8: Boolean; ASmall: Boolean): TEtfAtom;
    function DecodeSmallBig: TEtfInteger;
    function DecodeLargeBig: TEtfInteger;
    function DecodeSmallTuple: TEtfTuple;
    function DecodeLargeTuple: TEtfTuple;
    function DecodeTupleN(ACount: Integer): TEtfTuple;
    function DecodeNilExt: TEtfList;
    function DecodeStringExt: TEtfString;
    function DecodeListExt: TEtfTerm;  { may return TEtfList or TEtfImproperList }
    function DecodeBinaryExt: TEtfBinary;
    function DecodeBitBinaryExt: TEtfBinary;
    function DecodeMapExt: TEtfTerm;   { may return TEtfMap or TEtfElixirStruct }
    function DecodePidExt(ANew: Boolean): TEtfPid;
    function DecodePortExt(ANew: Boolean): TEtfPort;
    function DecodeReferenceExt: TEtfReference;
    function DecodeNewReferenceExt: TEtfReference;
    function DecodeNewerReferenceExt: TEtfReference;
    function DecodeFunExt: TEtfFun;
    function DecodeNewFunExt: TEtfFun;
    function DecodeExportExt: TEtfFun;
    { Reads one term (the tag byte first) }
    function DecodeTermInternal: TEtfTerm;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean = False);
    destructor Destroy; override;
    { Decode one term from the current stream position (no version byte check) }
    function DecodeTerm: TEtfTerm;
    { Class-method shortcuts }
    class function Decode(const ABytes: TBytes): TEtfTerm;
    class function DecodeStream(AStream: TStream): TEtfTerm;
    property AtomRefTable: TEtfAtomRefTable read FAtomRefTable;
  end;

implementation

{ ------------------------------------------------------------------ }
{ Helpers                                                             }
{ ------------------------------------------------------------------ }

function BigBytesToInt64(const ABytes: TBytes; ASign: Byte): TEtfInteger;
{ Erlang big-integer: little-endian bytes, ASign=0 positive, 1 negative }
var
  I: Integer;
  Val: UInt64;
  IsOverflow: Boolean;
  Hex: string;
begin
  IsOverflow := Length(ABytes) > 8;
  if not IsOverflow then
  begin
    Val := 0;
    for I := High(ABytes) downto 0 do
      Val := (Val shl 8) or ABytes[I];
    if ASign = 0 then
    begin
      if Val > UInt64(High(Int64)) then
      begin
        IsOverflow := True;
        Hex := IntToHex(Val, 16);
      end
      else
        Result := TEtfInteger.Create(Int64(Val));
    end
    else
    begin
      if Val > UInt64(High(Int64)) + 1 then
      begin
        IsOverflow := True;
        Hex := '-' + IntToHex(Val, 16);
      end
      else
        Result := TEtfInteger.Create(-Int64(Val));
    end;
    if not IsOverflow then Exit;
  end;
  { Build hex string from bytes (big-endian display) }
  if Hex = '' then
  begin
    Hex := '';
    for I := High(ABytes) downto 0 do
      Hex := Hex + IntToHex(ABytes[I], 2);
    if ASign <> 0 then Hex := '-' + Hex;
  end;
  Result := TEtfInteger.CreateBig(Hex, ASign);
end;

{ ------------------------------------------------------------------ }
{ TEtfDecoder                                                         }
{ ------------------------------------------------------------------ }

constructor TEtfDecoder.Create(AStream: TStream; AOwnsStream: Boolean);
begin
  inherited Create;
  FStream := AStream;
  FOwnStream := AOwnsStream;
  FAtomRefTable := TEtfAtomRefTable.Create;
end;

destructor TEtfDecoder.Destroy;
begin
  FAtomRefTable.Free;
  if FOwnStream then FStream.Free;
  inherited Destroy;
end;

function TEtfDecoder.ReadByte: Byte;
begin
  if FStream.Read(Result, 1) <> 1 then
    raise EEtfDecodeError.Create('Unexpected end of ETF stream');
end;

function TEtfDecoder.ReadBytes(ACount: Integer): TBytes;
begin
  SetLength(Result, ACount);
  if ACount = 0 then Exit;
  if FStream.Read(Result[0], ACount) <> ACount then
    raise EEtfDecodeError.CreateFmt('Expected %d bytes, stream ended', [ACount]);
end;

function TEtfDecoder.ReadUInt16BE: UInt16;
var
  B: array[0..1] of Byte;
begin
  if FStream.Read(B[0], 2) <> 2 then
    raise EEtfDecodeError.Create('Unexpected end of ETF stream (uint16)');
  Result := (UInt16(B[0]) shl 8) or B[1];
end;

function TEtfDecoder.ReadUInt32BE: UInt32;
var
  B: array[0..3] of Byte;
begin
  if FStream.Read(B[0], 4) <> 4 then
    raise EEtfDecodeError.Create('Unexpected end of ETF stream (uint32)');
  Result := (UInt32(B[0]) shl 24) or (UInt32(B[1]) shl 16)
          or (UInt32(B[2]) shl 8)  or B[3];
end;

function TEtfDecoder.ReadInt32BE: Int32;
begin
  Result := Int32(ReadUInt32BE);
end;

function TEtfDecoder.ReadUInt64BE: UInt64;
var
  Hi, Lo: UInt32;
begin
  Hi := ReadUInt32BE;
  Lo := ReadUInt32BE;
  Result := (UInt64(Hi) shl 32) or Lo;
end;

function TEtfDecoder.ReadDouble: Double;
var
  B: array[0..7] of Byte;
  I: Integer;
  Rev: array[0..7] of Byte;
begin
  if FStream.Read(B[0], 8) <> 8 then
    raise EEtfDecodeError.Create('Unexpected end of ETF stream (double)');
  { ETF stores doubles as big-endian IEEE 754 }
  {$IFDEF ENDIAN_LITTLE}
  for I := 0 to 7 do Rev[I] := B[7 - I];
  Move(Rev[0], Result, 8);
  {$ELSE}
  Move(B[0], Result, 8);
  {$ENDIF}
end;

function TEtfDecoder.ReadAtomStr(ALen: Integer): string;
var
  Buf: TBytes;
begin
  Buf := ReadBytes(ALen);
  if ALen = 0 then Exit('');
  SetLength(Result, ALen);
  Move(Buf[0], Result[1], ALen);
end;

{ ------------------------------------------------------------------ }

function TEtfDecoder.DecodeAtomCacheRef: TEtfAtom;
var
  Idx: Byte;
  AtomStr: string;
begin
  Idx := ReadByte;
  AtomStr := FAtomRefTable.Retrieve(Idx);
  Result := TEtfAtom.Create(AtomStr);
end;

function TEtfDecoder.DecodeSmallInteger: TEtfInteger;
begin
  Result := TEtfInteger.Create(ReadByte);
end;

function TEtfDecoder.DecodeInteger: TEtfInteger;
begin
  Result := TEtfInteger.Create(ReadInt32BE);
end;

function TEtfDecoder.DecodeFloat: TEtfFloat;
var
  Buf: TBytes;
  S: string;
  V: Double;
begin
  { 31-byte ASCII float string (legacy) }
  Buf := ReadBytes(31);
  SetLength(S, 31);
  Move(Buf[0], S[1], 31);
  S := TrimRight(S);
  { Replace Erlang-style exponent notation if needed }
  V := StrToFloat(S, TFormatSettings.Create('C'));
  Result := TEtfFloat.Create(V);
end;

function TEtfDecoder.DecodeNewFloat: TEtfFloat;
begin
  Result := TEtfFloat.Create(ReadDouble);
end;

function TEtfDecoder.DecodeAtomExt(AUtf8: Boolean; ASmall: Boolean): TEtfAtom;
var
  Len: Integer;
  S: string;
begin
  if ASmall then
    Len := ReadByte
  else
    Len := ReadUInt16BE;
  S := ReadAtomStr(Len);
  S := EtfInternAtom(S);
  Result := TEtfAtom.Create(S);
end;

function TEtfDecoder.DecodeSmallBig: TEtfInteger;
var
  N: Byte;
  Sign: Byte;
  Data: TBytes;
begin
  N := ReadByte;
  Sign := ReadByte;
  Data := ReadBytes(N);
  Result := BigBytesToInt64(Data, Sign);
end;

function TEtfDecoder.DecodeLargeBig: TEtfInteger;
var
  N: UInt32;
  Sign: Byte;
  Data: TBytes;
begin
  N := ReadUInt32BE;
  Sign := ReadByte;
  Data := ReadBytes(N);
  Result := BigBytesToInt64(Data, Sign);
end;

function TEtfDecoder.DecodeTupleN(ACount: Integer): TEtfTuple;
var
  I: Integer;
begin
  Result := TEtfTuple.Create;
  try
    for I := 0 to ACount - 1 do
      Result.Add(DecodeTermInternal);
  except
    Result.Free;
    raise;
  end;
end;

function TEtfDecoder.DecodeSmallTuple: TEtfTuple;
begin
  Result := DecodeTupleN(ReadByte);
end;

function TEtfDecoder.DecodeLargeTuple: TEtfTuple;
begin
  Result := DecodeTupleN(ReadUInt32BE);
end;

function TEtfDecoder.DecodeNilExt: TEtfList;
begin
  { The empty list [] }
  Result := TEtfList.Create;
end;

function TEtfDecoder.DecodeStringExt: TEtfString;
var
  Len: UInt16;
  Buf: TBytes;
  S: string;
begin
  Len := ReadUInt16BE;
  Buf := ReadBytes(Len);
  if Len > 0 then
  begin
    SetLength(S, Len);
    Move(Buf[0], S[1], Len);
  end
  else
    S := '';
  Result := TEtfString.Create(S);
end;

function TEtfDecoder.DecodeListExt: TEtfTerm;
var
  Len: UInt32;
  I: Integer;
  Tail: TEtfTerm;
  Proper: TEtfList;
  Improper: TEtfImproperList;
begin
  Len := ReadUInt32BE;
  { Decode elements }
  Proper := TEtfList.Create;
  try
    for I := 0 to Int64(Len) - 1 do
      Proper.Add(DecodeTermInternal);
    { Decode tail — if NIL_EXT, proper list; otherwise improper }
    Tail := DecodeTermInternal;
    if (Tail is TEtfList) and (TEtfList(Tail).Count = 0) then
    begin
      Tail.Free;
      Result := Proper;
    end
    else
    begin
      { Convert to improper list }
      Improper := TEtfImproperList.Create;
      try
        for I := 0 to Proper.Count - 1 do
        begin
          Proper.Elements[I].Owned := False;  { transfer ownership }
          Improper.Add(Proper.Elements[I]);
          Proper.Elements[I].Owned := True;
        end;
        Improper.Tail := Tail;
        Result := Improper;
      except
        Improper.Free;
        Tail.Free;
        raise;
      end;
      { Free Proper shell without freeing its elements (already moved) }
      Proper.Elements.OwnsObjects := False;
      Proper.Free;
    end;
  except
    Proper.Free;
    raise;
  end;
end;

function TEtfDecoder.DecodeBinaryExt: TEtfBinary;
var
  Len: UInt32;
  Data: TBytes;
begin
  Len := ReadUInt32BE;
  Data := ReadBytes(Len);
  Result := TEtfBinary.Create(Data, 8);
end;

function TEtfDecoder.DecodeBitBinaryExt: TEtfBinary;
var
  Len: UInt32;
  Bits: Byte;
  Data: TBytes;
begin
  Len := ReadUInt32BE;
  Bits := ReadByte;
  Data := ReadBytes(Len);
  Result := TEtfBinary.Create(Data, Bits);
end;

function TEtfDecoder.DecodeMapExt: TEtfTerm;
var
  Arity: UInt32;
  I: Integer;
  Key, Val: TEtfTerm;
  StructNameTerm: TEtfTerm;
  StructMap: TEtfElixirStruct;
  PlainMap: TEtfMap;
  PairKeys: array of TEtfTerm;
  PairVals: array of TEtfTerm;
  StructIdx: Integer;
begin
  Arity := ReadUInt32BE;
  SetLength(PairKeys, Arity);
  SetLength(PairVals, Arity);
  StructIdx := -1;
  for I := 0 to Int64(Arity) - 1 do
  begin
    PairKeys[I] := DecodeTermInternal;
    PairVals[I] := DecodeTermInternal;
    if (PairKeys[I] is TEtfAtom)
       and (TEtfAtom(PairKeys[I]).Value = ATOM_STRUCT)
       and (PairVals[I] is TEtfAtom) then
      StructIdx := I;
  end;

  if StructIdx >= 0 then
  begin
    StructNameTerm := PairVals[StructIdx];
    StructMap := TEtfElixirStruct.Create(TEtfAtom(StructNameTerm).Value);
    try
      for I := 0 to Int64(Arity) - 1 do
        StructMap.Put(PairKeys[I], PairVals[I]);
    except
      StructMap.Free;
      raise;
    end;
    Result := StructMap;
  end
  else
  begin
    PlainMap := TEtfMap.Create;
    try
      for I := 0 to Int64(Arity) - 1 do
        PlainMap.Put(PairKeys[I], PairVals[I]);
    except
      PlainMap.Free;
      for I := 0 to Int64(Arity) - 1 do
      begin
        PairKeys[I].Free;
        PairVals[I].Free;
      end;
      raise;
    end;
    Result := PlainMap;
  end;
end;

function TEtfDecoder.DecodePidExt(ANew: Boolean): TEtfPid;
var
  Node: TEtfAtom;
  Id, Serial, Creation: UInt32;
begin
  Node := TEtfAtom(DecodeTermInternal);
  Id := ReadUInt32BE;
  Serial := ReadUInt32BE;
  if ANew then
    Creation := ReadUInt32BE
  else
    Creation := ReadByte;
  Result := TEtfPid.Create(Node, Id, Serial, Creation);
end;

function TEtfDecoder.DecodePortExt(ANew: Boolean): TEtfPort;
var
  Node: TEtfAtom;
  Id: UInt64;
  Creation: UInt32;
begin
  Node := TEtfAtom(DecodeTermInternal);
  if ANew then
  begin
    Id := ReadUInt64BE;
    Creation := ReadUInt32BE;
  end
  else
  begin
    Id := ReadUInt32BE;
    Creation := ReadByte;
  end;
  Result := TEtfPort.Create(Node, Id, Creation);
end;

function TEtfDecoder.DecodeReferenceExt: TEtfReference;
var
  Node: TEtfAtom;
  Id: UInt32;
  Creation: Byte;
begin
  Node := TEtfAtom(DecodeTermInternal);
  Id := ReadUInt32BE;
  Creation := ReadByte;
  Result := TEtfReference.Create(Node, [Id], Creation);
end;

function TEtfDecoder.DecodeNewReferenceExt: TEtfReference;
var
  Len: UInt16;
  Node: TEtfAtom;
  Creation: Byte;
  Ids: array of UInt32;
  I: Integer;
begin
  Len := ReadUInt16BE;
  Node := TEtfAtom(DecodeTermInternal);
  Creation := ReadByte;
  SetLength(Ids, Len);
  for I := 0 to Len - 1 do
    Ids[I] := ReadUInt32BE;
  Result := TEtfReference.Create(Node, Ids, Creation);
end;

function TEtfDecoder.DecodeNewerReferenceExt: TEtfReference;
var
  Len: UInt16;
  Node: TEtfAtom;
  Creation: UInt32;
  Ids: array of UInt32;
  I: Integer;
begin
  Len := ReadUInt16BE;
  Node := TEtfAtom(DecodeTermInternal);
  Creation := ReadUInt32BE;
  SetLength(Ids, Len);
  for I := 0 to Len - 1 do
    Ids[I] := ReadUInt32BE;
  Result := TEtfReference.Create(Node, Ids, Creation);
end;

function TEtfDecoder.DecodeFunExt: TEtfFun;
var
  NumFree: UInt32;
  Pid: TEtfPid;
  Module, FuncName: string;
  IndexTerm, UniqTerm: TEtfTerm;
  I: Integer;
  FreeTerm: TEtfTerm;
begin
  NumFree := ReadUInt32BE;
  Pid := TEtfPid(DecodeTermInternal);
  Module := TEtfAtom(DecodeTermInternal).Value;
  IndexTerm := DecodeTermInternal;
  UniqTerm  := DecodeTermInternal;
  Result := TEtfFun.Create(efkOldFun, Module, '', -1);
  for I := 0 to Int64(NumFree) - 1 do
  begin
    FreeTerm := DecodeTermInternal;
    FreeTerm.Free;
  end;
  Pid.Free;
  IndexTerm.Free;
  UniqTerm.Free;
end;

function TEtfDecoder.DecodeNewFunExt: TEtfFun;
var
  Size: UInt32;
  Arity: Byte;
  Uniq: TBytes;
  Index: UInt32;
  NumFree: UInt32;
  Module, FuncName: string;
  OldIndex, OldUniq: TEtfTerm;
  Pid: TEtfPid;
  I: Integer;
  FreeTerm: TEtfTerm;
begin
  Size := ReadUInt32BE;
  Arity := ReadByte;
  Uniq := ReadBytes(16);
  Index := ReadUInt32BE;
  NumFree := ReadUInt32BE;
  Module := TEtfAtom(DecodeTermInternal).Value;
  OldIndex := DecodeTermInternal;
  OldUniq := DecodeTermInternal;
  Pid := TEtfPid(DecodeTermInternal);
  Result := TEtfFun.Create(efkNewFun, Module, '', Arity);
  for I := 0 to Int64(NumFree) - 1 do
  begin
    FreeTerm := DecodeTermInternal;
    FreeTerm.Free;
  end;
  OldIndex.Free;
  OldUniq.Free;
  Pid.Free;
end;

function TEtfDecoder.DecodeExportExt: TEtfFun;
var
  Module, FuncName: string;
  ArityTerm: TEtfTerm;
  Arity: Integer;
begin
  Module := TEtfAtom(DecodeTermInternal).Value;
  FuncName := TEtfAtom(DecodeTermInternal).Value;
  ArityTerm := DecodeTermInternal;
  if ArityTerm is TEtfInteger then
    Arity := TEtfInteger(ArityTerm).Value
  else
    Arity := -1;
  ArityTerm.Free;
  Result := TEtfFun.Create(efkExport, Module, FuncName, Arity);
end;

{ ------------------------------------------------------------------ }
{ Main dispatch                                                        }
{ ------------------------------------------------------------------ }

function TEtfDecoder.DecodeTermInternal: TEtfTerm;
var
  Tag: Byte;
begin
  Tag := ReadByte;
  case Tag of
    TAG_ATOM_CACHE_REF:        Result := DecodeAtomCacheRef;
    TAG_SMALL_INTEGER_EXT:     Result := DecodeSmallInteger;
    TAG_INTEGER_EXT:           Result := DecodeInteger;
    TAG_FLOAT_EXT:             Result := DecodeFloat;
    TAG_NEW_FLOAT_EXT:         Result := DecodeNewFloat;
    TAG_ATOM_EXT:              Result := DecodeAtomExt(False, False);
    TAG_ATOM_UTF8_EXT:         Result := DecodeAtomExt(True,  False);
    TAG_SMALL_ATOM_EXT:        Result := DecodeAtomExt(False, True);
    TAG_SMALL_ATOM_UTF8_EXT:   Result := DecodeAtomExt(True,  True);
    TAG_SMALL_BIG_EXT:         Result := DecodeSmallBig;
    TAG_LARGE_BIG_EXT:         Result := DecodeLargeBig;
    TAG_SMALL_TUPLE_EXT:       Result := DecodeSmallTuple;
    TAG_LARGE_TUPLE_EXT:       Result := DecodeLargeTuple;
    TAG_NIL_EXT:               Result := DecodeNilExt;
    TAG_STRING_EXT:            Result := DecodeStringExt;
    TAG_LIST_EXT:              Result := DecodeListExt;
    TAG_BINARY_EXT:            Result := DecodeBinaryExt;
    TAG_BIT_BINARY_EXT:        Result := DecodeBitBinaryExt;
    TAG_MAP_EXT:               Result := DecodeMapExt;
    TAG_PID_EXT:               Result := DecodePidExt(False);
    TAG_NEW_PID_EXT:           Result := DecodePidExt(True);
    TAG_PORT_EXT:              Result := DecodePortExt(False);
    TAG_NEW_PORT_EXT:          Result := DecodePortExt(True);
    TAG_REFERENCE_EXT:         Result := DecodeReferenceExt;
    TAG_NEW_REFERENCE_EXT:     Result := DecodeNewReferenceExt;
    TAG_NEWER_REFERENCE_EXT:   Result := DecodeNewerReferenceExt;
    TAG_FUN_EXT:               Result := DecodeFunExt;
    TAG_NEW_FUN_EXT:           Result := DecodeNewFunExt;
    TAG_EXPORT_EXT:            Result := DecodeExportExt;
  else
    raise EEtfDecodeError.CreateFmt('Unknown ETF tag: %d (0x%x)', [Tag, Tag]);
  end;
end;

function TEtfDecoder.DecodeTerm: TEtfTerm;
begin
  Result := DecodeTermInternal;
end;

class function TEtfDecoder.Decode(const ABytes: TBytes): TEtfTerm;
var
  Stream: TBytesStream;
  Dec: TEtfDecoder;
  VerByte: Byte;
begin
  Stream := TBytesStream.Create(ABytes);
  try
    Dec := TEtfDecoder.Create(Stream, False);
    try
      { Check ETF version byte }
      VerByte := Dec.ReadByte;
      if VerByte <> ETF_VERSION then
        raise EEtfDecodeError.CreateFmt(
          'Invalid ETF version byte: %d (expected %d)', [VerByte, ETF_VERSION]);
      Result := Dec.DecodeTerm;
    finally
      Dec.Free;
    end;
  finally
    Stream.Free;
  end;
end;

class function TEtfDecoder.DecodeStream(AStream: TStream): TEtfTerm;
var
  Dec: TEtfDecoder;
  VerByte: Byte;
begin
  Dec := TEtfDecoder.Create(AStream, False);
  try
    VerByte := Dec.ReadByte;
    if VerByte <> ETF_VERSION then
      raise EEtfDecodeError.CreateFmt(
        'Invalid ETF version byte: %d (expected %d)', [VerByte, ETF_VERSION]);
    Result := Dec.DecodeTerm;
  finally
    Dec.Free;
  end;
end;

end.
