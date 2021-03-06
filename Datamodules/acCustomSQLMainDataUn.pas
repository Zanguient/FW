unit acCustomSQLMainDataUn;

interface

uses
  SysUtils, Classes, Data.DBXFirebird, FMTBcd, SqlExpr, osSQLDataSet, DB,
  osSQLConnection, Provider, osCustomDataSetProvider, osSQLDataSetProvider,
  DBTables, osClientDataSet, Contnrs, osSQLQuery, Forms, Types, Variants,
  Data.DBXInterBase;

const

// Nomes das Tabelas a serem atualizadas (refresh) na aplica��o Cliente
// para fornecer dados para Lookup

  tnUsuario             = 'Usuario';
  tnRecurso             = 'Recurso';
  tnAcao                = 'Acao';
  tnDominio             = 'Dominio';
  tnTipoRecurso         = 'TipoRecurso';
  tnCargo               = 'Cargo';
  tnGrupo               = 'Grupo';
  tnTipoRelatorio       = 'TipoRelatorio';
  tnParametroSistema    = 'ParametroSistema';
  tnTipo                = 'Tipo';
  tnEmpresa             = 'Empresa';

type
  TRefreshTable = class(TObject)
  private
    FTableName: string;
    FVersion: integer;
    FDataSet: TosClientDataSet;
  public
    property Version: integer read FVersion;
    property TableName: string read FTableName write FTableName;
    property DataSet: TosClientDataset read FDataSet write FDataSet;
    procedure RefreshData(NewVersion: integer);
  end;

  TacCustomSQLMainData = class(TDataModule)
    spGetNewSequence: TStoredProc;
    prvFilter: TosSQLDataSetProvider;
    SQLConnection: TosSQLConnection;
    FilterQuery: TosSQLDataSet;
    SQLMonitor: TSQLMonitor;
    SQLConnectionMeta: TosSQLConnection;
    procedure DataModuleCreate(Sender: TObject);
  private
  protected
    BD: string;
    FQueryList: TObjectList;
    FIDHighValue: integer;
    FIDLowValue: integer;
    FTransactionDesc: TTransactionDesc;
    FIDUsuario: Integer;
    FNomeUsuario: String;
    FApelidoUsuario: String;
    FRefreshTableList: TObjectList;
    FProfile: string;
    function selectParamsFileName: string;

  public
    { Public declarations }
    property NomeUsuario: String read FNomeUsuario;
    property IDUsuario: Integer read FIDUsuario;
    property ApelidoUsuario: String read FApelidoUsuario;
    property Profile: string read FProfile;


    constructor Create(AOwner: TComponent); overload; override;
    constructor Create(AOwner: TComponent; BD: String); overload;
    destructor Destroy; override;
    function GetNetUserName: string;

    function GetQuery(meta: boolean = false): TosSQLQuery;
    procedure FreeQuery(Query: TosSQLQuery);

    function GetNextSequence(Nome: string): integer;
    function GetServerDate: TDatetime;
    function GetServerDatetime: TDatetime;
    function InTransaction: boolean;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function GetNewID(nomeGenerator: String = ''): integer;
    function GetGeneratorValue(nomeGenerator: String): integer;
    procedure GetUserInfo(apelido: string);

    procedure LoadRefreshTables;
    procedure RegisterRefreshTable(PTableName: string; PDataSet: TosClientDataSet);
    function FindRefreshTable(PTableName: string): TRefreshTable;
    procedure UpdateVersion(PTableName: string);
    procedure CheckVersion(PTableFilter: string);
    procedure RefreshTables; overload;
    procedure RefreshTable(PTableName: string);
    procedure RefreshTables(PTablesNames: array of string); overload;
    function GeTosSQLDataset: TosSQLDataset;

    function getSQLResult(sqlText: string; connection: TosSQLConnection = nil): variant;
    procedure execSQL(sqlText: string);
  end;

var
  acCustomSQLMainData: TacCustomSQLMainData;

implementation

uses EscolhaConexaoFormUn;

