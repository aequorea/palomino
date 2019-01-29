program dc;  { design compiler }

{ 07-17-90  (1.00)  first release }
{ 02-05-93  (1.01)  allow alpha in pin # with " prefix }

const
  partsize = 100;  { max number of entries in parts table }
  netsize =  2000; { max number of entries in nets table }


type symname=string[8];

type filename=string[40];

type textline=string[132];

type part= record
              name :     symname;
              package :  symname;
              style :    symname;
            end;

type net=record
              name :     symname;
              signal :   symname;
              pin :      symname;
            end;

var

  i,j : integer;
  p   : integer;

  errflag    : boolean;
  firstwrite : boolean;

  parts:  array[1..partsize] of part;
  nets:   array[1..netsize]  of net;

  testnet : net;

  maxpart: integer;            { Top of parts table }
  maxnet:  integer;            { Top of nets table }

  choice                   : filename;
  inputfile,outputfile     : filename;
  inputline,outputline     : textline;
  inputfilvar,outputfilvar : text;

  ch : char;
  val: integer;

  curpart,cursig,curpin: symname;

function findpart(curname:symname) : integer;
var i : integer;
  begin
  i := 1;
  while (parts[i].name<>curname) and (i<maxpart) do
    i := succ(i);
  if i=maxpart then
    findpart := 0
  else
    findpart := i;
  end;

procedure getsym(var name:symname);
var
  i:integer;
  n:integer;
  ch: char;

  begin
  i := 0;
  name := '';
  n := 0;
  ch := upcase(inputline[p+i]);
  if ch=';' then exit;
  if ch='"' then
    begin
    i := succ(i);
    ch := upcase(inputline[p+i]);
    end;
  while (ch<>' ') and (length(inputline)>=p+i) do
    begin
    i := succ(i);
    n := succ(n);
    name[n] := ch;
    ch := upcase(inputline[p+i]);
    end;
  name[0] := chr(n);
  p := p+i;
  while inputline[p]=' ' do p := succ(p);
  end;

procedure dopart;
  begin
  getsym(curpart);
  if findpart(curpart) <> 0 then
    begin
    writeln('Duplicate part definition: ', curpart);
    errflag := true;
    exit;
    end;
  parts[maxpart].name := curpart;
  getsym(parts[maxpart].package);
  getsym(parts[maxpart].style);
  curpart := parts[maxpart].name;
  if maxpart<>partsize then
    maxpart := succ(maxpart)
  else
    begin
    writeln('Error:  parts table overflow');
    errflag := true;
    exit;
    end;
  end;

procedure donet;
  begin
  getsym(curpin);
  getsym(cursig);
  if curpin='0' then
    begin
    writeln('Warning:  ',curpart,'.',cursig,' unassigned');
    exit;
    end;
  j := maxnet-1;
  while (j >=1) and (nets[j].name = curpart) do
    begin
    if nets[j].pin = curpin then
      writeln('Warning:  ',curpart,'.',cursig,' pin ',curpin,' -- multiple pin definition');
(*
    if nets[j].signal = cursig then
      writeln('Warning:  ',curpart,'.',cursig, ' pin ',curpin,' -- multiple signal definition');
*)
    j := pred(j);
    end;
  nets[maxnet].pin := curpin;
  nets[maxnet].signal := cursig;
  nets[maxnet].name := curpart;
  if cursig[1] in ['A'..'Z','a'..'z'] then
    if maxnet<>netsize then
      maxnet := succ(maxnet)
    else
      begin
      writeln('Error:  nets table overflow');
      errflag := true;
      exit;
      end;
  end;

procedure sortnet;
var i    : integer;
var mark : boolean;
  begin
  mark := true;
  while mark do
    begin
    i := 1;
    mark := false;
    while i<maxnet-1 do
      begin
      testnet := nets[i];
      if testnet.signal > nets[i+1].signal then
        begin
        nets[i] := nets[i+1];
        nets[i+1] := testnet;
        mark := true;
        end;
      i := succ(i);
      end;
    end;
  end;

begin  { of main program }

{ Initialization }

maxnet :=  1;  { Init pointers to end of symbol tables }
maxpart := 1;

errflag := false;
firstwrite := false;

{ Open the files }

choice := ParamStr(1);
if length(choice)=0 then
  begin
  write('Source File: '); readln(choice);
  end;
inputfile := concat(choice,'.dc');
assign(inputfilvar,inputfile);
{$I-} reset(inputfilvar); {$I+}
if ioresult<>0 then
  begin
  writeln('Can''t find input file!');
  writeln;
  writeln('Press <return> to continue.');
  readln;
  exit;
  end;
outputfile := concat(choice,'.net');
assign(outputfilvar,outputfile);
rewrite(outputfilvar);

{ Main assembler loop }
while (not eof(inputfilvar)) and (not errflag) do
  begin
  readln(inputfilvar,inputline);       { read an input line }
  p := 1;                              { point to start of line }
  if (inputline<>'') and (inputline[1]<>' ') and (inputline[1]<>';') then
    if inputline[1] in ['0'..'9','"'] then
      donet
    else
      dopart;
  end;
if errflag then
  begin
  writeln('Press <return> to continue.');
  writeln;
  readln;
  exit;
  end;
writeln(maxpart-1,' parts, ',maxnet-1,' nodes');
sortnet;
i := 1;
cursig := '';
while i<maxnet do
  begin
  outputline := '';
  while nets[i].signal <> cursig do
    begin
    cursig := nets[i].signal;
    curpart := nets[i].name;
    if nets[i+1].signal = cursig then
      begin
      if firstwrite then
        writeln(outputfilvar,')');
      firstwrite := true;
      writeln(outputfilvar,'(');
      writeln(outputfilvar,nets[i].signal);
      end
    else
      begin
      writeln('Warning:  ',curpart,'.',cursig,' is singular');
      i := succ(i);
      end;
    end;
  outputline := concat(outputline,nets[i].name);
  outputline := concat(outputline,'-');
  outputline := concat(outputline,nets[i].pin);
  writeln(outputfilvar,outputline);      { write out output line }
  i := succ(i);
  end;
writeln(outputfilvar,')');
close(inputfilvar);
close(outputfilvar);

end.
