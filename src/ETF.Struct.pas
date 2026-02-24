unit ETF.Struct;

{
  TEtfStructRegistry — global registry mapping Elixir struct names to Pascal classes.

  When the ETF decoder encounters a MAP_EXT with a __struct__ key, it calls
  TEtfStructRegistry.FindClass(StructName) to look up a registered Pascal class.
  If found, TEtfMapper fills the class instance via RTTI.

  Registration:
    TEtfStructRegistry.RegisterClass('Elixir.MyApp.User', TUser);

  Or via the generic helper (reads EtfStructAttribute automatically):
    TEtfStructRegistry.Register(TUser);    { non-generic variant }

  The mapper in ETF.RTTI uses this registry automatically.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections,
  ETF.Attributes;

type
  TEtfStructRegistry = class
  private
    class var FMap: specialize TDictionary<string, TClass>;
    class procedure EnsureMap;
  public
    { Register a Pascal class under an explicit Elixir struct name }
    class procedure RegisterClass(const AStructName: string; AClass: TClass);

    { Register a class by reading its EtfStructAttribute.
      Raises EEtfMappingError if the attribute is absent. }
    class procedure Register(AClass: TClass);

    { Find a class by Elixir struct name; returns nil if not found }
    class function FindClass(const AStructName: string): TClass;

    { True if AStructName is registered }
    class function IsRegistered(const AStructName: string): Boolean;

    { Remove all registrations (useful in tests) }
    class procedure Clear;

    { Returns a snapshot of all registered struct names }
    class function RegisteredNames: specialize TArray<string>;

    class destructor Destroy;
  end;

implementation

uses
  ETF.Types;

{ TEtfStructRegistry }

class procedure TEtfStructRegistry.EnsureMap;
begin
  if FMap = nil then
    FMap := specialize TDictionary<string, TClass>.Create;
end;

class procedure TEtfStructRegistry.RegisterClass(const AStructName: string; AClass: TClass);
begin
  EnsureMap;
  FMap.AddOrSetValue(AStructName, AClass);
end;

class procedure TEtfStructRegistry.Register(AClass: TClass);
var
  StructName: string;
begin
  StructName := TEtfAttributeHelper.GetStructName(AClass);
  if StructName = '' then
    raise EEtfMappingError.CreateFmt(
      'Class %s has no EtfStructAttribute; use RegisterClass() with an explicit name',
      [AClass.ClassName]);
  RegisterClass(StructName, AClass);
end;

class function TEtfStructRegistry.FindClass(const AStructName: string): TClass;
begin
  EnsureMap;
  if not FMap.TryGetValue(AStructName, Result) then
    Result := nil;
end;

class function TEtfStructRegistry.IsRegistered(const AStructName: string): Boolean;
begin
  EnsureMap;
  Result := FMap.ContainsKey(AStructName);
end;

class procedure TEtfStructRegistry.Clear;
begin
  EnsureMap;
  FMap.Clear;
end;

class function TEtfStructRegistry.RegisteredNames: specialize TArray<string>;
begin
  EnsureMap;
  Result := FMap.Keys.ToArray;
end;

class destructor TEtfStructRegistry.Destroy;
begin
  FreeAndNil(FMap);
end;

end.
