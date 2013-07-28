unit DBXJsonUnMarshal;

interface

uses System.Rtti, System.TypInfo, Data.DBXJson, RestJsonUtils;

type
  TJsonValueHelper = class helper for TJsonValue
  private
  public
    function IsJsonNumber: Boolean;
    function IsJsonTrue: Boolean;
    function IsJsonFalse: Boolean;
    function IsJsonString: Boolean;
    function IsJsonNull: Boolean;
    function IsJsonObject: Boolean;
    function IsJsonArray: Boolean;

    function AsJsonNumber: TJSONNumber;
    function AsJsonString: TJSONString;
    function AsJsonObject: TJSONObject;
    function AsJsonArray: TJSONArray;
  end;

  TRttiFieldHelper = class helper for TRttiField
  public
    function GetFieldName: string;
  end;

  TDBXJsonUnmarshal = class
  private
    FContext: TRttiContext;

    function CreateInstance(ATypeInfo: PTypeInfo): TValue;
    function IsList(ATypeInfo: PTypeInfo): Boolean;
    function IsParameterizedType(ATypeInfo: PTypeInfo): Boolean;
    function GetParameterizedType(ATypeInfo: PTypeInfo): TRttiType;
    function GetFieldDefault(AField: TRttiField): TJSONValue;

    function FromJson(ATypeInfo: PTypeInfo; AJSONValue: TJSONValue): TValue;overload;

    function FromClass(ATypeInfo: PTypeInfo; AJSONValue: TJSONValue): TValue;
    function FromList(ATypeInfo: PTypeInfo; AJSONValue: TJSONValue): TValue;
    function FromString(const AJSONValue: TJSONValue): TValue;
    function FromInt(ATypeInfo: PTypeInfo; const AJSONValue: TJSONValue): TValue;
    function FromInt64(ATypeInfo: PTypeInfo; const AJSONValue: TJSONValue): TValue;
    function FromFloat(ATypeInfo: PTypeInfo; const AJSONValue: TJSONValue): TValue;
    function FromChar(const AJSONValue: TJSONValue): TValue;
    function FromWideChar(const AJSONValue: TJSONValue): TValue;
    function FromSet(ATypeInfo: PTypeInfo; const AJSONValue: TJSONValue): TValue;
  public
    constructor Create;
    destructor Destroy; override;

    class function FromJson<T>(AJSONValue: TJSONValue): T;overload;
    class function FromJson<T>(const AJSON: string): T;overload;
  end;

implementation

uses System.SysUtils, System.StrUtils;

{ TDBXJsonUnmarshal }

constructor TDBXJsonUnmarshal.Create;
begin
  FContext := TRttiContext.Create;
end;

function TDBXJsonUnmarshal.CreateInstance(ATypeInfo: PTypeInfo): TValue;
var
  rType: TRttiType;
  mType: TRTTIMethod;
  metaClass: TClass;
begin
  rType := FContext.GetType(ATypeInfo);
  if ( rType <> nil ) then
  begin
    for mType in rType.GetMethods do
    begin
      if mType.HasExtendedInfo and mType.IsConstructor and (Length(mType.GetParameters) = 0) then
      begin
        metaClass := rType.AsInstance.MetaclassType;
        exit(mType.Invoke(metaClass, []).AsObject);
      end;
    end;
  end;

  raise Exception.CreateFmt('No default constructor found for clas "%s".', [GetTypeData(ATypeInfo).ClassType.ClassName]);
end;

destructor TDBXJsonUnmarshal.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TDBXJsonUnmarshal.FromChar(const AJSONValue: TJSONValue): TValue;
begin
  Result := TValue.Empty;

  if AJSONValue.IsJsonString and (Length(AJSONValue.AsJsonString.Value) = 1) then
  begin
    Result := String(AnsiString(AJSONValue.AsJsonString.Value)[1]);
  end;
end;

function TDBXJsonUnmarshal.FromClass(ATypeInfo: PTypeInfo;AJSONValue: TJSONValue): TValue;
var
  f: TRttiField;
  v: TValue;
  vFieldPair: TJSONPair;
  vOldValue: TValue;
  vJsonValue: TJSONValue;
  vOwnedJsonValue: Boolean;
