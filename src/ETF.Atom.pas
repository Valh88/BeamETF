unit ETF.Atom;

{
  Atom cache/interning for ETF decoding.

  TEtfAtomCache provides a global table of interned atom strings so that
  repeated atoms don't allocate duplicate strings.  The Erlang Distribution
  Protocol also maintains a per-connection 255-slot atom cache reference table;
  TEtfAtomRefTable models that.

  Well-known atoms (nil, true, false, ok, error, __struct__) are pre-cached
  at unit initialization so they are always available.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections;

type
  { Thread-unsafe global string cache — intern atoms to avoid duplicates }
  TEtfAtomCache = class
  private
    FTable: specialize TDictionary<string, string>;
    class var FInstance: TEtfAtomCache;
  public
    constructor Create;
    destructor Destroy; override;
    { Returns an interned copy of AAtom.  Subsequent calls with equal strings
      return the exact same string reference from the internal table. }
    function Intern(const AAtom: string): string;
    procedure Clear;
    function Count: Integer;
    class function Instance: TEtfAtomCache;
    class procedure FreeInstance;
  end;

  { Per-connection 255-slot atom cache reference table (Erlang dist protocol) }
  TEtfAtomRefTable = class
  private
    FSlots: array[0..254] of string;
    FUsed: array[0..254] of Boolean;
  public
    constructor Create;
    procedure Store(AIndex: Byte; const AAtom: string);
    function Retrieve(AIndex: Byte): string;
    function IsUsed(AIndex: Byte): Boolean;
    procedure Clear;
  end;

{ Global interning shortcut — equivalent to TEtfAtomCache.Instance.Intern }
function EtfInternAtom(const AAtom: string): string;

const
  { Pre-interned well-known atoms — use these constants to avoid string literals }
  CACHED_NIL       = 'nil';
  CACHED_TRUE      = 'true';
  CACHED_FALSE     = 'false';
  CACHED_OK        = 'ok';
  CACHED_ERROR     = 'error';
  CACHED_STRUCT    = '__struct__';
  CACHED_UNDEFINED = 'undefined';

implementation

{ TEtfAtomCache }

constructor TEtfAtomCache.Create;
begin
  inherited Create;
  FTable := specialize TDictionary<string, string>.Create;
  { Pre-load well-known atoms }
  FTable.AddOrSetValue(CACHED_NIL,       CACHED_NIL);
  FTable.AddOrSetValue(CACHED_TRUE,      CACHED_TRUE);
  FTable.AddOrSetValue(CACHED_FALSE,     CACHED_FALSE);
  FTable.AddOrSetValue(CACHED_OK,        CACHED_OK);
  FTable.AddOrSetValue(CACHED_ERROR,     CACHED_ERROR);
  FTable.AddOrSetValue(CACHED_STRUCT,    CACHED_STRUCT);
  FTable.AddOrSetValue(CACHED_UNDEFINED, CACHED_UNDEFINED);
end;

destructor TEtfAtomCache.Destroy;
begin
  FTable.Free;
  inherited Destroy;
end;

function TEtfAtomCache.Intern(const AAtom: string): string;
begin
  if not FTable.TryGetValue(AAtom, Result) then
  begin
    FTable.AddOrSetValue(AAtom, AAtom);
    Result := AAtom;
  end;
end;

procedure TEtfAtomCache.Clear;
begin
  FTable.Clear;
  FTable.AddOrSetValue(CACHED_NIL,       CACHED_NIL);
  FTable.AddOrSetValue(CACHED_TRUE,      CACHED_TRUE);
  FTable.AddOrSetValue(CACHED_FALSE,     CACHED_FALSE);
  FTable.AddOrSetValue(CACHED_OK,        CACHED_OK);
  FTable.AddOrSetValue(CACHED_ERROR,     CACHED_ERROR);
  FTable.AddOrSetValue(CACHED_STRUCT,    CACHED_STRUCT);
  FTable.AddOrSetValue(CACHED_UNDEFINED, CACHED_UNDEFINED);
end;

function TEtfAtomCache.Count: Integer;
begin
  Result := FTable.Count;
end;

class function TEtfAtomCache.Instance: TEtfAtomCache;
begin
  if FInstance = nil then
    FInstance := TEtfAtomCache.Create;
  Result := FInstance;
end;

class procedure TEtfAtomCache.FreeInstance;
begin
  FreeAndNil(FInstance);
end;

{ TEtfAtomRefTable }

constructor TEtfAtomRefTable.Create;
begin
  inherited Create;
  FillChar(FUsed, SizeOf(FUsed), 0);
end;

procedure TEtfAtomRefTable.Store(AIndex: Byte; const AAtom: string);
begin
  FSlots[AIndex] := TEtfAtomCache.Instance.Intern(AAtom);
  FUsed[AIndex] := True;
end;

function TEtfAtomRefTable.Retrieve(AIndex: Byte): string;
begin
  if not FUsed[AIndex] then
    raise ERangeError.CreateFmt('Atom cache ref slot %d is not populated', [AIndex]);
  Result := FSlots[AIndex];
end;

function TEtfAtomRefTable.IsUsed(AIndex: Byte): Boolean;
begin
  Result := FUsed[AIndex];
end;

procedure TEtfAtomRefTable.Clear;
var
  I: Integer;
begin
  for I := 0 to 254 do
    FSlots[I] := '';
  FillChar(FUsed, SizeOf(FUsed), 0);
end;

{ Global helper }

function EtfInternAtom(const AAtom: string): string;
begin
  Result := TEtfAtomCache.Instance.Intern(AAtom);
end;

initialization

finalization
  TEtfAtomCache.FreeInstance;

end.
