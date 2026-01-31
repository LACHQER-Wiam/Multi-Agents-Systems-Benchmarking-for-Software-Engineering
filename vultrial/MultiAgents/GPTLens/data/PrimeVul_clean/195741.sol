bool SingleComponentLSScan::ParseMCU(void)
{ 
#if ACCUSOFT_CODE
  int lines             = m_ulRemaining[0]; 
  UBYTE preshift        = m_ucLowBit + FractionalColorBitsOf();
  struct Line *line     = CurrentLine(0);
  if (m_pFrame->HeightOf() == 0) {
    assert(lines == 0);
    lines = 8;
  }
  assert(m_ucCount == 1);
  if (lines > 8) {
    lines = 8;
  }
  if (m_pFrame->HeightOf() > 0)
    m_ulRemaining[0] -= lines;
  assert(lines > 0);
  do {
    LONG length = m_ulWidth[0];
    LONG *lp    = line->m_pData;
#ifdef DEBUG_LS
    int xpos    = 0;
    static int linenumber = 0;
    printf("\n%4d : ",++linenumber);
#endif
    StartLine(0);
    if (BeginReadMCU(m_Stream.ByteStreamOf())) { 
      do {
        LONG a,b,c,d;   
        LONG d1,d2,d3;  
        GetContext(0,a,b,c,d);
        d1  = d - b;    
        d2  = b - c;
        d3  = c - a;
        if (isRunMode(d1,d2,d3)) {
          LONG run = DecodeRun(length,m_lRunIndex[0]);
          while(run) {
            UpdateContext(0,a);
            *lp++ = a << preshift;
#ifdef DEBUG_LS
            printf("%4d:<%2x> ",xpos++,a);
#endif
            run--,length--;
          }
          if (length) {
            bool negative; 
            bool rtype;    
            LONG errval;   
            LONG merr;     
            LONG rx;       
            UBYTE k;       
            GetContext(0,a,b,c,d);
            rtype  = InterruptedPredictionMode(negative,a,b);
            k      = GolombParameter(rtype);
            merr   = GolombDecode(k,m_lLimit - m_lJ[m_lRunIndex[0]] - 1);
            errval = InverseErrorMapping(merr + rtype,ErrorMappingOffset(rtype,rtype || merr,k));
            rx     = Reconstruct(negative,rtype?a:b,errval);
            UpdateContext(0,rx);
            *lp    = rx << preshift;
#ifdef DEBUG_LS
            printf("%4d:<%2x> ",xpos++,*lp);
#endif
            UpdateState(rtype,errval);
            if (m_lRunIndex[0] > 0)
              m_lRunIndex[0]--;
          } else break; 
        } else {
          UWORD ctxt;
          bool  negative; 
          LONG  px;       
          LONG  rx;       
          LONG  errval;   
          LONG  merr;     
          UBYTE k;        
          d1     = QuantizedGradient(d1);
          d2     = QuantizedGradient(d2);
          d3     = QuantizedGradient(d3);
          ctxt   = Context(negative,d1,d2,d3); 
          px     = Predict(a,b,c);
          px     = CorrectPrediction(ctxt,negative,px);
          k      = GolombParameter(ctxt);
          merr   = GolombDecode(k,m_lLimit);
          errval = InverseErrorMapping(merr,ErrorMappingOffset(ctxt,k));
          UpdateState(ctxt,errval);
          rx     = Reconstruct(negative,px,errval);
          UpdateContext(0,rx);
          *lp    = rx << preshift;
#ifdef DEBUG_LS
          printf("%4d:<%2x> ",xpos++,*lp);
#endif
        }
      } while(++lp,--length);
    } 
    EndLine(0);
    line = line->m_pNext;
  } while(--lines); 
  m_Stream.SkipStuffing();
#endif  
  return false;
}