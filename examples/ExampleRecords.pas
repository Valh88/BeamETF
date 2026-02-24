unit ExampleRecords;

{
  Record types used by the EtfParser example.

  Must be compiled with {$mode delphi} so that
    {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  and attribute syntax on fields are available.

  The {$RTTI EXPLICIT ...} directive must appear INSIDE the type block,
  directly before each record declaration.
}

{$mode delphi}

interface

uses
  ETF.Attributes;

type
  // Stack-friendly mirror of Elixir %User{}
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  TUserRecord = record
    [EtfField('id')]
    Id: Integer;
    [EtfField('name')]
    Name: string;
    [EtfField('email')]
    Email: string;
    [EtfField('active')]
    Active: Boolean;
    [EtfField('score')]
    Score: Double;
    [EtfField('role')]
    [EtfAsAtom]
    Role: string;
  end;

  // Stack-friendly mirror of Elixir %Address{}
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  TAddressRecord = record
    [EtfField('street')]
    Street: string;
    [EtfField('city')]
    City: string;
    [EtfField('country')]
    Country: string;
  end;

implementation

end.
