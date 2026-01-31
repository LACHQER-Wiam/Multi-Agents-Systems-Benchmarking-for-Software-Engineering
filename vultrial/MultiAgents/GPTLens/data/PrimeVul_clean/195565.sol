String string_number_format(double d, int dec,
                            const String& dec_point,
                            const String& thousand_sep) {
  char *tmpbuf = nullptr, *resbuf;
  char *s, *t;  
  char *dp;
  int integral;
  int tmplen, reslen=0;
  int count=0;
  int is_negative=0;
  if (d < 0) {
    is_negative = 1;
    d = -d;
  }
  if (dec < 0) dec = 0;
  d = php_math_round(d, dec);
  String tmpstr(63, ReserveString);
  tmpbuf = tmpstr.mutableData();
  tmplen = snprintf(tmpbuf, 64, "%.*F", dec, d);
  if (tmplen < 0) return empty_string();
  if (tmpbuf == nullptr || !isdigit((int)tmpbuf[0])) {
    tmpstr.setSize(tmplen);
    return tmpstr;
  }
  if (tmplen >= 64) {
    tmpstr = String(tmplen, ReserveString);
    tmpbuf = tmpstr.mutableData();
    tmplen = snprintf(tmpbuf, tmplen + 1, "%.*F", dec, d);
    if (tmplen < 0) return empty_string();
    if (tmpbuf == nullptr || !isdigit((int)tmpbuf[0])) {
      tmpstr.setSize(tmplen);
      return tmpstr;
    }
  }
  if (dec) {
    dp = strpbrk(tmpbuf, ".,");
  } else {
    dp = nullptr;
  }
  if (dp) {
    integral = dp - tmpbuf;
  } else {
    integral = tmplen;
  }
  if (!thousand_sep.empty()) {
    if (integral + thousand_sep.size() * ((integral-1) / 3) < integral) {
      raise_error("String overflow");
    }
    integral += ((integral-1) / 3) * thousand_sep.size();
  }
  reslen = integral;
  if (dec) {
    reslen += dec;
    if (!dec_point.empty()) {
      if (reslen + dec_point.size() < dec_point.size()) {
        raise_error("String overflow");
      }
      reslen += dec_point.size();
    }
  }
  if (is_negative) {
    reslen++;
  }
  String resstr(reslen, ReserveString);
  resbuf = resstr.mutableData();
  s = tmpbuf+tmplen-1;
  t = resbuf+reslen-1;
  if (dec) {
    int declen = dp ? s - dp : 0;
    int topad = dec > declen ? dec - declen : 0;
    while (topad--) {
      *t-- = '0';
    }
    if (dp) {
      s -= declen + 1; 
      t -= declen;
      memcpy(t + 1, dp + 1, declen);
    }
    if (!dec_point.empty()) {
      memcpy(t + (1 - dec_point.size()), dec_point.data(), dec_point.size());
      t -= dec_point.size();
    }
  }
  while(s >= tmpbuf) {
    *t-- = *s--;
    if (thousand_sep && (++count%3)==0 && s>=tmpbuf) {
      memcpy(t + (1 - thousand_sep.size()),
             thousand_sep.data(),
             thousand_sep.size());
      t -= thousand_sep.size();
    }
  }
  if (is_negative) {
    *t-- = '-';
  }
  resstr.setSize(reslen);
  return resstr;
}