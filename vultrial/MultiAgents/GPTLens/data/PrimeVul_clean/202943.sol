l_noret luaG_runerror (lua_State *L, const char *fmt, ...) {
  CallInfo *ci = L->ci;
  const char *msg;
  va_list argp;
  luaC_checkGC(L);  
  va_start(argp, fmt);
  msg = luaO_pushvfstring(L, fmt, argp);  
  va_end(argp);
  if (isLua(ci))  
    luaG_addinfo(L, msg, ci_func(ci)->p->source, getcurrentline(ci));
  luaG_errormsg(L);
}