{$R *.dfm}

{ TacCustomSQLMainData }

{-------------------------------------------------------------------------
�Objetivo�� > Verifica a vers�o de tabelas conforme uma pista usada para
                filtrar as Tabelas
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� >
�Observa��es>  Comentario iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
procedure TacCustomSQLMainData.CheckVersion(PTableFilter: string);
var
  Query: TosSQLQuery;
  NomeTabelaField: TStringField;
  VersaoField: TIntegerField;
  RefreshTable: TRefreshTable;
begin
  Query := GetQuery;
  try
    with Query, Query.SQL do
    begin
      Text :=
      'SELECT ' +
        'NomeTabela, ' +
        'Versao ' +
      'FROM ' +
        'VersaoTabela ' + PTableFilter;
      Open;
      if not Eof then
      begin
        NomeTabelaField := TStringField(Fields[0]);
        VersaoField := TIntegerField(Fields[1]);
        while not Eof do
        begin

          Application.ProcessMessages;

          RefreshTable := FindRefreshTable(Trim(NomeTabelaField.Value));
          if Assigned(RefreshTable) then
          begin
            with RefreshTable do
            begin
              if FVersion < VersaoField.Value then
                  RefreshData(VersaoField.Value);
            end;
          end;

          Next;
        end; // while
      end; // if
    end;
  finally
    FreeQuery(Query);
  end;
end;

{-------------------------------------------------------------------------
�Objetivo�� > 
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� >
�Observa��es> Comentario iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
constructor TacCustomSQLMainData.Create(AOwner: TComponent);
begin
  FQueryList := TObjectList.Create(True); // OwnsObjects = True
  FIDHighValue := -1;
  FRefreshTableList := TObjectList.Create(True); // OwnsObjects = True
  inherited;
end;

{-------------------------------------------------------------------------
�Objetivo�� > 
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� > 19.07.2006 - Ricardo N. Acras
�Observa��es>
�Atualiza��o>
�------------------------------------------------------------------------}
constructor TacCustomSQLMainData.Create(AOwner: TComponent; bd: string);
begin
  inherited Create(AOwner);
  self.BD := bd;
  FQueryList := TObjectList.Create(True); // OwnsObjects = True
  FIDHighValue := -1;
  FRefreshTableList := TObjectList.Create(True); // OwnsObjects = True
end;

{-------------------------------------------------------------------------
�Objetivo�� > Procura um objeto TRefreshTable na lista de objetos
                se encontrar retorna a instancia sen�o retorna nulo
�Par�metros > PTableName: Nome da tabela no BD
�Retorno��� >
�Cria��o��� >
�Observa��es> Comentario iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
destructor TacCustomSQLMainData.Destroy;
begin
  FQueryList.Free;
  FRefreshTableList.Free;
  inherited;
end;

function TacCustomSQLMainData.FindRefreshTable(
  PTableName: string): TRefreshTable;
var
  i: integer;
  n : integer;
begin
  n := FRefreshTableList.Count - 1;
  i := 0;
  while (i <= n) and (TRefreshTable(FRefreshTableList.Items[i]).TableName <> PTableName) do
    inc(i);
  if i <= n then
    Result := TRefreshTable(FRefreshTableList.Items[i])
  else
    Result := nil;
end;

{-------------------------------------------------------------------------
�Objetivo�� > Pegar o nome do usu�rio logado no windows 
�Par�metros >
�Retorno��� >
�Cria��o��� >
�Observa��es> Coment�rio Iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
function TacCustomSQLMainData.GetNetUserName: string;
const
    NetUserNameLength: DWORD = 50;
begin
    SetLength(Result, NetUserNameLength);
    SetLength(Result, StrLen(pChar(Result)));
end;

{-------------------------------------------------------------------------
�Objetivo�� > Carrega as tabelas cadastradas no Banco de Dados  para a lista
                de objetos na mem�ria para posterior controle de vers�es de
                dados b�sicos e Refresh nos ClientsDataSets usados para Lookup
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� >
�Observa��es> Comentario iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
procedure TacCustomSQLMainData.LoadRefreshTables;
var
  Query: TosSQLQuery;
  NomeTabelaField: TStringField;
  VersaoField: TIntegerField;
  RefreshTable: TRefreshTable;
begin
  Query := GetQuery;
  try
    with Query, Query.SQL do
    begin
      Text :=
      'SELECT ' +
        'NomeTabela, ' +
        'Versao ' +
      'FROM ' +
        'VersaoTabela ';
      Open;
      if not Eof then
      begin
        NomeTabelaField := TStringField(Fields[0]);
        VersaoField := TIntegerField(Fields[1]);
        FRefreshTableList.Clear;
        while not Eof do
        begin
          RefreshTable := TRefreshTable.Create;
          with RefreshTable do
          begin
            FTableName := Trim(NomeTabelaField.Value);
            FVersion := VersaoField.Value;
            FDataSet := nil;
          end;

          FRefreshTableList.Add(RefreshTable);

          Next;
        end; // while
      end; // if
    end;
  finally
    FreeQuery(Query);
  end;
end;

{-------------------------------------------------------------------------
�Objetivo�� > 
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� > 23.06.2006 - Ricardo N. Acras
�Observa��es>
�Atualiza��o>
�------------------------------------------------------------------------}
function TacCustomSQLMainData.selectParamsFileName: string;
var
  opcaoConexao: TOpcaoConexao;
begin
  result := '';
  if FileExists(ExtractFilePath(Application.ExeName)+'profiles.ini') then
  begin
    opcaoConexao := TEscolhaConexaoForm.execute;
    result := opcaoConexao.nomeArquivo;
    fprofile := opcaoConexao.nome;
  end;
  if result = '' then
    result := 'AppParams.ini';
end;

{-------------------------------------------------------------------------
�Objetivo�� >
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� > 23.06.2006 - Ricardo N. Acras
�Observa��es>
�Atualiza��o> 19.07.2006 - Ricardo N. Acras
                Atualizado para respeitar a configura��o caso um BD tenha
                sido passado na cria��o.
�------------------------------------------------------------------------}
procedure TacCustomSQLMainData.DataModuleCreate(Sender: TObject);
var
   sName : string;
   i : integer;
begin
  SQLConnection.Close;

  with TStringList.Create do
  begin
    try
      if bd='' then
        LoadFromFile(selectParamsFileName)
      else
      begin
        add('BlobSize=-1');
        add('CommitRetain=False');
        add('Database=' + BD);
        add('DriverName=Interbase');
        add('ErrorResourceFile=');
        add('LocaleCode=0000');
        add('Password=masterkey');
        add('RoleName=RoleName');
        add('ServerCharSet=');
        add('SQLDialect=2');
        add('Interbase TransIsolation=ReadCommited');
        add('User_Name=SYSDBA');
        add('WaitOnLocks=True');
      end;
      for i := 0 to Count - 1 do
      begin
        sName := Names[i];
        SQLConnection.Params.Values[sName] := Values[sName];
        SQLConnectionMeta.Params.Values[sName] := Values[sName];
      end;
      if SQLConnectionMeta.Params.Values['DataBaseMeta']<>'' then
        SQLConnectionMeta.Params.Values['Database'] :=
          SQLConnectionMeta.Params.Values['DatabaseMeta'];
    finally
      Free;
    end;
  end;
  SQLConnection.Open;
  SQLConnectionMeta.Open;

  LoadRefreshTables;
end;

{-------------------------------------------------------------------------
�Objetivo�� > Retorna um TosSQLQuery conectado ao SQLConnection 
�Par�metros > meta: indica se o SQLConnection deve ser o de metadados ou o
                de dados.
�Retorno��� >
�Cria��o��� >
�Observa��es> Coment�rio iniciado em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
function TacCustomSQLMainData.GetQuery(meta: boolean): TosSQLQuery;
begin
  Result := TosSQLQuery.Create(Self);
  if meta then
    Result.SQLConnection := SQLConnectionMeta
  else
    Result.SQLConnection := SQLConnection;
end;

procedure TacCustomSQLMainData.FreeQuery(Query: TosSQLQuery);
begin
  Query.Close;
  Query.Destroy;
end;

procedure TacCustomSQLMainData.Commit;
begin
  SQLConnection.Commit(FTransactionDesc);
end;

function TacCustomSQLMainData.GetNewID(nomeGenerator: String): integer;
var
  v: variant;
  qryAux: TosSQLDataSet;
begin
  if nomeGenerator='' then
  begin
    // Se estourou a faixa, l� um novo HighValue
    if (FIDLowValue = 10) or (FIDHighValue = -1) then
    begin
      v := prvFilter.GetIDHigh;
      if v = NULL then
        raise Exception.Create('N�o conseguiu obter o ID do server para inclus�o');
      FIDHighValue := v;
      FIDLowValue := 0;
    end;
    Result := FIDHighValue * 10 + FIDLowValue;
    Inc(FIDLowValue);
  end else
  begin
    qryAux := GeTosSQLDataset;
    try
      qryAux.CommandText := 'select gen_id('+nomeGenerator+', 1) from RDB$DATABASE';
      qryAux.Open;
      result := qryAux.Fields[0].AsInteger;
    finally
      FreeAndNil(qryAux);
    end;
  end;
end;

function TacCustomSQLMainData.GetNextSequence(Nome: string): integer;
begin
  with spGetNewSequence do
  begin
    ParamByName('@Name').Value := Nome;
    ExecProc;
    Result := ParamByName('@Value').Value;
  end;
end;

function TacCustomSQLMainData.GetServerDate: TDatetime;
begin
  Result := StrToDatetime(FormatDatetime('dd/mm/yyyy', GetServerDatetime));
end;

function TacCustomSQLMainData.GetServerDatetime: TDatetime;
var
  Query: TosSQLQuery;
begin
  Query := GetQuery;
  try
    with Query, Query.SQL do
    begin
      Add('select CURRENT_TIMESTAMP as DataHoraServidor from RDB$DATABASE');
      Open;
      Result := Fields[0].AsDatetime;
      Close;
    end;
  finally
    FreeQuery(Query);
  end;
end;

procedure TacCustomSQLMainData.GetUserInfo(apelido: string);
var
  Query: TosSQLQuery;
begin
  Query := GetQuery;
  try
    with Query, Query.SQL do
    begin
      Text :=
        'SELECT ' +
        'Nome, ' +
        'IdUsuario, ' +
        'Apelido ' +
        'FROM ' +
        'Usuario ' +
        'WHERE ' +
        'upper(Apelido) = upper(:Apelido)';
      ParamByName('Apelido').AsString := apelido;
      Open;
      FNomeUsuario := Fields[0].AsString;
      FIDUsuario := Fields[1].AsInteger;
      FApelidoUsuario := Fields[2].AsString;
      Close;
    end;
  finally
    FreeQuery(Query);
  end;
end;

function TacCustomSQLMainData.InTransaction: boolean;
begin
  Result := SQLConnection.InTransaction;
end;

procedure TacCustomSQLMainData.Rollback;
begin
  SQLConnection.Rollback(FTransactionDesc);
end;

procedure TacCustomSQLMainData.StartTransaction;
begin
  if not SQLConnection.InTransaction then
  begin
    FTransactionDesc.TransactionID := 1;
    FTransactionDesc.IsolationLevel := xilREADCOMMITTED;
    SQLConnection.StartTransaction(FTransactionDesc);
  end;
end;

{-------------------------------------------------------------------------
�Objetivo�� > Registra qual o ClientDataset de Lookup deve ser atualizado
                quando uma determinada tabela for alterada, isto � quando
                houver mudan�a de vers�o da tabela
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� >
�Observa��es> Comentarios iniciados em 23.06.2006 por Ricardo N. Acras
�Atualiza��o>
�------------------------------------------------------------------------}
procedure TacCustomSQLMainData.RegisterRefreshTable(PTableName: string;
  PDataSet: TosClientDataSet);
var
  RefreshTable: TRefreshTable;
begin
  RefreshTable := FindRefreshTable(PTableName);
  if Assigned(RefreshTable) then
    RefreshTable.FDataset := PDataSet;

  PDataSet.Open;
end;


{-------------------------------------------------------------------------
�Objetivo�� >   Trata a notifica que uma tabela sofreu altera��o
              registra a evolu��o de ver��o faz refresh dos dados
�Par�metros > Conforme documenta��o
�Retorno��� >
�Cria��o��� >
�Observa��es> Comentarios iniciados em 23.06.2006
�Atualiza��o>
�------------------------------------------------------------------------}
procedure TacCustomSQLMainData.UpdateVersion(PTableName: string);
var
  Query: TosSQLQuery;
begin
  Query := GetQuery;
  try
    with Query, Query.SQL do
    begin
      Text :=
      'UPDATE ' +
        'VersaoTabela ' +
      'SET Versao = Versao + 1' +
      'WHERE ' +
        'NomeTabela = ' + QuotedStr(PTableName);
      ExecSql;
    end;
  finally
    FreeQuery(Query);
  end;

  CheckVersion('WHERE NomeTabela = ' + QuotedStr(PTableName));
end;

procedure TacCustomSQLMainData.RefreshTable(PTableName: string);
begin
  CheckVersion('WHERE NomeTabela = ' + QuotedStr(PTableName));
end;

procedure TacCustomSQLMainData.RefreshTables;
begin
  CheckVersion(''); // Sem filtro
end;

procedure TacCustomSQLMainData.RefreshTables(
  PTablesNames: array of string);
var
  TableFilter: string;
  i: integer;
begin
  if Length(PTablesNames) > 0 then
  begin
    TableFilter := 'WHERE NomeTabela IN (' + QuotedStr(PTablesNames[0]);

    for i := Low(PTablesNames) + 1 to High(PTablesNames) do
      TableFilter := TableFilter + ', ' + QuotedStr(PTablesNames[i]);

    TableFilter := TableFilter + ')';
  end
  else
    TableFilter := '';

  CheckVersion(TableFilter);
end;

procedure SetParamToNull(PParam: TParam; PDatatype: TFieldtype);
begin
  PParam.DataType := PDatatype;
  PParam.Clear;
  PParam.Bound := True;
end;

function TacCustomSQLMainData.GeTosSQLDataset: TosSQLDataset;
begin
  Result := TosSQLDataset.Create(Self);
  Result.SQLConnection := SQLConnection
end;


{ TRefreshTable }

procedure TRefreshTable.RefreshData(NewVersion: integer);
begin
  FVersion := NewVersion;
  if Assigned(FDataSet) then
    with FDataSet do
    begin
      Close;
      Open;
    end;
end;

function TacCustomSQLMainData.getSQLResult(sqlText: string;
  connection: TosSQLConnection = nil): variant;
var
  query: TosSQLQuery;
begin
  query := GetQuery;
  try
    if connection <> nil then
      query.SQLConnection := connection;
    query.SQL.Text := sqlText;
    query.Open;
    if query.Eof then
      result := null
    else
      result := query.Fields[0].Value;
  finally
    FreeAndNil(query);
  end;
end;

procedure TacCustomSQLMainData.execSQL(sqlText: string);
var
  query: TosSQLQuery;
begin
  query := GetQuery;
  try
    query.SQL.Text := sqlText;
    query.ExecSQL;
  finally
    FreeAndNil(query);
  end;
end;


function TacCustomSQLMainData.GetGeneratorValue(
  nomeGenerator: String): integer;
var
  qryAux: TosSQLDataSet;
begin
  qryAux := GeTosSQLDataset;
  try
    qryAux.CommandText := 'select gen_id('+nomeGenerator+', 1) from RDB$DATABASE';
    qryAux.Open;
    result := qryAux.fields[0].AsInteger;
  finally
    FreeAndNil(qryAux);
  end;
end;

end.