begin
  if AJSONValue.IsJsonObject then
  begin
    Result := CreateInstance(ATypeInfo);
    try
      for f in FContext.GetType(Result.AsObject.ClassType).GetFields do
      begin
        if f.FieldType <> nil then
        begin
          vFieldPair := AJSONValue.AsJsonObject.Get(f.GetFieldName);

          if Assigned(vFieldPair) then
          begin
            vJsonValue := vFieldPair.JsonValue;
            vOwnedJsonValue := False;
          end
          else
          begin
            vJsonValue := GetFieldDefault(f);
            vOwnedJsonValue := True;
          end;

          if Assigned(vJsonValue) then
          begin
            try
              try
                v := FromJson(f.FieldType.Handle, vJsonValue);
              except
                on E: Exception do
                begin
                  raise EJsonInvalidValueForField.CreateFmt('UnMarshalling error for field "%s.%s" : %s',
                                                            [Result.AsObject.ClassName, f.Name, E.Message]);
                end;
              end;

              if not v.IsEmpty then
              begin
                vOldValue := f.GetValue(Result.AsObject);

                if not vOldValue.IsEmpty and vOldValue.IsObject then
                begin
                  vOldValue.AsObject.Free;
                end;

                f.SetValue(Result.AsObject, v);
              end;
            finally
              if vOwnedJsonValue then
                vJsonValue.Free;
            end;
          end;
        end;
      end;
    except
      Result.AsObject.Free;
      raise;
    end;
  end
  else if AJsonValue.IsJsonArray then
  begin
    if IsList(ATypeInfo) and IsParameterizedType(ATypeInfo) then
    begin
      Result := FromList(ATypeInfo, AJSONValue);
    end;
  end
  else
  begin
    Result := TValue.Empty;
  end;
end;

function TDBXJsonUnmarshal.FromFloat(ATypeInfo: PTypeInfo; const AJSONValue: TJSONValue): TValue;
var
  vTemp: TJSONValue;
begin
  if AJSONValue.IsJsonNumber then
  begin
    if ATypeInfo = TypeInfo(TDateTime) then
    begin
      Result := JavaToDelphiDateTime(AJSONValue.AsJsonNumber.AsInt64);
    end
    else
    begin
      TValue.Make(nil, ATypeInfo, Result);

      case GetTypeData(ATypeInfo).FloatType of
        ftSingle: TValueData(Result).FAsSingle := AJSONValue.AsJsonNumber.AsDouble;
        ftDouble: TValueData(Result).FAsDouble := AJSONValue.AsJsonNumber.AsDouble;
        ftExtended: TValueData(Result).FAsExtended := AJSONValue.AsJsonNumber.AsDouble;
        ftComp: TValueData(Result).FAsSInt64 := AJSONValue.AsJsonNumber.AsInt64;
        ftCurr: TValueData(Result).FAsCurr := AJSONValue.AsJsonNumber.AsDouble;
      end;
    end;
  end
  else if AJSONValue.IsJsonString then
  begin
    vTemp := TJSONObject.ParseJSONValue(AJSONValue.AsJsonString.Value);
    try
      if vTemp.IsJsonNumber then
        Result := FromFloat(ATypeInfo, vTemp)
      else
        Result := TValue.Empty;
    finally
      vTemp.Free;
    end;
  end
  else
  begin
    Result := TValue.Empty;
  end;
end;

function TDBXJsonUnmarshal.FromInt(ATypeInfo: PTypeInfo;const AJSONValue: TJSONValue): TValue;
var
  TypeData: PTypeData;
  i: Integer;
  vIsValid: Boolean;
  vTemp: TJSONValue;
  vRttiType: TRttiType;
begin
  if AJSONValue.IsJsonNumber then
  begin
    i := AJSONValue.AsJsonNumber.AsInt;

    TypeData := GetTypeData(ATypeInfo);
    if TypeData.MaxValue > TypeData.MinValue then
      vIsValid := (i >= TypeData.MinValue) and (i <= TypeData.MaxValue)
    else
      vIsValid := (i >= TypeData.MinValue) and (i <= Int64(PCardinal(@TypeData.MaxValue)^));

    if vIsValid then
      TValue.Make(@i, ATypeInfo, Result);
  end
  else if AJSONValue.IsJsonTrue then
  begin
    i := Ord(True);
    TValue.Make(@i, ATypeInfo, Result);
  end
  else if AJSONValue.IsJsonFalse then
  begin
    i := Ord(False);
    TValue.Make(@i, ATypeInfo, Result);
  end
  else if AJSONValue.IsJsonString then
  begin
    vRttiType := FContext.GetType(ATypeInfo);

    if vRttiType is TRttiEnumerationType then
    begin
      if not TryStrToInt(AJSONValue.AsJsonString.Value,i) then
        i := Ord(GetEnumValue(ATypeInfo, AJSONValue.AsJsonString.Value));
      TValue.Make(@i, ATypeInfo, Result);
    end
    else
    begin
      vTemp := TJSONObject.ParseJSONValue(AJSONValue.AsJsonString.Value);
      try
        if not vTemp.IsJsonString then
          Result := FromInt(ATypeInfo, vTemp)
        else
          Result := TValue.Empty;
      finally
        vTemp.Free;
      end;
    end;
  end;
