class CoronaAI extends AIInfo {
  function GetAuthor()      { return "Libor Vilimek"; }
  function GetName()        { return "CoronaAI"; }
  function GetDescription() { return "Built while having Coronavirus myself. The CoronaAI will try to spread to all cities with bus transition. Please increase number of road vehicles to 2500 (on 1024x1024 map)."; }
  function GetVersion()     { return 1; }
  function GetDate()        { return "2020-11-15"; }
  function CreateInstance() { return "CoronaAI"; }
  function GetShortName()   { return "COVD"; }
  function GetAPIVersion()  { return "1.9"; }
}

/* Tell the core we are an AI */
RegisterAI(CoronaAI());
