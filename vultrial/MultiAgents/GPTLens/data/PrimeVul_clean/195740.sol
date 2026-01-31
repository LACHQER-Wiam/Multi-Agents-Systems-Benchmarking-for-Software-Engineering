bool SampleInterleavedLSScan::ParseMCU(void)
{
#if ACCUSOFT_CODE
  int lines             = m_ulRemaining[0]; 
  UBYTE preshift        = m_ucLowBit + FractionalColorBitsOf();
  struct Line *line[4];
  UBYTE cx;
  if (m_pFrame->HeightOf() == 0) {
    assert(lines == 0);
    lines = 8;
  }
  if (lines > 8) {
    lines = 8;
  }
  if (m_pFrame->HeightOf() > 0)
    m_ulRemaining[0] -= lines;
  assert(lines > 0);
  assert(m_ucCount < 4);
  for(cx = 0;cx < m_ucCount;cx++) {
    line[cx] = CurrentLine(cx);
  }
  do {
    LONG length = m_ulWidth[0];
    LONG *lp[4];
    for(cx = 0;cx < m_ucCount;cx++) {
      lp[cx] = line[cx]->m_pData;
      StartLine(cx);
    }
    if (BeginReadMCU(m_Stream.ByteStreamOf())) { 
      do {
        LONG a[4],b[4],c[4],d[4]; 
        LONG d1[4],d2[4],d3[4];   
        bool isrun = true;
        for(cx = 0;cx < m_ucCount;cx++) {
          GetContext(cx,a[cx],b[cx],c[cx],d[cx]);
          d1[cx]  = d[cx] - b[cx];    
          d2[cx]  = b[cx] - c[cx];
          d3[cx]  = c[cx] - a[cx];
          if (isrun && !isRunMode(d1[cx],d2[cx],d3[cx]))
            isrun = false;
        }
        if (isrun) {
          LONG run = DecodeRun(length,m_lRunIndex[0]);
          while(run) {
            for(cx = 0;cx < m_ucCount;cx++) {
              UpdateContext(cx,a[cx]);
              *lp[cx]++ = a[cx] << preshift;
            }
            run--,length--;
          }
          if (length) {
            bool negative; 
            LONG errval;   
            LONG merr;     
            LONG rx;       
            UBYTE k;       
            for(cx = 0;cx < m_ucCount;cx++) {
              GetContext(cx,a[cx],b[cx],c[cx],d[cx]);
              negative = a[cx] > b[cx];
              k       = GolombParameter(false);
              merr    = GolombDecode(k,m_lLimit - m_lJ[m_lRunIndex[0]] - 1);
              errval  = InverseErrorMapping(merr,ErrorMappingOffset(false,merr != 0,k));
              rx      = Reconstruct(negative,b[cx],errval);
              UpdateContext(cx,rx);
              *lp[cx]++ = rx << preshift;
              UpdateState(false,errval);
            }
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
          for(cx = 0;cx < m_ucCount;cx++) {
            d1[cx]  = QuantizedGradient(d1[cx]);
            d2[cx]  = QuantizedGradient(d2[cx]);
            d3[cx]  = QuantizedGradient(d3[cx]);
            ctxt    = Context(negative,d1[cx],d2[cx],d3[cx]); 
            px      = Predict(a[cx],b[cx],c[cx]);
            px      = CorrectPrediction(ctxt,negative,px);
            k       = GolombParameter(ctxt);
            merr    = GolombDecode(k,m_lLimit);
            errval  = InverseErrorMapping(merr,ErrorMappingOffset(ctxt,k));
            UpdateState(ctxt,errval);
            rx      = Reconstruct(negative,px,errval);
            UpdateContext(cx,rx);
            *lp[cx]++ = rx << preshift;
          }
        }
      } while(--length);
    } 
    for(cx = 0;cx < m_ucCount;cx++) {
      EndLine(cx);
      line[cx] = line[cx]->m_pNext;
    }
  } while(--lines);
  m_Stream.SkipStuffing();
#endif  
  return false;
}