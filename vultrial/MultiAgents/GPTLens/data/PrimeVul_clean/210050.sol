static void singlevar (LexState *ls, expdesc *var) {
  TString *varname = str_checkname(ls);
  FuncState *fs = ls->fs;
  singlevaraux(fs, varname, var, 1);
  if (var->k == VVOID) {  
    expdesc key;
    singlevaraux(fs, ls->envn, var, 1);  
    lua_assert(var->k != VVOID);  
    codestring(&key, varname);  
    luaK_indexed(fs, var, &key);  
  }
}