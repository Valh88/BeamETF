unit testrecords;

{
  Record types used by TTestEtfRecord in testbeam.pas.

  Must be a separate unit compiled in {$mode delphi} so that
  {$RTTI EXPLICIT FIELDS(...)} and attribute syntax work correctly.
  The main test unit (testbeam.pas) stays in {$mode objfpc}.

  IMPORTANT: {$RTTI EXPLICIT FIELDS([...])} must appear INSIDE the type block,
  directly before the record declaration (not before the 'type' keyword).
}

{$mode delphi}

interface

uses
  ETF.Attributes;

type
  // Simple flat record — mirrors Elixir %User{}
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  TUserRecord = record
    [EtfField('id')]
    [EtfRequired]
    Id: Integer;
    [EtfField('name')]
    Name: string;
    [EtfField('active')]
    Active: Boolean;
    [EtfField('score')]
    Score: Double;
    [EtfIgnore]
    InternalTag: string;
  end;

  // Record with atom-encoded string field
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  TRoleRecord = record
    [EtfField('id')]
    Id: Integer;
    [EtfField('role')]
    [EtfAsAtom]
    Role: string;
  end;

  // Enum type used in TStatusRecord
  TStatusEnum = (seActive, seInactive, seBanned);

  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  TStatusRecord = record
    [EtfField('id')]
    Id: Integer;
    [EtfField('status')]
    Status: TStatusEnum;
  end;

  // Nested: used inside TProfileRecord
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  [EtfStruct('Elixir.Address')]
  TAddressRecord = record
    [EtfField('street')]
    Street: string;
    [EtfField('city')]
    City: string;
    [EtfField('country')]
    Country: string;
  end;

  // Record with nested record field
  {$RTTI EXPLICIT FIELDS([vcPublic,vcPublished])}
  [EtfStruct('Elixir.Profile')]
  TProfileRecord = record
    [EtfField('name')]
    Name: string;
    [EtfField('address')]
    Address: TAddressRecord;
  end;

implementation

end.