end;

function TDBXJsonUnmarshal.FromInt64(ATypeInfo: PTypeInfo;const AJSONValue: TJSONValue): TValue;
var
  i: Int64;
begin
  if AJSONValue.IsJsonNumber then
  begin
    TValue.Make(nil, ATypeInfo, Result);
    TValueData(Result).FAsSInt64 := AJSONValue.AsJsonNumber.AsInt64;
  end
  else if AJSONValue.IsJsonString and TryStrToInt64(AJSONValue.AsJsonString.Value, i) then
  begin
    TValue.Make(nil, ATypeInfo, Result);
    TValueData(Result).FAsSInt64 := i;
  end
  else
  begin
    Result := TValue.Empty;
  end;
end;

function TDBXJsonUnmarshal.FromJson(ATypeInfo: PTypeInfo; AJSONValue: TJSONValue): TValue;
begin
  begin
    case ATypeInfo.Kind of
      tkChar: Result := FromChar(AJSONValue);
      tkInt64: Result := FromInt64(ATypeInfo, AJSONValue);
      tkEnumeration, tkInteger: Result := FromInt(ATypeInfo, AJSONValue);
      tkSet: Result := fromSet(ATypeInfo, AJSONValue);
      tkFloat: Result := FromFloat(ATypeInfo, AJSONValue);
      tkString, tkLString, tkUString, tkWString: Result := FromString(AJSONValue);
      tkClass: Result := FromClass(ATypeInfo, AJSONValue);
      tkMethod: ;
      tkPointer: ;
      tkWChar: Result := FromWideChar(AJSONValue);
  //    tkRecord: Result := FromRecord;
  //    tkInterface: Result := FromInterface;
  //    tkArray: Result := FromArray;
  //    tkDynArray: Result := FromDynArray;
  //    tkClassRef: Result := FromClassRef;
  //  else
  //    Result := FromUnknown;
    else
      Result := TValue.Empty;
    end;
  end;
end;

class function TDBXJsonUnmarshal.FromJson<T>(const AJSON: string): T;
var
  vJsonValue: TJSONValue;
begin
  vJsonValue := TJSONObject.ParseJSONValue(AJSON);
  try
    if vJsonValue = nil then
    begin
      raise EJsonInvalidSyntax.CreateFmt('Invalid json: "%s"', [AJSON]);
    end;

    Result := FromJson<T>(vJsonValue);
  finally
    vJsonValue.Free;
  end;
end;

class function TDBXJsonUnmarshal.FromJson<T>(AJSONValue: TJSONValue): T;
var
  vUnmarshal: TDBXJsonUnmarshal;
begin
  vUnmarshal := TDBXJsonUnmarshal.Create;
  try
    Result := vUnmarshal.FromJson(TypeInfo(T), AJSONValue).AsType<T>;
  finally
    vUnmarshal.Free;
  end;
end;

function TDBXJsonUnmarshal.FromList(ATypeInfo: PTypeInfo; AJSONValue: TJSONValue): TValue;
var
  method: TRttiMethod;
  vJsonValue: TJSONValue;
  vItem: TValue;
begin
  Result := CreateInstance(ATypeInfo);

  method := FContext.GetType(ATypeInfo).GetMethod('Add');

  for vJsonValue in AJSONValue.AsJsonArray do
  begin
    vItem := FromJson(GetParameterizedType(ATypeInfo).Handle, vJsonValue);

    if not vItem.IsEmpty then
    begin
      method.Invoke(Result.AsObject, [vItem])
    end;
  end;
end;

function TDBXJsonUnmarshal.FromSet(ATypeInfo: PTypeInfo;const AJSONValue: TJSONValue): TValue;
var
  i: Integer;
