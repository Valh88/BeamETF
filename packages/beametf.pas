{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit BeamETF;

{$warn 5023 off : no warning about unused units}
interface

uses
  ETF.Types, ETF.Atom, ETF.Decoder, ETF.Encoder, ETF.Attributes, ETF.Struct, 
  ETF.RTTI, ETF.RecordMap, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('BeamETF', @Register);
end.