begin
  if AJSONValue.IsJsonNumber then
  begin
    TValue.Make(nil, ATypeInfo, Result);
    TValueData(Result).FAsSLong := AJSONValue.AsJsonNumber.AsInt;
  end
  else if AJSONValue.IsJsonString and TryStrToInt(AJSONValue.AsJsonString.Value, i) then
  begin
    TValue.Make(nil, ATypeInfo, Result);
    TValueData(Result).FAsSLong := i;
  end
  else
    Result := TValue.Empty;
end;

function TDBXJsonUnmarshal.FromString(const AJSONValue: TJSONValue): TValue;
begin
  if AJSONValue.IsJsonNull then
  begin
    Result := ''
  end
  else if AJSONValue.IsJsonString then       
  begin
    Result := AJSONValue.AsJsonString.Value;
  end
  else
    raise EJsonInvalidValue.CreateFmt('Invalid value "%s".', [AJSONValue.ToString]);
end;

function TDBXJsonUnmarshal.FromWideChar(const AJSONValue: TJSONValue): TValue;
begin
  Result := TValue.Empty;

  if AJSONValue.IsJsonString and (Length(AJSONValue.AsJsonString.Value) = 1) then
  begin
    Result := AJSONValue.AsJsonString.Value[1];
  end;
end;

function TDBXJsonUnmarshal.GetFieldDefault(AField: TRttiField): TJSONValue;
var
  attr: TCustomAttribute;
begin
  for attr in AField.GetAttributes do
  begin
    if attr is JsonDefault then
    begin
      Exit(TJSONObject.ParseJSONValue(JsonDefault(attr).Name));
    end;
  end;

  Result := nil;
end;

function TDBXJsonUnmarshal.GetParameterizedType(ATypeInfo: PTypeInfo): TRttiType;
var
  startPos,
  endPos: Integer;
  vTypeName: String;
begin
  Result := nil;

  startPos := AnsiPos('<', String(ATypeInfo.Name));

  if startPos > 0 then
  begin
    endPos := Pos('>', String(ATypeInfo.Name));

    vTypeName := Copy(String(ATypeInfo.Name), startPos + 1, endPos - Succ(startPos));

    Result := FContext.FindType(vTypeName);
  end;
end;

function TDBXJsonUnmarshal.IsList(ATypeInfo: PTypeInfo): Boolean;
var
  method: TRttiMethod;
begin
  method := FContext.GetType(ATypeInfo).GetMethod('Add');

  Result := (method <> nil) and
            (method.MethodKind = mkFunction) and
            (Length(method.GetParameters) = 1)
end;

function TDBXJsonUnmarshal.IsParameterizedType(ATypeInfo: PTypeInfo): Boolean;
var
  vStartPos: Integer;
begin
  vStartPos := Pos('<', String(ATypeInfo.Name));
  Result := (vStartPos > 0) and (PosEx('>', String(ATypeInfo.Name), vStartPos) > 0);
end;

{ TJsonValueHelper }

function TJsonValueHelper.AsJsonArray: TJSONArray;
begin
  Result := Self as TJSONArray;
end;

function TJsonValueHelper.AsJsonNumber: TJSONNumber;
begin
  Result := Self as TJSONNumber;
end;

function TJsonValueHelper.AsJsonObject: TJSONObject;
begin
  Result := Self as TJSONObject;
end;

function TJsonValueHelper.AsJsonString: TJSONString;
begin
  Result := Self as TJSONString;
end;

function TJsonValueHelper.IsJsonArray: Boolean;
begin
  Result := ClassType = TJSONArray;
end;

function TJsonValueHelper.IsJsonFalse: Boolean;
begin
  Result := ClassType = TJSONFalse;
end;

function TJsonValueHelper.IsJsonNull: Boolean;
begin
  Result := ClassType = TJSONNull;
end;

function TJsonValueHelper.IsJsonNumber: Boolean;
begin
  Result := ClassType = TJSONNumber;
end;

function TJsonValueHelper.IsJsonObject: Boolean;
begin
  Result := ClassType = TJSONObject;
end;

function TJsonValueHelper.IsJsonString: Boolean;
begin
  Result := ClassType = TJSONString;
end;

function TJsonValueHelper.IsJsonTrue: Boolean;
begin
  Result := ClassType = TJSONTrue;
end;

{ TRttiFieldHelper }

function TRttiFieldHelper.GetFieldName: string;
var
  attr: TCustomAttribute;
begin
  for attr in GetAttributes do
  begin
    if attr is JsonName then
    begin
      Exit(JsonName(attr).Name);
    end;
  end;

  Result := Name;
end;

end.
